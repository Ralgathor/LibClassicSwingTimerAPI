local MAJOR, MINOR = "LibClassicSwingTimerAPI", 4
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

local frame = CreateFrame("Frame")
local C_Timer, tonumber = C_Timer, tonumber
local GetSpellInfo, GetTime, CombatLogGetCurrentEventInfo = GetSpellInfo, GetTime, CombatLogGetCurrentEventInfo
local UnitAttackSpeed, UnitAura, UnitGUID, UnitRangedDamage = UnitAttackSpeed, UnitAura, UnitGUID, UnitRangedDamage

local isRetails = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local isClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local isBCC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_BURNING_CRUSADE
local isWarth = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_WRATH_OF_THE_LICH_KING
local isClassicOrBCC = isClassic or isBCC

local gameVersion = (isRetails and "RETAILS") or (isClassic and "CLASSIC") or (isBCC and "BCC") or (isWarth and "WRATH")

local reset_swing_spells = {
	[16589] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Noggenfogger Elixir
	[2645] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Ghost Wolf
	[2764] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Throw
	[3018] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Shoots,
	[5019] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Shoot Wand
	[5384] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Feign Death
	[75] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = true, }, -- Auto Shot
	[20066] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Repentance
	[51533] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Feral Spirit
}

local reset_swing_channel_spells = {
	[257044] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = false, ["RETAILS"] = true, }, -- Rapide Fire
}

local prevent_swing_speed_update = {
	[768] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = true, }, -- Cat Form
	[5487] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = true, }, -- Bear Form
	[9634] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = true, }, -- Dire Bear Form
}

local next_melee_spells = {
	[47450] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 13)
	[47449] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 12)
	[30324] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 11)
	[29707] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 10)
	[25286] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 9)
	[11567] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 18)
	[11566] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 7)
	[11565] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 6)
	[11564] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 5)
	[1608] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 4)
	[285] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 3)
	[284] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 2)
	[78] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heroic Strike (rank 1)
	[47520] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Cleave (rank 8)
	[47519] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Cleave (rank 7)
	[25231] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Cleave (rank 6)
	[20569] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Cleave (rank 5)
	[11609] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Cleave (rank 4)
	[11608] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Cleave (rank 3)
	[7369] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Cleave (rank 2)
	[845] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Cleave (rank 1)
	[48996] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Raptor Strike (rank 11)
	[48995] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Raptor Strike (rank 10)
	[27014] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Raptor Strike (rank 9)
	[14266] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Raptor Strike (rank 8)
	[14265] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Raptor Strike (rank 7)
	[14264] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Raptor Strike (rank 6)
	[14263] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Raptor Strike (rank 5)
	[14262] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Raptor Strike (rank 4)
	[14261] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Raptor Strike (rank 3)
	[14260] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Raptor Strike (rank 2)
	[2973] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Raptor Strike (rank 1)
	[6807] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Maul (rank 1)
	[6808] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Maul (rank 2)
	[6809] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Maul (rank 3)
	[8972] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Maul (rank 4)
	[9745] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Maul (rank 5)
	[9880] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Maul (rank 6)
	[9881] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Maul (rank 7)
	[26996] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Maul (rank 8)
	[48479] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Maul (rank 9)
	[48480] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Maul (rank 10)
}

local noreset_swing_spells = {
	[23063] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Dense Dynamite
	[4054] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Rough Dynamite
	[4064] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Rough Copper Bomb
	[4061] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Coarse Dynamite
	[8331] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Ez-Thro Dynamite
	[4065] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Large Copper Bomb
	[4066] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Small Bronze Bomb
	[4062] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Heavy Dynamite
	[4067] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Big Bronze Bomb
	[4068] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Iron Grenade
	[23000] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Ez-Thro Dynamite II
	[12421] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Mithril Frag Bomb
	[4069] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Big Iron Bomb
	[12562] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- The Big One
	[12543] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Hi-Explosive Bomb
	[19769] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Thorium Grenade
	[19784] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Dark Iron Bomb
	[30216] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Fel Iron Bomb
	[19821] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Arcane Bomb
	[39965] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Frost Grenade
	[30461] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- The Bigger One
	[30217] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Adamantite Grenade
	[35476] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Drums of Battle
	[35475] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Drums of War
	[35477] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Drums of Speed
	[35478] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Drums of Restoration
	[56641] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Steady Shot (rank 1)
	[34120] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Steady Shot (rank 2)
	[49051] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Steady Shot (rank 3)
	[49052] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Steady Shot (rank 4)
	[19434] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Aimed Shot (rank 1)
	[1464] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 1)
	[8820] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 2)
	[11604] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 3)
	[11605] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 4)
	[25241] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 5)
	[25242] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 6)
	[47474] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 7)
	[47475] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 8)
	[48467] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Hurricane (rank 5)
	[27012] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Hurricane (rank 4)
	[17402] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Hurricane (rank 3)
	[17401] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Hurricane (rank 2)
	[16914] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Hurricane (rank 1)
	[12051] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = true, }, -- Evocation
	[58434] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Volley (rank 6)
	[58431] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Volley (rank 5)
	[27022] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Volley (rank 4)
	[14295] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Volley (rank 3)
	[14294] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Volley (rank 2)
	[1510] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Volley (rank 1)
	--35474 Drums of Panic DO reset the swing timer, do not add
	[120360] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = false, ["RETAILS"] = true, }, -- Barrage
	[56641] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = false, ["RETAILS"] = true, }, -- Steady Shot
	[19434] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = false, ["RETAILS"] = true, }, -- Aimed Shot
	[113656] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = false, ["RETAILS"] = true, }, -- Fists of Fury
	[198013] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = false, ["RETAILS"] = true, }, -- Eye Beam
}

local prevent_reset_swing_auras = {
	[53817] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Maelstrom Weapon
}

local pause_swing_spells = {
	[1464] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 1)
	[8820] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 2)
	[11604] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 3)
	[11605] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 4)
	[25241] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 5)
	[25242] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 6)
	[47474] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 7)
	[47475] = {["CLASSIC"] = false, ["BCC"] = false, ["WRATH"] = true, ["RETAILS"] = false, }, -- Slam (rank 8)
}

local ranged_swing = {
	[75] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = true, }, -- Auto Shot
	[3018] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Shoot
	[2764] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Throw
	[5019] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Shoot Wand
}

local reset_ranged_swing = {
	[58433] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Volley (rank 6)
	[58432] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Volley (rank 5)
	[42234] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Volley (rank 4)
	[42245] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Volley (rank 3)
	[42244] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, }, -- Volley (rank 2)
	[42243] = {["CLASSIC"] = true, ["BCC"] = true, ["WRATH"] = true, ["RETAILS"] = false, },  -- Volley (rank 1)
}

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
		if isRetails and hand == "mainhand" then		
			self:SwingStart(hand, now, true)
			self:Fire("SWING_TIMER_CLIPPED", hand)
		elseif not isRetails then
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
			if not isClassicOrBCC and not isRetails then
				self:SwingStart("ranged", now, true)
			end
		else
			self.firstMainSwing = true
			self:SwingStart("mainhand", now, false)
			if not isClassicOrBCC and not isRetails then
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
		if spell and prevent_swing_speed_update[spell] and prevent_swing_speed_update[spell][gameVersion] then
			self.skipNextAttackSpeedUpdate = now
			self.skipNextAttackSpeedUpdateCount = 2
		end
		if spell and prevent_reset_swing_auras[spell] and prevent_reset_swing_auras[spell][gameVersion] then
			self.preventSwingReset = subEvent == "SPELL_AURA_APPLIED"
		end
	elseif (subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_MISSED") and sourceGUID == self.unitGUID then
		local spell = amount
		if reset_ranged_swing[spell] and reset_ranged_swing[spell][gameVersion] then
			if isRetails then
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
	if spell and pause_swing_spells[spell] and pause_swing_spells[spell][gameVersion] and self.pauseSwingTime then
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
	if spell ~= nil and next_melee_spells[spell] and next_melee_spells[spell][gameVersion] then
		self:SwingStart("mainhand", now, false)
		if not self.isClassicOrBCC and not isRetails then
			self:SwingStart("ranged", now, true)
		end
	end
	if (spell and reset_swing_spells[spell] and reset_swing_spells[spell][gameVersion]) or (self.casting and not self.preventSwingReset) then
		if isRetails then		
			self:SwingStart("mainhand", now, not (ranged_swing[spell] and ranged_swing[spell][gameVersion])) -- set reset flag to true if the spell is not in list of ranged swing spells
		else
			self:SwingStart("mainhand", now, true)
			self:SwingStart("offhand", now, true)
			self:SwingStart("ranged", now, not (ranged_swing[spell] and ranged_swing[spell][gameVersion])) -- set reset flag to true if the spell is not in list of ranged swing spells
		end
	end
	if spell and pause_swing_spells[spell] and pause_swing_spells[spell][gameVersion] and self.pauseSwingTime then
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
				if not isRetails then
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
		local endOfCast = now + (castTime / 1000) -- endOfCast is not use anywhere
		self.casting = true
		self.preventSwingReset = self.preventSwingReset or (noreset_swing_spells[spell] and noreset_swing_spells[spell][gameVersion])
		if spell and pause_swing_spells[spell] and pause_swing_spells[spell][gameVersion] then
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
	self.preventSwingReset = noreset_swing_spells[spell] and noreset_swing_spells[spell][gameVersion]
end

function lib:UNIT_SPELLCAST_CHANNEL_STOP(_, _, _, spell)
	local now = GetTime()
	self.channeling = false
	if (spell and reset_swing_channel_spells[spell] and reset_swing_channel_spells[spell][gameVersion]) then
		if isRetails then		
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
		if not isRetails then
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
