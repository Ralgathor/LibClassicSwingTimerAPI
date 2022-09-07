local MAJOR, MINOR = "LibClassicSwingTimerAPI", 6
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

local frame = CreateFrame("Frame")
local C_Timer, tonumber = C_Timer, tonumber
local GetSpellInfo, GetTime, CombatLogGetCurrentEventInfo = GetSpellInfo, GetTime, CombatLogGetCurrentEventInfo
local UnitAttackSpeed, UnitAura, UnitGUID, UnitRangedDamage, GetPlayerInfoByGUID = UnitAttackSpeed, UnitAura, UnitGUID, UnitRangedDamage, GetPlayerInfoByGUID

local isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local isClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local isBCC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_BURNING_CRUSADE
local isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_WRATH_OF_THE_LICH_KING
local isClassicOrBCCOrWrath = isClassic or isBCC or isWrath

local reset_swing_spells = nil
local reset_swing_on_channel_stop_spells = nil
local prevent_swing_speed_update = nil
local next_melee_spells = nil
local noreset_swing_spells = nil
local prevent_reset_swing_auras = nil
local pause_swing_spells = nil
local ranged_swing = nil
local reset_ranged_swing = nil

lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)

function lib:Fire(event, ...)
	self.callbacks:Fire(event, ...)
end

function lib:PLAYER_ENTERING_WORLD()
	self.unitGUID = UnitGUID("player")
	self.class = select(2,GetPlayerInfoByGUID(self.unitGUID))

	local mainSpeed, offSpeed = UnitAttackSpeed("player")
	local now = GetTime()

	self.mainSpeed = mainSpeed or 3 -- some dummy non-zero value to prevent infinities
	self.offSpeed = offSpeed or 0
	self.rangedSpeed = UnitRangedDamage("player") or 0

	self.lastMainSwing = now
	self.mainExpirationTime = self.lastMainSwing + self.mainSpeed
	self.firstMainSwing = false

	self.lastOffSwing = now
	self.offExpirationTime = self.lastMainSwing + self.mainSpeed
	self.firstOffSwing = false

	self.lastRangedSwing = now
	self.rangedExpirationTime = self.lastRangedSwing + self.rangedSpeed
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
	self.skipNextAttack = nil
	self.skipNextAttackCount = 0

	self.skipNextAttackSpeedUpdate = nil
	self.skipNextAttackSpeedUpdateCount = 0
end

function lib:CalculateDelta()
	if self.offSpeed > 0 and self.mainExpirationTime ~= nil and self.offExpirationTime ~= nil then
		self:Fire("SWING_TIMER_DELTA", self.mainExpirationTime - self.offExpirationTime)
	end
end

function lib:SwingStart(hand, startTime, isReset)
	if hand == "mainhand" then
		if self.mainTimer and isReset then
			self.mainTimer:Cancel()
		end
		self.lastMainSwing = startTime
		local mainSpeed, _ = UnitAttackSpeed("player")
		self.mainSpeed = mainSpeed
		self.mainExpirationTime = self.lastMainSwing + self.mainSpeed
		self:Fire("SWING_TIMER_START", self.mainSpeed, self.mainExpirationTime, hand)
		if self.mainSpeed > 0 and self.mainExpirationTime - GetTime() > 0 then
			self.mainTimer = C_Timer.NewTimer(self.mainExpirationTime - GetTime(), function()
				self:SwingEnd("mainhand")
			end)
		end
	elseif hand == "offhand" then
		if self.offTimer and isReset then
			self.offTimer:Cancel()
		end
		self.lastOffSwing = startTime
		local _, offSpeed = UnitAttackSpeed("player")
		self.offSpeed = offSpeed or 0
		self.offExpirationTime = self.lastOffSwing + self.offSpeed
		if self.calculaDeltaTimer then
			self.calculaDeltaTimer:Cancel()
		end
		if self.offSpeed > 0 and self.firstOffSwing == false and self.isAttacking then
			self.offExpirationTime = self.lastOffSwing + (self.offSpeed / 2)
			self:CalculateDelta()
			self:Fire("SWING_TIMER_UPDATE", self.offSpeed, self.offExpirationTime, hand)
		elseif self.offSpeed > 0 then
			self:Fire("SWING_TIMER_START", self.offSpeed, self.offExpirationTime, hand)
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
		if self.rangedTimer and isReset then
			self.rangedTimer:Cancel()
		end
		self.rangedSpeed = UnitRangedDamage("player") or 0
		if self.rangedSpeed ~= nil and self.rangedSpeed > 0 then
			self.rangedSpeed = self.rangedSpeed
			self.lastRangedSwing = startTime
			self.rangedExpirationTime = self.lastRangedSwing + self.rangedSpeed
			self:Fire("SWING_TIMER_START", self.rangedSpeed, self.rangedExpirationTime, hand)
			if self.rangedExpirationTime - GetTime() > 0 then
				self.rangedTimer = C_Timer.NewTimer(self.rangedExpirationTime - GetTime(), function()
					self:SwingEnd("ranged")
				end)
			end
		end
	end
end

function lib:SwingEnd(hand)
	self:Fire("SWING_TIMER_STOP", hand)
	if (self.casting or self.channeling) and self.isAttacking and hand ~= "ranged" then
		local now = GetTime()
		if isRetail and hand == "mainhand" then		
			self:SwingStart(hand, now, true)
			self:Fire("SWING_TIMER_CLIPPED", hand)
		elseif isClassicOrBCCOrWrath then
			self:SwingStart(hand, now, true)
			self:Fire("SWING_TIMER_CLIPPED", hand)
		end
	end
end

function lib:SwingTimerInfo(hand)
	if hand == "mainhand" then
		return self.mainSpeed, self.mainExpirationTime, self.lastMainSwing
	elseif hand == "offhand" then
		return self.offSpeed, self.offExpirationTime, self.lastOffSwing
	elseif hand == "ranged" then
		return self.rangedSpeed, self.rangedExpirationTime, self.lastRangedSwing
	end
end

function lib:COMBAT_LOG_EVENT_UNFILTERED(_, ts, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, amount, overkill, _, resisted, _, _, _, _, _, isOffHand)
	local now = GetTime()
	if subEvent == "SPELL_EXTRA_ATTACKS" and sourceGUID == self.unitGUID then
		self.skipNextAttack = ts
		self.skipNextAttackCount = resisted
	elseif (subEvent == "SWING_DAMAGE" or subEvent == "SWING_MISSED") and sourceGUID == self.unitGUID then
		local isOffHand = isOffHand
		if subEvent == "SWING_MISSED" then
			isOffHand = overkill
		end
		if
			self.skipNextAttack ~= nil
			and tonumber(self.skipNextAttack)
			and (ts - self.skipNextAttack) < 0.04
			and tonumber(self.skipNextAttackCount)
			and not isOffHand
		then
			if self.skipNextAttackCount > 0 then
				self.skipNextAttackCount = self.skipNextAttackCount - 1
				return false
			end
		end
		if isOffHand then
			self.firstOffSwing = true
			self:SwingStart("offhand", now, false)
			if isWrath then
				self:SwingStart("ranged", now, true)
			end
		else
			self.firstMainSwing = true
			self:SwingStart("mainhand", now, false)
			if isWrath then
				self:SwingStart("ranged", now, true)
			end
		end
	elseif subEvent == "SWING_MISSED" and amount ~= nil and amount == "PARRY" and destGUID == self.unitGUID then
		if self.mainTimer then
			self.mainTimer:Cancel()
		end
		local swing_timer_reduced_40p = self.mainExpirationTime - (0.4 * self.mainSpeed)
		local min_swing_time = 0.2 * self.mainSpeed
		if swing_timer_reduced_40p < min_swing_time then
			self.mainExpirationTime = min_swing_time
		else
			self.mainExpirationTime = swing_timer_reduced_40p
		end
		self:Fire("SWING_TIMER_UPDATE", self.mainSpeed, self.mainExpirationTime, "mainhand")
		if self.mainSpeed > 0 and self.mainExpirationTime - GetTime() > 0 then
			self.mainTimer = C_Timer.NewTimer(self.mainExpirationTime - GetTime(), function()
				self:SwingEnd("mainhand")
			end)
		end
	elseif (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REMOVED") and sourceGUID == self.unitGUID then
		local spell = amount
		if spell and prevent_swing_speed_update[spell] then
			self.skipNextAttackSpeedUpdate = now
			self.skipNextAttackSpeedUpdateCount = 2
		end
		if spell and prevent_reset_swing_auras[spell] then
			self.auraPreventSwingReset = subEvent == "SPELL_AURA_APPLIED"
		end
	elseif (subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_MISSED") and sourceGUID == self.unitGUID then
		local spell = amount
		if reset_ranged_swing[spell] then
			if isRetail then
				self:SwingStart("mainhand", GetTime(), true)
			else
				self:SwingStart("ranged", GetTime(), true)
			end
		end
	end
end

function lib:UNIT_ATTACK_SPEED()
	if isClassic and self.class == "PALADIN" then return end -- Ignore UNIT_ATTACK_SPEED on Classic for Paladin. Seal of the Crusader snapshot. No other dynamic speed change.
	local now = GetTime()
	if
		self.skipNextAttackSpeedUpdate
		and tonumber(self.skipNextAttackSpeedUpdate)
		and (now - self.skipNextAttackSpeedUpdate) < 0.04
		and tonumber(self.skipNextAttackSpeedUpdateCount)
	then
		self.skipNextAttackSpeedUpdateCount = self.skipNextAttackSpeedUpdateCount - 1
		return
	end
	if self.mainTimer then
		self.mainTimer:Cancel()
	end
	if self.offTimer then
		self.offTimer:Cancel()
	end
	local mainSpeedNew, offSpeedNew = UnitAttackSpeed("player")
	offSpeedNew = offSpeedNew or 0
	if mainSpeedNew > 0 and self.mainSpeed > 0 and mainSpeedNew ~= self.mainSpeed then
		local multiplier = mainSpeedNew / self.mainSpeed
		local timeLeft = (self.lastMainSwing + self.mainSpeed - now) * multiplier
		self.mainSpeed = mainSpeedNew
		self.mainExpirationTime = now + timeLeft
		self:Fire("SWING_TIMER_UPDATE", self.mainSpeed, self.mainExpirationTime, "mainhand")
		if self.mainSpeed > 0 and self.mainExpirationTime - GetTime() > 0 then
			self.mainTimer = C_Timer.NewTimer(self.mainExpirationTime - GetTime(), function()
				self:SwingEnd("mainhand")
			end)
		end
	end
	if offSpeedNew > 0 and self.offSpeed > 0 and offSpeedNew ~= self.offSpeed then
		local multiplier = offSpeedNew / self.offSpeed
		local timeLeft = (self.lastOffSwing + self.offSpeed - now) * multiplier
		self.offSpeed = offSpeedNew
		self.offExpirationTime = now + timeLeft
		if self.calculaDeltaTimer ~= nil then
			self.calculaDeltaTimer:Cancel()
		end
		self:Fire("SWING_TIMER_UPDATE", self.offSpeed, self.offExpirationTime, "offhand")
		if self.offSpeed > 0 and self.offExpirationTime - GetTime() > 0 then
			self.offTimer = C_Timer.NewTimer(self.offExpirationTime - GetTime(), function()
				self:SwingEnd("offhand")
			end)
		end
	end
end

function lib:UNIT_SPELLCAST_INTERRUPTED_OR_FAILED(_, _, _, spell)
	self.casting = false
	if spell and pause_swing_spells[spell] and self.pauseSwingTime then
		self.pauseSwingTime = nil
		if self.mainSpeed > 0 then
			if self.mainExpirationTime < GetTime() and self.isAttacking then
				self.mainExpirationTime = self.mainExpirationTime + self.mainSpeed
			end
			self:Fire("SWING_TIMER_UPDATE", self.mainSpeed, self.mainExpirationTime, "mainhand")
			self.mainTimer = C_Timer.NewTimer(self.mainExpirationTime - GetTime(), function()
				self:SwingEnd("mainhand")
			end)
		end
		if self.offSpeed > 0 then
			if self.offExpirationTime < GetTime() and self.isAttacking then
				self.offExpirationTime = self.offExpirationTime + self.offSpeed
			end
			self:Fire("SWING_TIMER_UPDATE", self.offSpeed, self.offExpirationTime, "offhand")
			self.offTimer = C_Timer.NewTimer(self.offExpirationTime - GetTime(), function()
				self:SwingEnd("offhand")
			end)
		end
	end
end
function lib:UNIT_SPELLCAST_INTERRUPTED(...)
	self:UNIT_SPELLCAST_INTERRUPTED_OR_FAILED(...)
end
function lib:UNIT_SPELLCAST_FAILED(...)
	self:UNIT_SPELLCAST_INTERRUPTED_OR_FAILED(...)
end

function lib:UNIT_SPELLCAST_SUCCEEDED(_, _, _, spell)
	local now = GetTime()
	if spell ~= nil and next_melee_spells[spell] then
		self:SwingStart("mainhand", now, false)
		if isWrath then
			self:SwingStart("ranged", now, true)
		end
	end
	if (spell and reset_swing_spells[spell]) or (self.casting and not self.preventSwingReset) then
		if isRetail then		
			self:SwingStart("mainhand", now, true)
		else
			self:SwingStart("mainhand", now, true)
			self:SwingStart("offhand", now, true)
		end
	end
	if spell and ranged_swing[spell] then
		if isRetail then		
			self:SwingStart("mainhand", now, false)
		else
			self:SwingStart("ranged", now, false)
		end
	end
	if spell and pause_swing_spells[spell] and self.pauseSwingTime then
		local offset = now - self.pauseSwingTime
		self.pauseSwingTime = nil
		if self.mainSpeed > 0 then
			self.mainExpirationTime = self.mainExpirationTime + offset
			self:Fire("SWING_TIMER_UPDATE", self.mainSpeed, self.mainExpirationTime, "mainhand")
			self.mainTimer = C_Timer.NewTimer(self.mainExpirationTime - now, function()
				self:SwingEnd("mainhand")
			end)
		end
		if self.offSpeed > 0 then
			self.offExpirationTime = self.offExpirationTime + offset
			self:Fire("SWING_TIMER_UPDATE", self.offSpeed, self.offExpirationTime, "offhand")
			self.offTimer = C_Timer.NewTimer(self.offExpirationTime - now, function()
				self:SwingEnd("offhand")
			end)
		end
	end
	self.preventSwingReset = self.auraPreventSwingReset or false
	if self.casting and spell ~= 6603 then -- 6603=Auto Attack prevent set casting flag to false when auto attack is toggle on
		self.casting = false
	end
	if spell == 5384 then -- 5384=Feign Death
		self.feignDeathTimer = C_Timer.NewTicker(0.1, function() -- Start watching FD CD
			local start, _, enabled = GetSpellCooldown(spell)
			if enabled == 1 then -- Reset ranged swing when FD CD start
				self:SwingStart("mainhand", start, true)
				self:SwingStart("offhand", start, true)
				if isClassicOrBCCOrWrath then
					self:SwingStart("ranged", start, true)
				end
				if self.feignDeathTimer then
					self.feignDeathTimer:Cancel()
				end
			end
		end)
	end
end

function lib:UNIT_SPELLCAST_START(_, unit, _, spell)
	if spell then
		local now = GetTime()
		local name, rank, icon, castTime, minRange, maxRange, spellId = GetSpellInfo(spell)
		self.casting = true
		self.preventSwingReset = self.auraPreventSwingReset or noreset_swing_spells[spell]
		if spell and pause_swing_spells[spell] then
			self.pauseSwingTime = now
			if self.mainSpeed > 0 then
				self:Fire("SWING_TIMER_PAUSED", "mainhand")
				if self.mainTimer then
					self.mainTimer:Cancel()
				end
			end
			if self.offSpeed > 0 then
				self:Fire("SWING_TIMER_PAUSED", "offhand")
				if self.offTimer then
					self.offTimer:Cancel()
				end
			end
		end
	end
end

function lib:UNIT_SPELLCAST_CHANNEL_START(_, _, _, spell)
	self.casting = true
	self.channeling = true
	self.preventSwingReset = self.auraPreventSwingReset or noreset_swing_spells[spell]
end

function lib:UNIT_SPELLCAST_CHANNEL_STOP(_, _, _, spell)
	local now = GetTime()
	self.channeling = false
	self.preventSwingReset = self.auraPreventSwingReset or false
	if (spell and reset_swing_on_channel_stop_spells[spell]) then
		if isRetail then		
			self:SwingStart("mainhand", now, true)
		else
			self:SwingStart("mainhand", now, true)
			self:SwingStart("offhand", now, true)
			self:SwingStart("ranged", now, true)
		end
	end
end

function lib:PLAYER_EQUIPMENT_CHANGED(_, equipmentSlot)
	if equipmentSlot == 16 or equipmentSlot == 17 or equipmentSlot == 18 then
		local now = GetTime()
		self:SwingStart("mainhand", now, true)
		self:SwingStart("offhand", now, true)
		if isClassicOrBCCOrWrath then
			self:SwingStart("ranged", now, true)
		end
	end
end

function lib:PLAYER_ENTER_COMBAT()
	local now = GetTime()
	self.isAttacking = true
	if now > (self.offExpirationTime - (self.offSpeed / 2)) then
		if self.offTimer then
			self.offTimer:Cancel()
		end
		self:SwingStart("offhand", now, true)
	end
end

function lib:PLAYER_LEAVE_COMBAT()
	self.isAttacking = false
	self.firstMainSwing = false
	self.firstOffSwing = false
end

frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("PLAYER_ENTER_COMBAT")
frame:RegisterEvent("PLAYER_LEAVE_COMBAT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		lib[event](lib, event, CombatLogGetCurrentEventInfo())
	else
		lib[event](lib, event, ...)
	end
end)

--[[
	Set table data based on current game version
]]--
if isClassic then
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
		[56641] = true, -- Steady Shot (rank 1)
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

	prevent_reset_swing_auras = {}

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
