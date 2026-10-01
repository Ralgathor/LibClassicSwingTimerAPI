-- Get the name of a) this addon loaded seperately, or b) the addon that loaded this as an embedded library
local loadedAddonName = ... 
local MAJOR, MINOR = "LibClassicSwingTimerAPI", 36
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

local frame = CreateFrame("Frame")
local tooltip_name = loadedAddonName .. "Tooltip"
local tooltip = CreateFrame("GameTooltip", tooltip_name, nil, "GameTooltipTemplate")

local C_Timer = C_Timer
local GetTime, CombatLogGetCurrentEventInfo, GetInventoryItemID = GetTime, CombatLogGetCurrentEventInfo, GetInventoryItemID
local UnitAttackSpeed, UnitAura, UnitGUID, UnitRangedDamage, GetPlayerInfoByGUID = UnitAttackSpeed, UnitAura, UnitGUID, UnitRangedDamage, GetPlayerInfoByGUID

local issecretvalue = issecretvalue -- present on 12.x clients and WoW: Forever; nil on classic clients

-- Secret values cannot be compared or used in arithmetic by tainted code; when a
-- fresh read comes back secret (mid-combat on 12.x clients), fall back to the last
-- cached plain value instead of erroring. No-op on classic clients.
local function ResolveSecret(value, fallback)
	if issecretvalue and issecretvalue(value) then
		return fallback
	end
	return value
end

-- UnitAttackSpeed with the 12.x secret-value guard: mid-combat reads in
-- restricted content return secret strings; degrade both speeds to nil so
-- callers fall back to their cached values.
local function ReadAttackSpeeds(unitId)
	local mainSpeed, offSpeed = UnitAttackSpeed(unitId)
	if issecretvalue and (issecretvalue(mainSpeed) or issecretvalue(offSpeed)) then
		return nil, nil
	end
	return mainSpeed, offSpeed
end

-- The GetSpellCooldown global was removed from 11.x+ clients (retail and WoW: Forever).
-- Fall back to C_Spell.GetSpellCooldown (table return) where the old global no longer exists.
local GetSpellCooldownCompat
if GetSpellCooldown then
	GetSpellCooldownCompat = GetSpellCooldown
elseif C_Spell and C_Spell.GetSpellCooldown then
	GetSpellCooldownCompat = function(spell)
		local info = C_Spell.GetSpellCooldown(spell)
		if not info then
			return nil, nil, nil
		end
		return info.startTime, info.duration, info.isEnabled and 1 or 0
	end
end

-- WoW: Forever shares the mainline client (WOW_PROJECT_ID == 1) but runs Classic rules.
-- The project id cannot distinguish it; use the interface build range instead.
local _, _, _, interface = GetBuildInfo()
local isForever = interface >= 16000 and interface < 20000

local isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and not isForever
local isClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local isBCC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_BURNING_CRUSADE
local isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_WRATH_OF_THE_LICH_KING
local isCata = WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CATACLYSM
local isMists = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC
local isClassicOrBCCOrWrathOrCata = isClassic or isBCC or isWrath or isCata or isForever

-- Ranged speed source. On WoW: Forever the third UnitAttackSpeed return is the
-- ranged attack speed (probe-verified on the beta: equal to UnitRangedDamage
-- and to the PLAYER_SWING payload where readable; secret in combat exactly
-- like UnitRangedDamage) and is what the built-in swing timer reads. Classic
-- clients return only main/off-hand speeds there, so they keep UnitRangedDamage.
local function GetRangedSpeed(unitId, fallback)
	local speed
	if isForever then
		speed = ResolveSecret(select(3, UnitAttackSpeed(unitId)), nil)
	end
	if not speed or speed <= 0 then
		speed = ResolveSecret(UnitRangedDamage(unitId), fallback)
	end
	return speed
end

local reset_swing_spells = {}
local reset_swing_on_channel_stop_spells = {}
local prevent_swing_speed_update = {}
local next_melee_spells = {}
local noreset_swing_spells = {}
local prevent_reset_swing_auras = {}
local pause_swing_spells = {}
local ranged_swing = {}
local reset_ranged_swing = {}
local dynamic_haste_spells = {}

local Unit = {
	id = nil,
	GUID = nil,
	class = nil,

	mainSpeed = 0,
	offSpeed = 0,
	rangedSpeed = 0,
	rangedBaseSpeed = 1,
	autoShotCastTime = 0.52,

	lastMainSwing = nil,
	mainExpirationTime = nil,
	firstMainSwing = false,

	lastOffSwing = nil,
	offExpirationTime = nil,
	firstOffSwing = false,

	lastRangedSwing = nil,
	rangedExpirationTime = nil,
	feignDeathTimer = nil,

	mainTimer = nil,
	offTimer = nil,
	rangedTimer = nil,
	calculaDeltaTimer = nil,

	casting = false,
	channeling = false,
	isAttacking = false,
	isShooting = false,
	preventSwingReset = false,
	auraPreventSwingReset = false,

	skipNextAttackSpeedUpdate = nil,
	skipNextAttackSpeedUpdateCount = 0,

	cache = {},
}

function Unit:new(obj)
	obj = obj or {}
	setmetatable(obj, self)
	self.__index = self
	return obj
end

function Unit:CalculateDelta()
	if self.offSpeed > 0 and self.mainExpirationTime ~= nil and self.offExpirationTime ~= nil then
		self.callbacks:Fire("UNIT_SWING_TIMER_DELTA", self.id, self.mainExpirationTime - self.offExpirationTime)
	end
end

-- Clear the unit's transient timers and cast state. Shared by the full
-- re-anchoring on PLAYER_ENTERING_WORLD and PLAYER_TARGET_CHANGED.
function Unit:ResetTransientState()
	if self.feignDeathTimer then
		self.feignDeathTimer:Cancel()
	end
	self.feignDeathTimer = nil

	self.mainTimer = nil
	self.offTimer = nil
	self.rangedTimer = nil
	self.calculaDeltaTimer = nil

	self.casting = false
	self.channeling = false
	self.isAttacking = false
	self.preventSwingReset = false
	self.auraPreventSwingReset = false

	self.skipNextAttackSpeedUpdate = nil
	self.skipNextAttackSpeedUpdateCount = 0
end

function Unit:SwingStart(hand, startTime, isReset)
	if hand == "mainhand" then
		if self.mainTimer and not self.mainTimer:IsCancelled() then
			self.mainTimer:Cancel()
			if not isReset then
				self.callbacks:Fire("UNIT_SWING_TIMER_STOP", self.id, hand)
			end
		end
		self.lastMainSwing = startTime
		local mainSpeed = ResolveSecret(UnitAttackSpeed(self.id), self.mainSpeed)
		self.mainSpeed = mainSpeed
		self.mainExpirationTime = self.lastMainSwing + self.mainSpeed
		self.callbacks:Fire("UNIT_SWING_TIMER_START", self.id, self.mainSpeed, self.mainExpirationTime, hand)
		if self.mainSpeed > 0 and self.mainExpirationTime - GetTime() > 0 then
			self.mainTimer = C_Timer.NewTimer(self.mainExpirationTime - GetTime(), function()
				self:SwingEnd("mainhand")
			end)
		end
	elseif hand == "offhand" then
		if self.offTimer and not self.offTimer:IsCancelled() then
			self.offTimer:Cancel()
			if not isReset then
				self.callbacks:Fire("UNIT_SWING_TIMER_STOP", self.id, hand)
			end
		end
		self.lastOffSwing = startTime
		local _, offSpeed = UnitAttackSpeed(self.id)
		if(self.id == "target" and not self.isPlayer) then
			offSpeed = UnitAttackSpeed(self.id)
		end
		self.offSpeed = ResolveSecret(offSpeed, self.offSpeed) or 0
		self.offExpirationTime = self.lastOffSwing + self.offSpeed
		if self.calculaDeltaTimer then
			self.calculaDeltaTimer:Cancel()
		end
		if self.offSpeed > 0 and self.firstOffSwing == false and self.isAttacking then
			self.offExpirationTime = self.lastOffSwing + (self.offSpeed / 2)
			self:CalculateDelta()
			self.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", self.id, self.offSpeed, self.offExpirationTime, hand)
		elseif self.offSpeed > 0 then
			self.callbacks:Fire("UNIT_SWING_TIMER_START", self.id, self.offSpeed, self.offExpirationTime, hand)
			self.calculaDeltaTimer = C_Timer.NewTimer(self.offSpeed / 2, function()
				self:CalculateDelta()
			end)
		end
		if self.offSpeed > 0 and self.offExpirationTime - GetTime() > 0 then
			self.offTimer = C_Timer.NewTimer(self.offExpirationTime - GetTime(), function()
				self:SwingEnd("offhand")
			end)
		end
	elseif hand == "ranged" then
		if self.rangedTimer and not self.rangedTimer:IsCancelled() then
			self.rangedTimer:Cancel()
			if not isReset then
				self.callbacks:Fire("UNIT_SWING_TIMER_STOP", self.id, hand)
			end
		end
		self.rangedSpeed = GetRangedSpeed(self.id, self.rangedSpeed) or 0
		if self.rangedSpeed > 0 then
			self.lastRangedSwing = startTime
			self.rangedExpirationTime = self.lastRangedSwing + self.rangedSpeed
			self.autoShotCastTime = 0.52 * (self.rangedSpeed / self.rangedBaseSpeed)
			self.callbacks:Fire("UNIT_SWING_TIMER_START", self.id, self.rangedSpeed, self.rangedExpirationTime, hand)
			if self.rangedExpirationTime - GetTime() > 0 then
				self.rangedTimer = C_Timer.NewTimer(self.rangedExpirationTime - GetTime(), function()
					self:SwingEnd("ranged")
				end)
			end
		end
	end
end

function Unit:SwingEnd(hand)
	if hand == "mainhand" and self.mainTimer and not self.mainTimer:IsCancelled() then
		self.mainTimer:Cancel()
	elseif hand == "offhand" and self.offTimer and not self.offTimer:IsCancelled() then
		self.offTimer:Cancel()
	elseif hand == "ranged" and self.rangedTimer and not self.rangedTimer:IsCancelled() then
		self.rangedTimer:Cancel()
	end
	if (self.class == "DRUID" or self.class == "PALADIN") and self.skipNextAttackSpeedUpdate then
		self.skipNextAttackSpeedUpdate = nil
		lib:UNIT_ATTACK_SPEED("UNIT_ATTACK_SPEED", self.GUID)
	end
	self.callbacks:Fire("UNIT_SWING_TIMER_STOP", self.id, hand)
	if (self.casting or self.channeling) and self.isAttacking and hand ~= "ranged" then
		-- Retail clips only the main-hand swing; classic-era clients clip both hands.
		if (isRetail and hand == "mainhand") or isClassicOrBCCOrWrathOrCata or isMists then
			local now = GetTime()
			self:SwingStart(hand, now, true)
			self.callbacks:Fire("UNIT_SWING_TIMER_CLIPPED", self.id, hand)
		end
	end
end

function Unit:GetRangedBaseSpeed()
	-- Default speed
	local speed = 1
	local weapon_id = GetInventoryItemID("player", INVSLOT_RANGED)

	if self.cache[weapon_id] then
		return self.cache[weapon_id]
	elseif not weapon_id then
		return speed
	end

	local font_string_base = tooltip_name .. "TextRight"
	local speed_pattern = SPEED .. " (%d%.%d%d)"

	tooltip:ClearLines()
	tooltip:SetItemByID(weapon_id)
	for i = 1, tooltip:NumLines() do
		local fontString = _G[font_string_base .. i]
		local text = fontString:GetText()
		if text then
			local match = text:match(speed_pattern)
			if match then
				speed = match
				break
			end
		end
	end

	self.cache[weapon_id] = speed
	return speed
end

lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)

function lib:getUnit(unit)
	if not self.player or not self.target then
		return nil
	end
	-- UnitGUID("target") returns a SECRET string mid-combat in restricted
	-- content on WoW: Forever and 12.x clients (observed in a dungeon: every
	-- comparison against the cached target GUID errored with "attempt to
	-- compare field 'GUID' (a secret string value)"). A secret GUID degrades
	-- to matching by unit id only - the spellcast and attack-speed handlers
	-- pass unit ids ("player"/"target"), so target handling is unaffected.
	local playerGUID = ResolveSecret(self.player.GUID, nil)
	local targetGUID = ResolveSecret(self.target.GUID, nil)
	if playerGUID == unit or self.player.id == unit then
		return self.player
	elseif targetGUID == unit or self.target.id == unit then
		return self.target
	end
end

function lib:SwingTimerInfo(hand)
	if hand == "mainhand" then
		return self.player.mainSpeed, self.player.mainExpirationTime, self.player.lastMainSwing
	elseif hand == "offhand" then
		return self.player.offSpeed, self.player.offExpirationTime, self.player.lastOffSwing
	elseif hand == "ranged" then
		return self.player.rangedSpeed, self.player.rangedExpirationTime, self.player.lastRangedSwing
	end
end

function lib:UnitSwingTimerInfo(unitId, hand)
	local unit = lib:getUnit(unitId)
	if not unit then
		return
	end
	if hand == "mainhand" then
		return unit.mainSpeed, unit.mainExpirationTime, unit.lastMainSwing
	elseif hand == "offhand" then
		return unit.offSpeed, unit.offExpirationTime, unit.lastOffSwing
	elseif hand == "ranged" then
		return unit.rangedSpeed, unit.rangedExpirationTime, unit.lastRangedSwing
	end
end

function lib:ADDON_LOADED(_, addOnName)
	-- Check to see if this is the addon that loaded the library
	if addOnName ~= loadedAddonName then
		return
	end

	self.player = Unit:new({id="player"})
	self.player.callbacks = self.callbacks
	self.target = Unit:new({id="target", class="TARGET"})
	self.target.callbacks = self.callbacks
end

function lib:PLAYER_ENTERING_WORLD()
	self.player.GUID = UnitGUID("player")
	self.player.class = select(2,GetPlayerInfoByGUID(self.player.GUID))

	local mainSpeed, offSpeed = ReadAttackSpeeds("player")
	local now = GetTime()

	self.player.mainSpeed = mainSpeed or 3 -- some dummy non-zero value to prevent infinities
	self.player.offSpeed = offSpeed or 0
	self.player.rangedSpeed = GetRangedSpeed("player", self.player.rangedSpeed) or 0

	self.player.lastMainSwing = now
	-- Parked, like the PLAYER_TARGET_CHANGED seed: no swing can be in flight at
	-- a loading screen, so a future expiration would be an uncompletable swing.
	self.player.mainExpirationTime = self.player.lastMainSwing
	self.player.firstMainSwing = false

	self.player.lastOffSwing = now
	self.player.offExpirationTime = self.player.lastOffSwing
	self.player.firstOffSwing = false

	self.player.lastRangedSwing = now
	self.player.rangedExpirationTime = self.player.lastRangedSwing
	self.player:ResetTransientState()

	self.callbacks:Fire("UNIT_SWING_TIMER_INFO_INITIALIZED", self.player.id)
end

function lib:PLAYER_TARGET_CHANGED()
	self.target.GUID = UnitGUID("target")

	self.target.isPlayer = UnitIsPlayer("target")
	local mainSpeed, offSpeed = ReadAttackSpeeds("target")
	if(not self.target.isPlayer) then
		offSpeed = mainSpeed
	end
	local now = GetTime()

	self.target.mainSpeed = mainSpeed or 3 -- some dummy non-zero value to prevent infinities
	self.target.offSpeed = offSpeed or 0
	self.target.rangedSpeed = GetRangedSpeed("target", self.target.rangedSpeed) or 0

	self.target.lastMainSwing = now
	self.target.mainExpirationTime = self.target.lastMainSwing
	self.target.firstMainSwing = false

	self.target.lastOffSwing = now
	self.target.offExpirationTime = self.target.lastMainSwing
	self.target.firstOffSwing = false

	self.target.lastRangedSwing = now
	self.target.rangedExpirationTime = self.target.lastRangedSwing
	self.target:ResetTransientState()

	self.callbacks:Fire("UNIT_SWING_TIMER_INFO_INITIALIZED", self.target.id)
end

-- Parry haste shared by the classic CLEU path and the WoW: Forever UNIT_COMBAT
-- path (lib:UNIT_COMBAT): shorten an in-flight main-hand swing after a defensive
-- parry by this unit. Engine rule (the documented classic rule, verified against
-- this engine by a combat-log-only join on build 70124, 2026-09-30, two weapon
-- speeds): more than 60% of the swing remaining -> reduce by 40% of weapon speed;
-- between 20% and 60% -> reduce to 20% of weapon speed remaining (the floor);
-- 20% or less -> no effect. The floor measured at 0.484 s on a 2.4 s weapon and
-- 0.685 s on a 3.4 s weapon (20% at both speeds, +/-20 ms); full-cut landings
-- match to milliseconds; parries under 20% remaining do nothing.
-- On WoW: Forever the event streams are skewed: PLAYER_SWING fires ~0.45 s
-- before the swing's attack resolves, and the UNIT_COMBAT parry dispatch trails
-- the combat log's record of the same parry by 0.10-0.30 s (two clusters), so a
-- UNIT_COMBAT parry stamp sits ~0.55-0.72 s after the engine's parry
-- instant relative to the PLAYER_SWING-anchored timer (two dispatch
-- clusters, 0.55 and 0.72; their midpoint 0.65 is used). The parry is
-- therefore back-dated by that skew before the rule is applied; the classic
-- CLEU path needs no correction (swings and parries arrive on the same stream).
-- The earlier "no 20% floor / early parries discarded" readings were artifacts
-- of measuring UNIT_COMBAT parry stamps against PLAYER_SWING anchors without
-- this correction; see docs/FOREVER_API_FINDINGS.md section 8.10 (final entry)
-- and docs/evidence/README.md.
local FOREVER_PARRY_EVENT_SKEW = 0.65

function lib:ApplyParryHaste(unit)
	if not unit then
		return
	end
	if not (unit.mainTimer and not unit.mainTimer:IsCancelled()) then
		return
	end
	local now = GetTime()
	local speed = unit.mainSpeed
	if not speed or speed <= 0 then
		return
	end
	local remaining = unit.mainExpirationTime - now
	if remaining <= 0 then
		return
	end
	-- Engine-domain remaining at the parry instant; on WoW: Forever the
	-- UNIT_COMBAT event arrives ~FOREVER_PARRY_EVENT_SKEW after that instant.
	local skew = isForever and FOREVER_PARRY_EVENT_SKEW or 0
	local engineRemaining = remaining + skew
	if engineRemaining >= speed or engineRemaining <= 0.2 * speed then
		return -- before this swing started, or under the 20% floor: no effect
	end
	unit.mainTimer:Cancel()
	if engineRemaining > 0.6 * speed then
		engineRemaining = engineRemaining - 0.4 * speed -- full cut
	else
		engineRemaining = 0.2 * speed -- floored at 20% of the swing
	end
	remaining = engineRemaining - skew
	if remaining < 0 then
		remaining = 0 -- the engine has already fired (or fires at its next update)
	end
	unit.mainExpirationTime = now + remaining
	self.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", unit.id, unit.mainSpeed, unit.mainExpirationTime, "mainhand")
	if unit.mainSpeed > 0 and unit.mainExpirationTime - now > 0 then
		unit.mainTimer = C_Timer.NewTimer(unit.mainExpirationTime - now, function()
			unit:SwingEnd("mainhand")
		end)
	end
end


--[[	WoW: Forever dynamic-haste rescale (capture-verified 2026-09-30, build
	70124): applying one of the dynamic_haste_spells auras mid-swing shortens
	the in-flight swing proportionally - the same rule as the classic
	UNIT_ATTACK_SPEED rescale, expressed as remaining time divided by the
	haste factor. Both hands (verified: SnD affects main and off hand).
	Ranged is excluded: no dynamic-haste ranged spell is verified.
	Young-swing guard: a cast landing at a swing boundary arrives after the
	PLAYER_SWING anchor has already re-anchored with the hasted payload (the
	engine applies the aura before the anchor fires - observed in the 2026-09-30
	capture: a cast SUCCEEDED at the same instant as an anchor already reporting
	the new speed), so a swing younger than 50 ms is left alone: rescaling it
	would double-apply the factor, and it would gain less than 5 ms anyway. ]]
function lib:ApplyDynamicHaste(unit, factor)
	local now = GetTime()
	if unit.mainSpeed > 0 and unit.mainExpirationTime and unit.mainExpirationTime > now
		and unit.lastMainSwing and now - unit.lastMainSwing > 0.05 then
		if unit.mainTimer then
			unit.mainTimer:Cancel()
		end
		unit.mainSpeed = unit.mainSpeed / factor
		unit.mainExpirationTime = now + (unit.mainExpirationTime - now) / factor
		self.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", unit.id, unit.mainSpeed, unit.mainExpirationTime, "mainhand")
		unit.mainTimer = C_Timer.NewTimer(unit.mainExpirationTime - now, function()
			unit:SwingEnd("mainhand")
		end)
	end
	if unit.offSpeed > 0 and unit.offExpirationTime and unit.offExpirationTime > now
		and unit.lastOffSwing and now - unit.lastOffSwing > 0.05 then
		if unit.offTimer then
			unit.offTimer:Cancel()
		end
		unit.offSpeed = unit.offSpeed / factor
		unit.offExpirationTime = now + (unit.offExpirationTime - now) / factor
		self.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", unit.id, unit.offSpeed, unit.offExpirationTime, "offhand")
		unit.offTimer = C_Timer.NewTimer(unit.offExpirationTime - now, function()
			unit:SwingEnd("offhand")
		end)
	end
end

function lib:COMBAT_LOG_EVENT_UNFILTERED(_, ts, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, amount, overkill, _, resisted, _, _, _, _, _, isOffHand)
	local now = GetTime()
	-- Parry haste: the defender of a parried attack gets its next main-hand swing sooner.
	-- Handled before the source lookup so a parry by an untracked attacker still applies.
	if subEvent == "SWING_MISSED" and amount == "PARRY" then
		self:ApplyParryHaste(lib:getUnit(destGUID))
	end
	local unit = lib:getUnit(sourceGUID)
	if not unit then
		return
	end
	if (subEvent == "SWING_DAMAGE" or subEvent == "SWING_MISSED") then
		if subEvent == "SWING_MISSED" then
			isOffHand = overkill
		end
		if isOffHand then
			unit.firstOffSwing = true
			unit:SwingStart("offhand", now, false)
		else
			unit.firstMainSwing = true
			unit:SwingStart("mainhand", now, false)
		end
		if isWrath or isCata then
			unit:SwingStart("ranged", now, true)
		end
	elseif (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REMOVED") then
		local spell = amount
		if spell and prevent_swing_speed_update[spell] and (GetTime() < unit.mainExpirationTime) then
			unit.skipNextAttackSpeedUpdate = now
			unit.skipNextAttackSpeedUpdateCount = 2
		end
		if spell and prevent_reset_swing_auras[spell] then
			unit.auraPreventSwingReset = subEvent == "SPELL_AURA_APPLIED"
		end
	elseif (subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_MISSED") then
		local spell = amount
		if reset_ranged_swing[spell] then
			if (isRetail or isMists) then
				unit:SwingStart("mainhand", GetTime(), true)
			else
				unit:SwingStart("ranged", GetTime(), true)
			end
		end
	elseif subEvent == "SPELL_CAST_START" then
		local spell = amount
		if isClassic and spell and ranged_swing[spell] and now > (unit.rangedExpirationTime - unit.autoShotCastTime) then
			if unit.rangedTimer and not unit.rangedTimer:IsCancelled() then
				unit.rangedTimer:Cancel()
			end
			unit.rangedExpirationTime = now + unit.autoShotCastTime
			unit.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", unit.id, unit.rangedSpeed, unit.rangedExpirationTime, "ranged")
			if unit.rangedExpirationTime - now > 0 then
				unit.rangedTimer = C_Timer.NewTimer(unit.rangedExpirationTime - now, function()
					unit:SwingEnd("ranged")
				end)
			end
		end
	end
end

--[[	WoW: Forever native swing event (registered on Forever only).
	Payload verified on the beta: swingDuration is the weapon swing speed as a
	plain number (readable even in restricted content, where UnitAttackSpeed
	returns secret values); swingType is Enum.PlayerSwingType
	(MainHand=0, OffHand=1, Ranged=2). ]]
function lib:PLAYER_SWING(_, swingDuration, swingType)
	if not isForever then
		return
	end
	if issecretvalue and issecretvalue(swingDuration) then
		return -- swing anchor without a usable duration; do not guess one
	end
	if type(swingDuration) ~= "number"
		or swingDuration ~= swingDuration -- NaN
		or swingDuration <= 0
		or swingDuration == math.huge then
		return -- malformed payload; do not cache it as a weapon speed
	end
	local hand
	if swingType == 0 then
		hand = "mainhand"
	elseif swingType == 1 then
		hand = "offhand"
	elseif swingType == 2 then
		hand = "ranged"
	else
		return
	end
	local unit = self.player
	if not unit then
		return
	end
	-- WoW: Forever dynamic-haste state: the anchor payload is the true speed
	-- every swing, so it doubles as the expiry signal - once it reports a
	-- speed above the hasted cache again, the aura is gone and a recast must
	-- rescale once more.
	if unit.dynamicHasteActive then
		local cachedSpeed
		if hand == "mainhand" then
			cachedSpeed = unit.mainSpeed
		elseif hand == "offhand" then
			cachedSpeed = unit.offSpeed
		else
			cachedSpeed = unit.rangedSpeed
		end
		if cachedSpeed and cachedSpeed > 0 and swingDuration > cachedSpeed * 1.02 then
			unit.dynamicHasteActive = nil
		end
	end

	-- Cache the event-provided speed first so the UnitAttackSpeed reads inside
	-- SwingStart fall back to it when they return secret values.
	if hand == "mainhand" then
		unit.firstMainSwing = true
		unit.mainSpeed = swingDuration
	elseif hand == "offhand" then
		unit.firstOffSwing = true
		unit.offSpeed = swingDuration
	else
		unit.rangedSpeed = swingDuration
	end
	unit:SwingStart(hand, GetTime(), false)
end

--[[	WoW: Forever parry signal (registered on Forever only). CLEU is refused on
	that client, but UNIT_COMBAT fires for the defender of a combat action, once
	per unit token that names it, with plain unitIDs mid-combat (probe-verified
	2026-09-30, build 70124). A defensive parry by the player fires the "player"
	token; the player's attack being parried fires the defender's own tokens. ]]
function lib:UNIT_COMBAT(_, unitTarget, action)
	if unitTarget ~= "player" or action ~= "PARRY" then
		return
	end
	self:ApplyParryHaste(self.player)
end

function lib:UNIT_ATTACK_SPEED(_, unitGUID)
	local unit = lib:getUnit(unitGUID)
	if not unit then
		return
	end
	local now = GetTime()
	if
		unit.skipNextAttackSpeedUpdate
		and (now - unit.skipNextAttackSpeedUpdate) < 0.04
		and unit.skipNextAttackSpeedUpdateCount > 0
	then
		unit.skipNextAttackSpeedUpdateCount = unit.skipNextAttackSpeedUpdateCount - 1
		return
	end
	local mainSpeedNew, offSpeedNew = UnitAttackSpeed(unit.id)
	mainSpeedNew = ResolveSecret(mainSpeedNew, unit.mainSpeed)
	offSpeedNew = ResolveSecret(offSpeedNew, unit.offSpeed)
	if(unit.id == "target" and not unit.isPlayer) then
		offSpeedNew = mainSpeedNew
	end
	offSpeedNew = offSpeedNew or 0
	if mainSpeedNew > 0 and unit.mainSpeed > 0 and mainSpeedNew ~= unit.mainSpeed and not isForever then
		if unit.mainTimer then
			unit.mainTimer:Cancel()
		end
		local multiplier = mainSpeedNew / unit.mainSpeed
		local timeLeft = (unit.lastMainSwing + unit.mainSpeed - now) * multiplier
		unit.mainSpeed = mainSpeedNew
		unit.mainExpirationTime = now + timeLeft
		self.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", unit.id, unit.mainSpeed, unit.mainExpirationTime, "mainhand")
		if unit.mainSpeed > 0 and unit.mainExpirationTime - GetTime() > 0 then
			unit.mainTimer = C_Timer.NewTimer(unit.mainExpirationTime - GetTime(), function()
				unit:SwingEnd("mainhand")
			end)
		end
	end
	if offSpeedNew > 0 and unit.offSpeed > 0 and offSpeedNew ~= unit.offSpeed and not isForever then
		if unit.offTimer then
			unit.offTimer:Cancel()
		end
		local multiplier = offSpeedNew / unit.offSpeed
		local timeLeft = (unit.lastOffSwing + unit.offSpeed - now) * multiplier
		unit.offSpeed = offSpeedNew
		unit.offExpirationTime = now + timeLeft
		if unit.calculaDeltaTimer ~= nil then
			unit.calculaDeltaTimer:Cancel()
		end
		self.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", unit.id, unit.offSpeed, unit.offExpirationTime, "offhand")
		if unit.offSpeed > 0 and unit.offExpirationTime - GetTime() > 0 then
			unit.offTimer = C_Timer.NewTimer(unit.offExpirationTime - GetTime(), function()
				unit:SwingEnd("offhand")
			end)
		end
	end
	local rangedSpeedNew = GetRangedSpeed(unit.id, unit.rangedSpeed) or 0
	if rangedSpeedNew > 0 and unit.rangedSpeed > 0 and rangedSpeedNew ~= unit.rangedSpeed and not isForever then
		if unit.rangedTimer then
			unit.rangedTimer:Cancel()
		end
		local multiplier = rangedSpeedNew / unit.rangedSpeed
		local timeLeft = (unit.lastRangedSwing + unit.rangedSpeed - now) * multiplier
		unit.rangedSpeed = rangedSpeedNew
		unit.rangedExpirationTime = now + timeLeft
		self.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", unit.id, unit.rangedSpeed, unit.rangedExpirationTime, "ranged")
		if unit.rangedSpeed > 0 and unit.rangedExpirationTime - GetTime() > 0 then
			unit.rangedTimer = C_Timer.NewTimer(unit.rangedExpirationTime - GetTime(), function()
				unit:SwingEnd("ranged")
			end)
		end
	end
end

function lib:UNIT_SPELLCAST_INTERRUPTED_OR_FAILED(_, unitType, _, spell)
	local unit = lib:getUnit(unitType)
	if not unit then
		return
	end
	spell = ResolveSecret(spell, nil)
	unit.casting = false
	unit.channeling = false
	if spell and pause_swing_spells[spell] and unit.pauseSwingTime then
		unit.pauseSwingTime = nil
		if unit.mainSpeed > 0 then
			if unit.mainExpirationTime < GetTime() and unit.isAttacking then
				unit.mainExpirationTime = unit.mainExpirationTime + unit.mainSpeed
			end
			self.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", unit.id, unit.mainSpeed, unit.mainExpirationTime, "mainhand")
			if unit.mainExpirationTime - GetTime() > 0 then
				unit.mainTimer = C_Timer.NewTimer(unit.mainExpirationTime - GetTime(), function()
					unit:SwingEnd("mainhand")
				end)
			end
		end
		if unit.offSpeed > 0 then
			if unit.offExpirationTime < GetTime() and unit.isAttacking then
				unit.offExpirationTime = unit.offExpirationTime + unit.offSpeed
			end
			self.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", unit.id, unit.offSpeed, unit.offExpirationTime, "offhand")
			if unit.offExpirationTime - GetTime() > 0 then
				unit.offTimer = C_Timer.NewTimer(unit.offExpirationTime - GetTime(), function()
					unit:SwingEnd("offhand")
				end)
			end
		end
	end
end
function lib:UNIT_SPELLCAST_INTERRUPTED(...)
	self:UNIT_SPELLCAST_INTERRUPTED_OR_FAILED(...)
end
function lib:UNIT_SPELLCAST_FAILED(...)
	self:UNIT_SPELLCAST_INTERRUPTED_OR_FAILED(...)
end

function lib:UNIT_SPELLCAST_SUCCEEDED(_, unitType, _, spell)
	local unit = lib:getUnit(unitType)
	if not unit then
		return
	end
	-- UNIT_SPELLCAST_* payloads can carry secret spell IDs in restricted
	-- content (observed on the target unit mid-fight on WoW: Forever); secret
	-- values cannot be compared or used as table keys, and there is no cached
	-- fallback for an event payload. A secret spell ID degrades to "unknown
	-- spell": the cast-state logic below still runs, the spell-ID list
	-- lookups are skipped.
	spell = ResolveSecret(spell, nil)
	local now = GetTime()
	-- On WoW: Forever the native PLAYER_SWING anchors the consumed swing as well
	-- (verified: a queued next-melee ability double-anchored with identical expiry),
	-- so the SUCCEEDED anchor is skipped there like the ranged Auto Shot one.
	if spell ~= nil and next_melee_spells[spell] and not isForever then
		unit:SwingStart("mainhand", now, false)
		if isWrath or isCata then
			unit:SwingStart("ranged", now, true)
		end
	end
	if (spell and reset_swing_spells[spell]) or (unit.casting and not unit.preventSwingReset) then
		if isRetail then		
			unit:SwingStart("mainhand", now, true)
		else
			-- Do not skip the attack speed update if we reset the timer
			unit.skipNextAttackSpeedUpdate = nil
			unit:SwingStart("mainhand", now, true)
			unit:SwingStart("offhand", now, true)
		end
	end
	-- On WoW: Forever the native PLAYER_SWING is the ranged anchor; the SUCCEEDED
	-- anchor would double-fire every shot (identical STOP/START pairs per arrow).
	if spell and ranged_swing[spell] and not isForever then
		if (isRetail or isMists) then		
			unit:SwingStart("mainhand", now, false)
		else
			unit:SwingStart("ranged", now, false)
		end
	end
	if spell and pause_swing_spells[spell] and unit.pauseSwingTime then
		local offset = now - unit.pauseSwingTime
		unit.pauseSwingTime = nil
		if unit.mainSpeed > 0 then
			unit.mainExpirationTime = unit.mainExpirationTime + offset
			self.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", unit.id, unit.mainSpeed, unit.mainExpirationTime, "mainhand")
			if unit.mainExpirationTime - now > 0 then
				unit.mainTimer = C_Timer.NewTimer(unit.mainExpirationTime - now, function()
					unit:SwingEnd("mainhand")
				end)
			end
		end
		if unit.offSpeed > 0 then
			unit.offExpirationTime = unit.offExpirationTime + offset
			self.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", unit.id, unit.offSpeed, unit.offExpirationTime, "offhand")
			if unit.offExpirationTime - now > 0 then
				unit.offTimer = C_Timer.NewTimer(unit.offExpirationTime - now, function()
					unit:SwingEnd("offhand")
				end)
			end
		end
	end	
	-- WoW: Forever dynamic-haste mid-swing rescale (capture-verified
	-- 2026-09-30): the engine shortens the in-flight swing when one of these
	-- auras is applied, and the cast success is the only plain mid-combat
	-- speed signal on that client (UnitAttackSpeed is secret in combat). A
	-- recast while the aura is already up does NOT rescale again (the engine
	-- does not - verified), so the rescale is guarded by a flag that
	-- lib:PLAYER_SWING clears when an anchor reports the aura is gone.
	if isForever and spell and dynamic_haste_spells[spell] then
		if unit.dynamicHasteActive ~= spell then
			unit.dynamicHasteActive = spell
			self:ApplyDynamicHaste(unit, dynamic_haste_spells[spell])
		end
	end

	-- The auto-attack toggle must not clear the cast-state flags. Classic clients
	-- fire the toggle as 6603; WoW: Forever fires it as 6803 (verified in-game).
	local isAttackToggle = spell == 6603 or (isForever and spell == 6803)
	if not isAttackToggle then
		unit.preventSwingReset = unit.auraPreventSwingReset or false
	end
	if unit.casting and not isAttackToggle then
		unit.casting = false
	end
	if spell == 5384 then -- 5384=Feign Death
		if unit.feignDeathTimer then
			unit.feignDeathTimer:Cancel()
		end
		local ticks = 0
		unit.feignDeathTimer = C_Timer.NewTicker(0.1, function() -- Start watching FD CD
			local start, _, enabled = GetSpellCooldownCompat and GetSpellCooldownCompat(spell)
			if enabled == 1 then -- Reset ranged swing when FD CD start
				start = ResolveSecret(start, GetTime()) -- cooldown startTime is secret in restricted content
				unit:SwingStart("mainhand", start, true)
				unit:SwingStart("offhand", start, true)
				if isClassicOrBCCOrWrathOrCata then
					unit:SwingStart("ranged", start, true)
				end
				if unit.feignDeathTimer then
					unit.feignDeathTimer:Cancel()
				end
			else
				ticks = ticks + 1
				if ticks >= 100 then -- Give up after 10 s if the FD cooldown is never observed
					unit.feignDeathTimer:Cancel()
				end
			end
		end)
	end
	if isMists and spell == 114089 then  -- Wind Lash main hand cast
		unit.firstMainSwing = true
		unit:SwingStart("mainhand", now, false)
	end
	if isMists and spell == 114093 then  -- Wind Lash off-hand cast
		unit.firstOffSwing = true
		unit:SwingStart("offhand", now, false)
	end
end

function lib:UNIT_SPELLCAST_START(_, unitType, _, spell)
	local unit = lib:getUnit(unitType)
	if not unit then
		return
	end
	spell = ResolveSecret(spell, nil)
	unit.casting = true
	if spell then
		local now = GetTime()
		unit.preventSwingReset = unit.auraPreventSwingReset or noreset_swing_spells[spell]
		if pause_swing_spells[spell] then
			unit.pauseSwingTime = now
			if unit.mainSpeed > 0 and unit.mainExpirationTime > now then
				self.callbacks:Fire("UNIT_SWING_TIMER_PAUSED", unit.id, "mainhand")
				if unit.mainTimer then
					unit.mainTimer:Cancel()
				end
			end
			if unit.offSpeed > 0 and unit.offExpirationTime > now then
				self.callbacks:Fire("UNIT_SWING_TIMER_PAUSED", unit.id, "offhand")
				if unit.offTimer then
					unit.offTimer:Cancel()
				end
			end
		end
	end
end

function lib:UNIT_SPELLCAST_CHANNEL_START(_, unitType, _, spell)
	local unit = lib:getUnit(unitType)
	if not unit then
		return
	end
	spell = ResolveSecret(spell, nil)
	unit.casting = true
	unit.channeling = true
	unit.preventSwingReset = unit.auraPreventSwingReset or noreset_swing_spells[spell]
end

function lib:UNIT_SPELLCAST_CHANNEL_STOP(_, unitType, _, spell)
	local unit = lib:getUnit(unitType)
	if not unit then
		return
	end
	spell = ResolveSecret(spell, nil)
	local now = GetTime()
	unit.channeling = false
	unit.preventSwingReset = unit.auraPreventSwingReset or false
	if (spell and reset_swing_on_channel_stop_spells[spell]) then
		unit:SwingStart("mainhand", now, true)
		if not isRetail then
			unit:SwingStart("offhand", now, true)
			unit:SwingStart("ranged", now, true)
		end
	end
end

function lib:PLAYER_EQUIPMENT_CHANGED(_, equipmentSlot)
	if equipmentSlot == 16 or equipmentSlot == 17 or equipmentSlot == 18 then
		local now = GetTime()
		self.player:SwingStart("mainhand", now, true)
		self.player:SwingStart("offhand", now, true)
		if isClassicOrBCCOrWrathOrCata then
			self.player:SwingStart("ranged", now, true)
		end
		if isClassicOrBCCOrWrathOrCata and equipmentSlot == 18 then
			self.player.rangedBaseSpeed = self.player:GetRangedBaseSpeed()
		end
	end
end

function lib:PLAYER_ENTER_COMBAT()
	local now = GetTime()
	self.player.isAttacking = true
	self.player.channeling = false -- hardening: channels may end silently on 12.x clients
	if now > (self.player.offExpirationTime - (self.player.offSpeed / 2)) then
		if self.player.offTimer then
			self.player.offTimer:Cancel()
		end
		self.player:SwingStart("offhand", now, true)
	end
end

function lib:PLAYER_LEAVE_COMBAT()
	self.player.isAttacking = false
	self.player.firstMainSwing = false
	self.player.firstOffSwing = false
end

-- An in-place resurrection does not fire PLAYER_ENTERING_WORLD, so without
-- this the timers would sit stale until the next swing.
function lib:PLAYER_DEAD()
	local unit = self.player
	if not unit then
		return
	end
	if unit.mainTimer and not unit.mainTimer:IsCancelled() then
		unit.mainTimer:Cancel()
		self.callbacks:Fire("UNIT_SWING_TIMER_STOP", unit.id, "mainhand")
	end
	if unit.offTimer and not unit.offTimer:IsCancelled() then
		unit.offTimer:Cancel()
		self.callbacks:Fire("UNIT_SWING_TIMER_STOP", unit.id, "offhand")
	end
	if unit.rangedTimer and not unit.rangedTimer:IsCancelled() then
		unit.rangedTimer:Cancel()
		self.callbacks:Fire("UNIT_SWING_TIMER_STOP", unit.id, "ranged")
	end
	unit.casting = false
	unit.channeling = false
	unit.isAttacking = false
	unit.preventSwingReset = false
	unit.auraPreventSwingReset = false
	if unit.feignDeathTimer then
		unit.feignDeathTimer:Cancel()
	end
	unit.feignDeathTimer = nil
end

function lib:START_AUTOREPEAT_SPELL()
	self.player.isShooting = true
	self.player.rangedBaseSpeed = self.player:GetRangedBaseSpeed()
	self.player.autoShotCastTime = 0.52 * (self.player.rangedSpeed / self.player.rangedBaseSpeed)
end

function lib:STOP_AUTOREPEAT_SPELL()
	self.player.isShooting = false
end

function lib:UNIT_SPELLCAST_FAILED_QUIET(_, unitType, _, spell)
	local unit = lib:getUnit(unitType)
	if not unit then
		return
	end
	spell = ResolveSecret(spell, nil)
	if (isClassic or isForever) and spell and ranged_swing[spell] and unit.isShooting then
		if self.player.rangedTimer and not self.player.rangedTimer:IsCancelled() then
			self.player.rangedTimer:Cancel()
		end
		-- Recast delay after a movement cancel. Classic-era clients: 0.5s retry
		-- plus the auto shot cast time. WoW: Forever (measured on the beta): the
		-- engine retries every ~0.5s while moving and the shot lands ~0.5s after
		-- the last cancel, so the cast time is not added there.
		local recastDelay = 0.5
		if not isForever then
			recastDelay = recastDelay + self.player.autoShotCastTime
		end
		self.player.rangedExpirationTime = GetTime() + recastDelay
		self.player.callbacks:Fire("UNIT_SWING_TIMER_UPDATE", self.player.id, self.player.rangedSpeed, self.player.rangedExpirationTime, "ranged")
		if self.player.rangedExpirationTime - GetTime() > 0 then
			self.player.rangedTimer = C_Timer.NewTimer(self.player.rangedExpirationTime - GetTime(), function()
				self.player:SwingEnd("ranged")
			end)
		end
	end
end

-- WoW: Forever refuses CLEU registration silently and only exposes swings through
-- its native event; it is unknown whether PLAYER_SWING exists on retail 12.x.
if isForever then
	frame:RegisterEvent("PLAYER_SWING")
	frame:RegisterEvent("UNIT_COMBAT")
else
	frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("PLAYER_ENTER_COMBAT")
frame:RegisterEvent("PLAYER_LEAVE_COMBAT")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("START_AUTOREPEAT_SPELL")
frame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
frame:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player", "target")
frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player", "target")
frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "target")
frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player", "target")
frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "target")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "target")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", "target")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		lib[event](lib, event, CombatLogGetCurrentEventInfo())
	else
		lib[event](lib, event, ...)
	end
end)

tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

--[[
	Specific event handling
]]--
local EventHandler = function(event, ...)
	-- Backward compatibility continue to fire EVENTS with SWING_TIMER_ format for player unit.
	local unitId = ...
	if unitId == "player" then
		lib.callbacks:Fire(string.gsub(event,"UNIT_",""), select(2,...))
	end
	-- Fire EVENTS in Weakauras if the addon is loaded
	if WeakAuras ~= nil then
		WeakAuras.ScanEvents(event, ...)
	end
end

lib.RegisterCallback(lib, "UNIT_SWING_TIMER_INFO_INITIALIZED", EventHandler)
lib.RegisterCallback(lib, "UNIT_SWING_TIMER_START", EventHandler)
lib.RegisterCallback(lib, "UNIT_SWING_TIMER_UPDATE", EventHandler)
lib.RegisterCallback(lib, "UNIT_SWING_TIMER_CLIPPED", EventHandler)
lib.RegisterCallback(lib, "UNIT_SWING_TIMER_PAUSED", EventHandler)
lib.RegisterCallback(lib, "UNIT_SWING_TIMER_STOP", EventHandler)
lib.RegisterCallback(lib, "UNIT_SWING_TIMER_DELTA", EventHandler)
lib.RegisterCallback(lib, "SWING_TIMER_INFO_INITIALIZED", EventHandler)
lib.RegisterCallback(lib, "SWING_TIMER_START", EventHandler)
lib.RegisterCallback(lib, "SWING_TIMER_STOP", EventHandler)
lib.RegisterCallback(lib, "SWING_TIMER_UPDATE", EventHandler)
lib.RegisterCallback(lib, "SWING_TIMER_CLIPPED", EventHandler)
lib.RegisterCallback(lib, "SWING_TIMER_DELTA", EventHandler)
lib.RegisterCallback(lib, "SWING_TIMER_PAUSED", EventHandler)

--[[
	Set table data based on current game version
]]--
if isClassic or isForever then
	reset_swing_spells = {
		[16589] = true, -- Noggenfogger Elixir
		[2645] = true, -- Ghost Wolf
		[5384] = true, -- Feign Death
		[20066] = true, -- Repentance
		[2893] = true, -- Abolish Poison
		[8946] = true, -- Cure Poison
		[339] = true, [1062] = true, [5195] = true, [5196] = true, [9852] = true, [9853] = true, -- Entangling Roots
		[770] = true, -- Faerie Fire
		[21849] = true,	[21850] = true, -- Gift of the Wild
		[5185] = true, [5186] = true, [5187] = true, [5188] = true, [5189] = true, [6778] = true, [8903] = true, [9758] = true, 
			[9888] = true, [9889] = true, [25297] = true, -- Healing Touch
		[2637] = true, [18657] = true, [18658] = true, -- Hibernate
		[1126] = true, [5232] = true, [6756] = true, [5234] = true, [8907] = true, [9884] = true, [9885] = true,  -- Mark of the Wild
		[8921] = true, [8924] = true, [8925] = true, [8926] = true, [8927] = true, [8928] = true, [8929] = true, [9833] = true, [9834] = true, [9835] = true, -- Moonfire
		[20484] = true, [20739] = true, [20742] = true, [20747] = true, [20748] = true, -- Rebirth
		[8936] = true, [8938] = true, [8939] = true, [8940] = true, [8941] = true, [9750] = true, [9856] = true, [9857] = true, [9858] = true, -- Regrowth
		[774] = true, [1058] = true, [1430] = true, [2090] = true, [2091] = true, [3627] = true, [8910] = true, [9839] = true, [9840] = true,
			[9841] = true, [25299] = true, -- Rejuvenation
		[2782] = true, -- remove-curse
		[2908] = true, [8955] = true, [9901] = true, -- Soothe Animal
		[467] = true, [782] = true, [1075] = true, [8914] = true, [9756] = true, [9910] = true, -- Thorns
		[5176] = true, [5177] = true, [5178] = true, [5179] = true, [5180] = true, [6780] = true, [8905] = true, [9912] = true, -- Wrath
	}

	reset_swing_on_channel_stop_spells = {}

	-- WoW: Forever dynamic-haste family (capture-verified 2026-09-30,
	-- docs/HASTE_APPLICATION_FINDINGS.md): applying one of these auras
	-- rescales the in-flight swing proportionally, both hands. Value = the
	-- attack speed multiplier's denominator (newSpeed = speed / factor).
	-- Only capture-verified spells belong here; unknown haste spells keep
	-- the next-swing re-anchoring. The snapshot family (SotC and the druid
	-- forms in prevent_swing_speed_update below) must never be listed: the
	-- engine applies those from the next swing only.
	if isForever then
		dynamic_haste_spells[5171] = 1.2 -- Slice and Dice (rank 1, +20%)
	end

	prevent_swing_speed_update = {
		[768] = true, -- Cat Form
		[5487] = true, -- Bear Form
		[9634] = true, -- Dire Bear Form
		[21082] = true, -- Seal of the Crusader (Rank 1)
		[20162] = true, -- Seal of the Crusader (Rank 2)
		[20305] = true, -- Seal of the Crusader (Rank 3)
		[20306] = true, -- Seal of the Crusader (Rank 4)
		[20307] = true, -- Seal of the Crusader (Rank 5)
		[20308] = true, -- Seal of the Crusader (Rank 6)
	}

	next_melee_spells = {
		[25286] = true, -- Heroic Strike (rank 9)
		[11567] = true, -- Heroic Strike (rank 18)
		[11566] = true, -- Heroic Strike (rank 7)
		[11565] = true, -- Heroic Strike (rank 6)
		[11564] = true, -- Heroic Strike (rank 5)
		[1608] = true, -- Heroic Strike (rank 4)
		[285] = true, -- Heroic Strike (rank 3)
		[284] = true, -- Heroic Strike (rank 2)
		[78] = true, -- Heroic Strike (rank 1)
		[20569] = true, -- Cleave (rank 5)
		[11609] = true, -- Cleave (rank 4)
		[11608] = true, -- Cleave (rank 3)
		[7369] = true, -- Cleave (rank 2)
		[845] = true, -- Cleave (rank 1)
		[14266] = true, -- Raptor Strike (rank 8)
		[14265] = true, -- Raptor Strike (rank 7)
		[14264] = true, -- Raptor Strike (rank 6)
		[14263] = true, -- Raptor Strike (rank 5)
		[14262] = true, -- Raptor Strike (rank 4)
		[14261] = true, -- Raptor Strike (rank 3)
		[14260] = true, -- Raptor Strike (rank 2)
		[2973] = true, -- Raptor Strike (rank 1)
		[6807] = true, -- Maul (rank 1)
		[6808] = true, -- Maul (rank 2)
		[6809] = true, -- Maul (rank 3)
		[8972] = true, -- Maul (rank 4)
		[9745] = true, -- Maul (rank 5)
		[9880] = true, -- Maul (rank 6)
		[9881] = true, -- Maul (rank 7)
	}

	noreset_swing_spells = {
		[23063] = true, -- Dense Dynamite
		[4054] = true, -- Rough Dynamite
		[4064] = true, -- Rough Copper Bomb
		[4061] = true, -- Coarse Dynamite
		[8331] = true, -- Ez-Thro Dynamite
		[4065] = true, -- Large Copper Bomb
		[4066] = true, -- Small Bronze Bomb
		[4062] = true, -- Heavy Dynamite
		[4067] = true, -- Big Bronze Bomb
		[4068] = true, -- Iron Grenade
		[23000] = true, -- Ez-Thro Dynamite II
		[12421] = true, -- Mithril Frag Bomb
		[4069] = true, -- Big Iron Bomb
		[12562] = true, -- The Big One
		[12543] = true, -- Hi-Explosive Bomb
		[19769] = true, -- Thorium Grenade
		[19784] = true, -- Dark Iron Bomb
		[30216] = true, -- Fel Iron Bomb
		[19821] = true, -- Arcane Bomb
		[17402] = true, -- Hurricane (rank 3)
		[17401] = true, -- Hurricane (rank 2)
		[16914] = true, -- Hurricane (rank 1)
		[12051] = true, -- Evocation
		[14295] = true, -- Volley (rank 3)
		[14294] = true, -- Volley (rank 2)
		[1510] = true, -- Volley (rank 1)	
	}

	prevent_reset_swing_auras = {}

	pause_swing_spells = {}

	ranged_swing = {
		[75] = true, -- Auto Shot
		[3018] = true, -- Shoot
		[2764] = true, -- Throw
		[5019] = true, -- Shoot Wand
	}

	reset_ranged_swing = {
		[42245] = true, -- Volley (rank 3)
		[42244] = true, -- Volley (rank 2)
		[42243] = true,  -- Volley (rank 1)
	}
elseif isBCC then
	reset_swing_spells = {
		[16589] = true, -- Noggenfogger Elixir
		[2645] = true, -- Ghost Wolf
		[5384] = true, -- Feign Death
		[20066] = true, -- Repentance
	}

	reset_swing_on_channel_stop_spells = {}

	prevent_swing_speed_update = {
		[768] = true, -- Cat Form
		[5487] = true, -- Bear Form
		[9634] = true, -- Dire Bear Form
	}

	next_melee_spells = {
		[30324] = true, -- Heroic Strike (rank 11)
		[29707] = true, -- Heroic Strike (rank 10)
		[25286] = true, -- Heroic Strike (rank 9)
		[11567] = true, -- Heroic Strike (rank 18)
		[11566] = true, -- Heroic Strike (rank 7)
		[11565] = true, -- Heroic Strike (rank 6)
		[11564] = true, -- Heroic Strike (rank 5)
		[1608] = true, -- Heroic Strike (rank 4)
		[285] = true, -- Heroic Strike (rank 3)
		[284] = true, -- Heroic Strike (rank 2)
		[78] = true, -- Heroic Strike (rank 1)
		[25231] = true, -- Cleave (rank 6)
		[20569] = true, -- Cleave (rank 5)
		[11609] = true, -- Cleave (rank 4)
		[11608] = true, -- Cleave (rank 3)
		[7369] = true, -- Cleave (rank 2)
		[845] = true, -- Cleave (rank 1)
		[27014] = true, -- Raptor Strike (rank 9)
		[14266] = true, -- Raptor Strike (rank 8)
		[14265] = true, -- Raptor Strike (rank 7)
		[14264] = true, -- Raptor Strike (rank 6)
		[14263] = true, -- Raptor Strike (rank 5)
		[14262] = true, -- Raptor Strike (rank 4)
		[14261] = true, -- Raptor Strike (rank 3)
		[14260] = true, -- Raptor Strike (rank 2)
		[2973] = true, -- Raptor Strike (rank 1)
		[6807] = true, -- Maul (rank 1)
		[6808] = true, -- Maul (rank 2)
		[6809] = true, -- Maul (rank 3)
		[8972] = true, -- Maul (rank 4)
		[9745] = true, -- Maul (rank 5)
		[9880] = true, -- Maul (rank 6)
		[9881] = true, -- Maul (rank 7)
		[26996] = true, -- Maul (rank 8)
	}

	noreset_swing_spells = {
		[23063] = true, -- Dense Dynamite
		[4054] = true, -- Rough Dynamite
		[4064] = true, -- Rough Copper Bomb
		[4061] = true, -- Coarse Dynamite
		[8331] = true, -- Ez-Thro Dynamite
		[4065] = true, -- Large Copper Bomb
		[4066] = true, -- Small Bronze Bomb
		[4062] = true, -- Heavy Dynamite
		[4067] = true, -- Big Bronze Bomb
		[4068] = true, -- Iron Grenade
		[23000] = true, -- Ez-Thro Dynamite II
		[12421] = true, -- Mithril Frag Bomb
		[4069] = true, -- Big Iron Bomb
		[12562] = true, -- The Big One
		[12543] = true, -- Hi-Explosive Bomb
		[19769] = true, -- Thorium Grenade
		[19784] = true, -- Dark Iron Bomb
		[30216] = true, -- Fel Iron Bomb
		[19821] = true, -- Arcane Bomb
		[39965] = true, -- Frost Grenade
		[30461] = true, -- The Bigger One
		[30217] = true, -- Adamantite Grenade
		[35476] = true, -- Drums of Battle
		[35475] = true, -- Drums of War
		[35477] = true, -- Drums of Speed
		[35478] = true, -- Drums of Restoration
		[34120] = true, -- Steady Shot
		[27012] = true, -- Hurricane (rank 4)
		[17402] = true, -- Hurricane (rank 3)
		[17401] = true, -- Hurricane (rank 2)
		[16914] = true, -- Hurricane (rank 1)
		[12051] = true, -- Evocation
		[27022] = true, -- Volley (rank 4)
		[14295] = true, -- Volley (rank 3)
		[14294] = true, -- Volley (rank 2)
		[1510] = true, -- Volley (rank 1)
		--35474 Drums of Panic DO reset the swing timer, do not add
	}

	prevent_reset_swing_auras = {
		[408505] = true, -- Maelstrom Weapon
	}

	pause_swing_spells = {}

	ranged_swing = {
		[75] = true, -- Auto Shot
		[3018] = true, -- Shoot
		[2764] = true, -- Throw
		[5019] = true, -- Shoot Wand
	}

	reset_ranged_swing = {
		[42234] = true, -- Volley (rank 4)
		[42245] = true, -- Volley (rank 3)
		[42244] = true, -- Volley (rank 2)
		[42243] = true,  -- Volley (rank 1)
	}
elseif isWrath then
	reset_swing_spells = {
		[16589] = true, -- Noggenfogger Elixir
		[2645] = true, -- Ghost Wolf
		[2764] = true, -- Throw
		[3018] = true, -- Shoots,
		[5019] = true, -- Shoot Wand
		[5384] = true, -- Feign Death
		[75] = true, -- Auto Shot
		[2893] = true, -- Abolish Poison
		[8946] = true, -- Cure Poison
		[339] = true, [1062] = true, [5195] = true, [5196] = true, [9852] = true, [9853] = true, [26989] = true, [53308] = true, -- Entangling Roots
		[770] = true, -- Faerie Fire
		[21849] = true,	[21850] = true,	[26991] = true,	[48470] = true, -- Gift of the Wild
		[5185] = true, [5186] = true, [5187] = true, [5188] = true, [5189] = true, [6778] = true, [8903] = true, [9758] = true, 
			[9888] = true, [9889] = true, [25297] = true, [26978] = true, [26979] = true, [58399] = true, [58378] = true, -- Healing Touch
		[2637] = true, [18657] = true, [18658] = true, -- Hibernate
		[33763] = true, [48450] = true, [48451] = true, -- Lifebloom
		[1126] = true, [5232] = true, [6756] = true, [5234] = true, [8907] = true, [9884] = true, [9885] = true, [26990] = true, [48469] = true, -- Mark of the Wild
		[8921] = true, [8924] = true, [8925] = true, [8926] = true, [8927] = true, [8928] = true, [8929] = true, [9833] = true, [9834] = true, 
			[9835] = true, [26987] = true, [26988] = true, -- Moonfire
		[50464] = true, -- Nourish
		[20484] = true, [20739] = true, [20742] = true, [20747] = true, [20748] = true, [26994] = true, [48477] = true, -- Rebirth
		[8936] = true, [8938] = true, [8939] = true, [8940] = true, [8941] = true, [9750] = true, [9856] = true, [9857] = true, [9858] = true,
			[26980] = true, [48442] = true, [48443] = true, -- Regrowth
		[774] = true, [1058] = true, [1430] = true, [2090] = true, [2091] = true, [3627] = true, [8910] = true, [9839] = true, [9840] = true,
			[9841] = true, [25299] = true, [26981] = true, [26982] = true, [48440] = true, [48441] = true, -- Rejuvenation
		[2782] = true, -- remove-curse
		[50769] = true, [50768] = true, [50767] = true, [50766] = true, [50765] = true, [50764] = true, [50763] = true, -- Revive
		[2908] = true, [8955] = true, [9901] = true, [26995] = true, -- Soothe Animal
		[467] = true, [782] = true, [1075] = true, [8914] = true, [9756] = true, [9910] = true, [26992] = true, [53307] = true, -- Thorns
		[5176] = true, [5177] = true, [5178] = true, [5179] = true, [5180] = true, [6780] = true, [8905] = true, [9912] = true, [26984] = true,
			[26985] = true, [48459] = true, [48461] = true, -- Wrath
		[53563] = true, -- Beacon of Light
		[64382] = true, -- Shattering Throw
		[57755] = true, -- Heroic Throw
	}

	reset_swing_on_channel_stop_spells = {}

	prevent_swing_speed_update = {
		[768] = true, -- Cat Form
		[5487] = true, -- Bear Form
		[9634] = true, -- Dire Bear Form
	}

	next_melee_spells = {
		[47450] = true, -- Heroic Strike (rank 13)
		[47449] = true, -- Heroic Strike (rank 12)
		[30324] = true, -- Heroic Strike (rank 11)
		[29707] = true, -- Heroic Strike (rank 10)
		[25286] = true, -- Heroic Strike (rank 9)
		[11567] = true, -- Heroic Strike (rank 18)
		[11566] = true, -- Heroic Strike (rank 7)
		[11565] = true, -- Heroic Strike (rank 6)
		[11564] = true, -- Heroic Strike (rank 5)
		[1608] = true, -- Heroic Strike (rank 4)
		[285] = true, -- Heroic Strike (rank 3)
		[284] = true, -- Heroic Strike (rank 2)
		[78] = true, -- Heroic Strike (rank 1)
		[47520] = true, -- Cleave (rank 8)
		[47519] = true, -- Cleave (rank 7)
		[25231] = true, -- Cleave (rank 6)
		[20569] = true, -- Cleave (rank 5)
		[11609] = true, -- Cleave (rank 4)
		[11608] = true, -- Cleave (rank 3)
		[7369] = true, -- Cleave (rank 2)
		[845] = true, -- Cleave (rank 1)
		[48996] = true, -- Raptor Strike (rank 11)
		[48995] = true, -- Raptor Strike (rank 10)
		[27014] = true, -- Raptor Strike (rank 9)
		[14266] = true, -- Raptor Strike (rank 8)
		[14265] = true, -- Raptor Strike (rank 7)
		[14264] = true, -- Raptor Strike (rank 6)
		[14263] = true, -- Raptor Strike (rank 5)
		[14262] = true, -- Raptor Strike (rank 4)
		[14261] = true, -- Raptor Strike (rank 3)
		[14260] = true, -- Raptor Strike (rank 2)
		[2973] = true, -- Raptor Strike (rank 1)
		[6807] = true, -- Maul (rank 1)
		[6808] = true, -- Maul (rank 2)
		[6809] = true, -- Maul (rank 3)
		[8972] = true, -- Maul (rank 4)
		[9745] = true, -- Maul (rank 5)
		[9880] = true, -- Maul (rank 6)
		[9881] = true, -- Maul (rank 7)
		[26996] = true, -- Maul (rank 8)
		[48479] = true, -- Maul (rank 9)
		[48480] = true, -- Maul (rank 10)
		[56815] = true, -- Rune Strike
	}

	noreset_swing_spells = {
		[23063] = true, -- Dense Dynamite
		[4054] = true, -- Rough Dynamite
		[4064] = true, -- Rough Copper Bomb
		[4061] = true, -- Coarse Dynamite
		[8331] = true, -- Ez-Thro Dynamite
		[4065] = true, -- Large Copper Bomb
		[4066] = true, -- Small Bronze Bomb
		[4062] = true, -- Heavy Dynamite
		[4067] = true, -- Big Bronze Bomb
		[4068] = true, -- Iron Grenade
		[23000] = true, -- Ez-Thro Dynamite II
		[12421] = true, -- Mithril Frag Bomb
		[4069] = true, -- Big Iron Bomb
		[12562] = true, -- The Big One
		[12543] = true, -- Hi-Explosive Bomb
		[19769] = true, -- Thorium Grenade
		[19784] = true, -- Dark Iron Bomb
		[30216] = true, -- Fel Iron Bomb
		[19821] = true, -- Arcane Bomb
		[39965] = true, -- Frost Grenade
		[30461] = true, -- The Bigger One
		[30217] = true, -- Adamantite Grenade
		[35476] = true, -- Drums of Battle
		[35475] = true, -- Drums of War
		[35477] = true, -- Drums of Speed
		[35478] = true, -- Drums of Restoration
		[56641] = true, -- Steady Shot (rank 1)
		[34120] = true, -- Steady Shot (rank 2)
		[49051] = true, -- Steady Shot (rank 3)
		[49052] = true, -- Steady Shot (rank 4)
		[19434] = true, -- Aimed Shot (rank 1)
		[1464] = true, -- Slam (rank 1)
		[8820] = true, -- Slam (rank 2)
		[11604] = true, -- Slam (rank 3)
		[11605] = true, -- Slam (rank 4)
		[25241] = true, -- Slam (rank 5)
		[25242] = true, -- Slam (rank 6)
		[47474] = true, -- Slam (rank 7)
		[47475] = true, -- Slam (rank 8)
		[48467] = true, -- Hurricane (rank 5)
		[27012] = true, -- Hurricane (rank 4)
		[17402] = true, -- Hurricane (rank 3)
		[17401] = true, -- Hurricane (rank 2)
		[16914] = true, -- Hurricane (rank 1)
		[12051] = true, -- Evocation
		[58434] = true, -- Volley (rank 6)
		[58431] = true, -- Volley (rank 5)
		[27022] = true, -- Volley (rank 4)
		[14295] = true, -- Volley (rank 3)
		[14294] = true, -- Volley (rank 2)
		[1510] = true, -- Volley (rank 1)
		--35474 Drums of Panic DO reset the swing timer, do not add

	}

	prevent_reset_swing_auras = {
		[53817] = true, -- Maelstrom Weapon
	}

	pause_swing_spells = {
		[1464] = true, -- Slam (rank 1)
		[8820] = true, -- Slam (rank 2)
		[11604] = true, -- Slam (rank 3)
		[11605] = true, -- Slam (rank 4)
		[25241] = true, -- Slam (rank 5)
		[25242] = true, -- Slam (rank 6)
		[47474] = true, -- Slam (rank 7)
		[47475] = true, -- Slam (rank 8)
	}

	ranged_swing = {
		[75] = true, -- Auto Shot
		[3018] = true, -- Shoot
		[2764] = true, -- Throw
		[5019] = true, -- Shoot Wand
	}

	reset_ranged_swing = {
		[58433] = true, -- Volley (rank 6)
		[58432] = true, -- Volley (rank 5)
		[42234] = true, -- Volley (rank 4)
		[42245] = true, -- Volley (rank 3)
		[42244] = true, -- Volley (rank 2)
		[42243] = true,  -- Volley (rank 1)
	}
elseif isCata then
	reset_swing_spells = {
		-- need to verify following for Cataclysm
		[16589] = true, -- Noggenfogger Elixir
		[2645] = true, -- Ghost Wolf
		[2764] = true, -- Throw
		[3018] = true, -- Shoots,
		[5019] = true, -- Shoot Wand
		[75] = true, -- Auto Shot
		[5185] = true, -- Hibernate
		[2782] = true, -- Remove Corruption
		[450759] = true, -- Revitalize
		[50769] = true, -- Revive
		[2908] = true, -- Soothe
		[53563] = true, -- Beacon of Light
		[64382] = true, -- Shattering Throw
		[57755] = true, -- Heroic Throw

		-- cata verified abilities below
		[5384] = true, -- Feign Death
		[339] = true, -- Entangling Roots
		[770] = true, -- Faerie Fire
		[33763] = true, -- Lifebloom
		[1126] = true, -- Mark of the Wild
		[8921] = true, -- Moonfire
		[50464] = true, -- Nourish
		[20484] = true, -- Regrowth
		[774] = true, -- Rejuvenation
		[467] = true, -- Thorns
		[5176] = true, -- Wrath
		[51505] = true, -- Lava Burst
		[51533] = true, -- Feral Spirit
	}

	reset_swing_on_channel_stop_spells = {}

	prevent_swing_speed_update = {
		[768] = true, -- Cat Form
		[5487] = true, -- Bear Form
	}

	-- all next melee spells have been converted to instants in Cataclysm
	next_melee_spells = {}

	-- need to verify these for Cataclysm
	noreset_swing_spells = {
		[23063] = true, -- Dense Dynamite
		[4054] = true, -- Rough Dynamite
		[4064] = true, -- Rough Copper Bomb
		[4061] = true, -- Coarse Dynamite
		[8331] = true, -- Ez-Thro Dynamite
		[4065] = true, -- Large Copper Bomb
		[4066] = true, -- Small Bronze Bomb
		[4062] = true, -- Heavy Dynamite
		[4067] = true, -- Big Bronze Bomb
		[4068] = true, -- Iron Grenade
		[23000] = true, -- Ez-Thro Dynamite II
		[12421] = true, -- Mithril Frag Bomb
		[4069] = true, -- Big Iron Bomb
		[12562] = true, -- The Big One
		[12543] = true, -- Hi-Explosive Bomb
		[19769] = true, -- Thorium Grenade
		[19784] = true, -- Dark Iron Bomb
		[30216] = true, -- Fel Iron Bomb
		[19821] = true, -- Arcane Bomb
		[39965] = true, -- Frost Grenade
		[30461] = true, -- The Bigger One
		[30217] = true, -- Adamantite Grenade
		[35476] = true, -- Drums of Battle
		[35475] = true, -- Drums of War
		[35477] = true, -- Drums of Speed
		[35478] = true, -- Drums of Restoration
		[19434] = true, -- Aimed Shot (rank 1)
		[12051] = true, -- Evocation
		--35474 Drums of Panic DO reset the swing timer, do not add

		-- Below have been verified in Cataclysm
		[56641] = true, -- Steady Shot
		[1464] = true, -- Slam
		[16914] = true, -- Hurricane
	}

	-- need to verify for cataclysm
	prevent_reset_swing_auras = {
		[53817] = true, -- Maelstrom Weapon
	}

	pause_swing_spells = {
		[1464] = true, -- Slam
	}

	ranged_swing = {
		[75] = true, -- Auto Shot
		[3018] = true, -- Shoot
		[2764] = true, -- Throw
		[5019] = true, -- Shoot Wand
	}

	reset_ranged_swing = {
	}
elseif isMists then
	reset_swing_spells = {
		-- need to verify following
		[16589] = true, -- Noggenfogger Elixir
		[2645] = true, -- Ghost Wolf
		[2764] = true, -- Throw
		[3018] = true, -- Shoots,
		[5019] = true, -- Shoot Wand
		[75] = true, -- Auto Shot
		[5185] = true, -- Hibernate
		[2782] = true, -- Remove Corruption
		[450759] = true, -- Revitalize
		[50769] = true, -- Revive
		[2908] = true, -- Soothe
		[53563] = true, -- Beacon of Light
		[64382] = true, -- Shattering Throw
		[5384] = true, -- Feign Death
		[339] = true, -- Entangling Roots
		[770] = true, -- Faerie Fire
		[33763] = true, -- Lifebloom
		[1126] = true, -- Mark of the Wild
		[8921] = true, -- Moonfire
		[50464] = true, -- Nourish
		[20484] = true, -- Regrowth
		[774] = true, -- Rejuvenation
		[467] = true, -- Thorns
		[5176] = true, -- Wrath
		[51505] = true, -- Lava Burst
		[51533] = true, -- Feral Spirit
		[124682] = true, -- Enveloping Mist
		[116670] = true, -- Vivify
		[115072] = true, -- Expel Harm
		[115450] = true, -- Detox
		[115460] = true, -- Healing Sphere
		[115315] = true, -- Summon Black Ox Statue
	}

	reset_swing_on_channel_stop_spells = {}

	prevent_swing_speed_update = {
		[768] = true, -- Cat Form
		[5487] = true, -- Bear Form
	}

	-- all next melee spells have been converted to instants in Cataclysm
	next_melee_spells = {
	}

	-- need to verify
	noreset_swing_spells = {
		[23063] = true, -- Dense Dynamite
		[4054] = true, -- Rough Dynamite
		[4064] = true, -- Rough Copper Bomb
		[4061] = true, -- Coarse Dynamite
		[8331] = true, -- Ez-Thro Dynamite
		[4065] = true, -- Large Copper Bomb
		[4066] = true, -- Small Bronze Bomb
		[4062] = true, -- Heavy Dynamite
		[4067] = true, -- Big Bronze Bomb
		[4068] = true, -- Iron Grenade
		[23000] = true, -- Ez-Thro Dynamite II
		[12421] = true, -- Mithril Frag Bomb
		[4069] = true, -- Big Iron Bomb
		[12562] = true, -- The Big One
		[12543] = true, -- Hi-Explosive Bomb
		[19769] = true, -- Thorium Grenade
		[19784] = true, -- Dark Iron Bomb
		[30216] = true, -- Fel Iron Bomb
		[19821] = true, -- Arcane Bomb
		[39965] = true, -- Frost Grenade
		[30461] = true, -- The Bigger One
		[30217] = true, -- Adamantite Grenade
		[35476] = true, -- Drums of Battle
		[35475] = true, -- Drums of War
		[35477] = true, -- Drums of Speed
		[35478] = true, -- Drums of Restoration
		[19434] = true, -- Aimed Shot (rank 1)
		[12051] = true, -- Evocation
		[56641] = true, -- Steady Shot
		[1464] = true, -- Slam
		[16914] = true, -- Hurricane
		
		[120360] = true, -- Barrage
		[113656] = true, -- Fists of Fury
		[123986] = true, -- Chi Burst	
		[107270] = true, -- Spinning Crane Kick
		[119996] = true, -- Transcendence: Transfer
		[115176] = true, -- Zen Meditation
	}

	prevent_reset_swing_auras = {
		[53817] = true, -- Maelstrom Weapon
	}

	pause_swing_spells = {
		[1464] = true, -- Slam
	}

	ranged_swing = {
		[75] = true, -- Auto Shot
		[3018] = true, -- Shoot
		[2764] = true, -- Throw
		[5019] = true, -- Shoot Wand
	}

	reset_ranged_swing = {
	}
elseif isRetail then
	reset_swing_spells = {
		[124682] = true, -- Enveloping Mist
		[116670] = true, -- Vivify
	}

	reset_swing_on_channel_stop_spells = {
		[257044] = true, -- Rapide Fire
	}

	prevent_swing_speed_update = {
		[768] = true, -- Cat Form
		[5487] = true, -- Bear Form
		[9634] = true, -- Dire Bear Form
	}

	noreset_swing_spells = {
		[12051] = true, -- Evocation
		[120360] = true, -- Barrage
		[56641] = true, -- Steady Shot
		[19434] = true, -- Aimed Shot
		[113656] = true, -- Fists of Fury
		[198013] = true, -- Eye Beam
		[101546] = true, -- Spinning Crane Kick
		[322729] = true, -- Spinning Crane Kick
		[123986] = true, -- Chi Burst	
	}

	next_melee_spells = {}

	prevent_reset_swing_auras = {}

	pause_swing_spells = {}

	ranged_swing = {
		[75] = true, -- Auto Shot
	}

	reset_ranged_swing = {}
end
