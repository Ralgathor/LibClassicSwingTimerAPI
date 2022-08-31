local MAJOR, MINOR = "LibClassicSwingTimerAPI", 4
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

local frame = CreateFrame("Frame")
local C_Timer, tonumber = C_Timer, tonumber
local GetSpellInfo, GetTime, CombatLogGetCurrentEventInfo = GetSpellInfo, GetTime, CombatLogGetCurrentEventInfo
local UnitAttackSpeed, UnitAura, UnitGUID, UnitRangedDamage = UnitAttackSpeed, UnitAura, UnitGUID, UnitRangedDamage

lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)

function lib:Fire(event, ...)
	self.callbacks:Fire(event, ...)
end

function lib:ADDON_LOADED(_, addOnName)
	if addOnName ~= MAJOR then
		return
	end

	self.unitGUID = UnitGUID("player")

	local mainSpeed, offSpeed = UnitAttackSpeed("player")
	local now = GetTime()

	self.mainSpeed = mainSpeed
	self.offSpeed = offSpeed or 0

	self.lastMainSwing = now
	self.mainExpirationTime = self.lastMainSwing + self.mainSpeed
	self.firstMainSwing = false

	self.lastOffSwing = now
	self.offExpirationTime = self.lastMainSwing + self.mainSpeed
	self.firstOffSwing = false

	self.lastRangedSwing = now
	self.rangedSpeed = UnitRangedDamage("player") or 0
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
		if self.isRetails and hand == "mainhand" then		
			self:SwingStart(hand, now, true)
			self:Fire("SWING_TIMER_CLIPPED", hand)
		elseif not self.isRetails then
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
			if not lib.isClassicOrBCC and not self.isRetails then
				self:SwingStart("ranged", now, true)
			end
		else
			self.firstMainSwing = true
			self:SwingStart("mainhand", now, false)
			if not lib.isClassicOrBCC and not self.isRetails then
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
		if spell and self.prevent_swing_speed_update[spell] then
			self.skipNextAttackSpeedUpdate = now
			self.skipNextAttackSpeedUpdateCount = 2
		end
		if spell and self.prevent_reset_swing_auras[spell] then
			self.preventSwingReset = subEvent == "SPELL_AURA_APPLIED"
		end
	elseif (subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_MISSED") and sourceGUID == self.unitGUID then
		local spell = amount
		if self.reset_ranged_swing[spell] then
			if self.isRetails then
				self:SwingStart("mainhand", GetTime(), true)
			else
				self:SwingStart("ranged", GetTime(), true)
			end
		end
	end
end

function lib:UNIT_ATTACK_SPEED()
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
	if spell and self.pause_swing_spells[spell] and self.pauseSwingTime then
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
	if spell ~= nil and self.next_melee_spells[spell] then
		self:SwingStart("mainhand", now, false)
		if not self.isClassicOrBCC and not self.isRetails then
			self:SwingStart("ranged", now, true)
		end
	end
	if (spell and self.reset_swing_spells[spell]) or (self.casting and not self.preventSwingReset) then
		if self.isRetails then		
			self:SwingStart("mainhand", now, not self.ranged_swing[spell]) -- set reset flag to true if the spell is not in list of ranged swing spells
		else
			self:SwingStart("mainhand", now, true)
			self:SwingStart("offhand", now, true)
			self:SwingStart("ranged", now, not self.ranged_swing[spell]) -- set reset flag to true if the spell is not in list of ranged swing spells
		end
	end
	if spell and self.pause_swing_spells[spell] and self.pauseSwingTime then
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
	if self.casting and spell ~= 6603 then -- 6603=Auto Attack prevent set casting to false when auto attack is toggle on
		self.casting = false
	end
	if spell == 5384 then -- 5384=Feign Death
		self.feignDeathTimer = C_Timer.NewTicker(0.1, function() -- Start watching FD CD
			local start, _, enabled = GetSpellCooldown(spell)
			if enabled == 1 then -- Reset ranged swing when FD CD start
				self:SwingStart("mainhand", start, true)
				self:SwingStart("offhand", start, true)
				if not self.isRetails then
					self:SwingStart("ranged", start, true)
				end
				if self.feignDeathTimer then
					self.feignDeathTimer:Cancel()
				end
			end
		end);
	end
end

function lib:UNIT_SPELLCAST_START(_, unit, _, spell)
	if spell then
		local now = GetTime()
		local name, rank, icon, castTime, minRange, maxRange, spellId = GetSpellInfo(spell)
		local endOfCast = now + (castTime / 1000) -- endOfCast is not use anywhere
		self.casting = true
		self.preventSwingReset = self.preventSwingReset or self.noreset_swing_spells[spell]
		if spell and self.pause_swing_spells[spell] then
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
	self.preventSwingReset = self.noreset_swing_spells[spell]
end

function lib:UNIT_SPELLCAST_CHANNEL_STOP()
	self.channeling = false
end

function lib:PLAYER_EQUIPMENT_CHANGED(_, equipmentSlot)
	if equipmentSlot == 16 or equipmentSlot == 17 or equipmentSlot == 18 then
		local now = GetTime()
		self:SwingStart("mainhand", now, true)
		self:SwingStart("offhand", now, true)
		if not self.isRetails then
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
frame:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		lib[event](lib, event, CombatLogGetCurrentEventInfo())
	else
		lib[event](lib, event, ...)
	end
end)
