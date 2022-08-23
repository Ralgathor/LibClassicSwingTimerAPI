local swingTimerFrame = _G["SwingTimerFrame"] or CreateFrame("Frame", "SwingTimerFrame");

SwingTimerAPI = SwingTimerAPI or {}

SwingTimerAPI.unit = "player"
SwingTimerAPI.unitGUID = UnitGUID(SwingTimerAPI.unit)

local mainSpeed, offSpeed = UnitAttackSpeed(SwingTimerAPI.unit)
local now = GetTime()

SwingTimerAPI.mainSpeed = mainSpeed
SwingTimerAPI.offSpeed = offSpeed or 0

SwingTimerAPI.lastMainSwing = now
SwingTimerAPI.mainExpirationTime = SwingTimerAPI.lastMainSwing + SwingTimerAPI.mainSpeed
SwingTimerAPI.firstMainSwing = false

SwingTimerAPI.lastOffSwing = now
SwingTimerAPI.offExpirationTime = SwingTimerAPI.lastMainSwing + SwingTimerAPI.mainSpeed
SwingTimerAPI.firstOffSwing = false

SwingTimerAPI.lastRangedSwing = now
SwingTimerAPI.rangedSpeed = UnitRangedDamage(SwingTimerAPI.unit) or 0
SwingTimerAPI.rangedAttackSpeedMultiplier = 1
SwingTimerAPI.rangedExpirationTime = SwingTimerAPI.lastRangedSwing + SwingTimerAPI.rangedSpeed

SwingTimerAPI.mainTimer = nil
SwingTimerAPI.offTimer = nil
SwingTimerAPI.rangedTimer = nil
SwingTimerAPI.calculaDeltaTimer = nil

SwingTimerAPI.casting = false
SwingTimerAPI.isAttacking = false
SwingTimerAPI.preventSwingReset = false
SwingTimerAPI.skipNextAttack = nil
SwingTimerAPI.skipNextAttackCount = 0

SwingTimerAPI.reset_swing_spells = {
    [16589] = true, -- Noggenfogger Elixir
    [2645] = true, -- Ghost Wolf
    [51533] = true, -- Feral Spirit
    [2764] = true, -- Throw
    [3018] = true, -- Shoots,
    [5384] = true, -- Feign Death
    [75] = true, -- Auto Shot
}

SwingTimerAPI.next_melee_spells = {
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

SwingTimerAPI.noreset_swing_spells = {
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
    --35474 Drums of Panic DO reset the swing timer, do not add
}

SwingTimerAPI.prevent_reset_swing_auras = {
    53817, -- Maelstrom Weapon
}

SwingTimerAPI.callbacks = SwingTimerAPI.callbacks or LibStub("CallbackHandler-1.0"):New(SwingTimerAPI)

local WA_GetUnitAura = function(unit, spell, filter)
    if filter and not filter:upper():find("FUL") then
        filter = filter.."|HELPFUL"
    end
    for i = 1, 255 do
        local name, _, _, _, _, _, _, _, _, spellId = UnitAura(unit, i, filter)
        if not name then return end
        if spell == spellId or spell == name then
        return UnitAura(unit, i, filter)
        end
    end
end

function SwingTimerAPI:CalculateDelta()
    if self.offSpeed > 0 and self.mainExpirationTime ~= nil and self.offExpirationTime ~= nil then
        SwingTimerAPI.callbacks:Fire("SWING_TIMER_DELTA", self.mainExpirationTime - self.offExpirationTime)
    end
end

function SwingTimerAPI:SwingStart(hand, startTime, isReset)
    if hand == "mainhand" then
        if self.mainTimer and isReset then
            self.mainTimer:Cancel()
        end
        self.lastMainSwing = startTime
        local mainSpeed, _ = UnitAttackSpeed(self.unit)
        self.mainSpeed = mainSpeed
        self.mainExpirationTime = self.lastMainSwing + self.mainSpeed
        SwingTimerAPI.callbacks:Fire("SWING_TIMER_START", self.mainSpeed, self.mainExpirationTime, hand)
        if self.mainSpeed > 0 and self.mainExpirationTime - GetTime() > 0 then
            self.mainTimer = C_Timer.NewTimer(self.mainExpirationTime - GetTime(), function() self:SwingEnd("mainhand") end)
        end
    elseif hand == "offhand" then
        if self.offTimer and isReset then
            self.offTimer:Cancel()
        end
        self.lastOffSwing = startTime
        local _, offSpeed = UnitAttackSpeed(self.unit)
        self.offSpeed = offSpeed or 0
        self.offExpirationTime = self.lastOffSwing + self.offSpeed
        if self.calculaDeltaTimer then
            self.calculaDeltaTimer:Cancel()
        end
        if self.offSpeed > 0 and self.firstOffSwing == false and self.isAttacking then
            self.offExpirationTime = self.lastOffSwing + (self.offSpeed/2)
            self:CalculateDelta()
            SwingTimerAPI.callbacks:Fire("SWING_TIMER_UPDATE", self.offSpeed, self.offExpirationTime, hand)
        elseif self.offSpeed > 0 then
            SwingTimerAPI.callbacks:Fire("SWING_TIMER_START", self.offSpeed, self.offExpirationTime, hand)
            self.calculaDeltaTimer = C_Timer.NewTimer(self.offSpeed/2, function() self:CalculateDelta() end)
        end
        if self.offSpeed > 0 and self.offExpirationTime - GetTime() > 0 then
            self.offTimer = C_Timer.NewTimer(self.offExpirationTime - GetTime(), function() self:SwingEnd("offhand") end)
        end
    elseif hand == "ranged" then
        if self.rangedTimer and isReset then
            self.rangedTimer:Cancel()
        end
        self.rangedSpeed = UnitRangedDamage(self.unit) or 0
        if self.rangedSpeed ~= nil and self.rangedSpeed > 0 then
            self.rangedSpeed = self.rangedSpeed*self.rangedAttackSpeedMultiplier
            self.lastRangedSwing = startTime
            self.rangedExpirationTime = self.lastRangedSwing + self.rangedSpeed
            SwingTimerAPI.callbacks:Fire("SWING_TIMER_START", self.rangedSpeed, self.rangedExpirationTime, hand)
            if self.rangedExpirationTime - GetTime() > 0 then
                self.rangedTimer = C_Timer.NewTimer(self.rangedExpirationTime - GetTime(), function() self:SwingEnd("ranged") end)
            end
        end
    end
end

function SwingTimerAPI:SwingEnd(hand)
    SwingTimerAPI.callbacks:Fire("SWING_TIMER_STOP", hand)
    if self.casting and self.isAttacking and hand ~= "ranged" then
        local now = GetTime()
        self:SwingStart(hand, now, true)
        SwingTimerAPI.callbacks:Fire("SWING_TIMER_CLIPPED", hand)
    end
end

function SwingTimerAPI:COMBAT_LOG_EVENT_UNFILTERED(event, ts, subEvent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand)
    local now = GetTime()
    if subEvent == "SPELL_EXTRA_ATTACKS" then
        self.skipNextAttack = ts
        self.skipNextAttackCount = resisted
    elseif ((subEvent == "SWING_DAMAGE" or subEvent == "SWING_MISSED") and sourceGUID == self.unitGUID) then
        local isOffHand = isOffHand
        if subEvent == "SWING_MISSED" then 
            isOffHand = overkill
        end
        if self.skipNextAttack ~= nil and tonumber(self.skipNextAttack) and (ts - self.skipNextAttack) < 0.04 and tonumber(self.skipNextAttackCount) and not isOffHand then
            if self.skipNextAttackCount > 0 then
                self.skipNextAttackCount = self.skipNextAttackCount - 1
                return false
            end
        end
        if isOffHand then
            self.firstOffSwing = true
            self:SwingStart("offhand", now, false)
            self:SwingStart("ranged", now, true)
        else
            self.firstMainSwing = true
            self:SwingStart("mainhand", now, false)
            self:SwingStart("ranged", now, true)
        end
    elseif (subEvent == "SWING_MISSED" and amount ~= nil and amount == "PARRY" and destGUID == self.unitGUID) then
        if self.mainTimer then
            self.mainTimer:Cancel()
        end
        local swing_timer_reduced_40p = self.mainExpirationTime - (0.4 * self.mainSpeed)
        local min_swing_time = self.mainExpirationTime - (0.2 * self.mainSpeed)             
        if swing_timer_reduced_40p < min_swing_time then
            self.mainExpirationTime = min_swing_time
        else
            self.mainExpirationTime = swing_timer_reduced_40p
        end
        SwingTimerAPI.callbacks:Fire("SWING_TIMER_UPDATE", self.mainSpeed, self.mainExpirationTime, hand)
        if self.mainSpeed > 0 and self.mainExpirationTime - GetTime() > 0 then
            self.mainTimer = C_Timer.NewTimer(self.mainExpirationTime - GetTime(), function() self:SwingEnd("mainhand") end)
        end
    end
end

function SwingTimerAPI:UNIT_ATTACK_SPEED()
    if self.mainTimer then
        self.mainTimer:Cancel()
    end
    if self.offTimer then
        self.offTimer:Cancel()
    end
    local now = GetTime()
    local mainSpeedNew, offSpeedNew = UnitAttackSpeed(self.unit)
    offSpeedNew = offSpeedNew or 0
    if mainSpeedNew > 0 and self.mainSpeed > 0 and mainSpeedNew ~= self.mainSpeed then
        local multiplier = mainSpeedNew / self.mainSpeed
        local timeLeft = (self.lastMainSwing + self.mainSpeed - now) * multiplier
        self.mainSpeed = mainSpeedNew
        self.mainExpirationTime = now + timeLeft
        SwingTimerAPI.callbacks:Fire("SWING_TIMER_UPDATE", self.mainSpeed, self.mainExpirationTime, "mainhand")
        if self.mainSpeed > 0 and self.mainExpirationTime - GetTime() > 0 then
            self.mainTimer = C_Timer.NewTimer(self.mainExpirationTime - GetTime(), function() self:SwingEnd("mainhand") end)
        end
    end
    if offSpeedNew > 0 and self.offSpeed > 0 and offSpeedNew ~= self.offSpeed then
        local multiplier = mainSpeedNew / self.offSpeed
        local timeLeft = (self.lastOffSwing + self.offSpeed - now) * multiplier
        self.offSpeed = mainSpeedNew
        self.offExpirationTime = now + timeLeft
        if self.calculaDeltaTimer ~= nil then
            self.calculaDeltaTimer:Cancel()
        end
        SwingTimerAPI.callbacks:Fire("SWING_TIMER_UPDATE", self.offSpeed, self.offExpirationTime, "offhand")
        if self.offSpeed > 0 and self.offExpirationTime - GetTime() > 0 then
            self.offTimer = C_Timer.NewTimer(self.offExpirationTime - GetTime(), function() self:SwingEnd("offhand") end)
        end
    end
end

function SwingTimerAPI:UNIT_SPELLCAST_INTERRUPTED_OR_FAILED()
    self.casting = false
end
function SwingTimerAPI:UNIT_SPELLCAST_INTERRUPTED()
    self:UNIT_SPELLCAST_INTERRUPTED_OR_FAILED()
end 
function SwingTimerAPI:UNIT_SPELLCAST_FAILED()
    self:UNIT_SPELLCAST_INTERRUPTED_OR_FAILED()
end

function SwingTimerAPI:UNIT_SPELLCAST_SUCCEEDED(event, unit, guid, spell)
    local now = GetTime()
    if spell ~= nil and self.next_melee_spells[spell] then
        self:SwingStart("mainhand", now, false)
        self:SwingStart("ranged", now, true)
    end
    if (spell and self.reset_swing_spells[spell]) or ( self.casting and not self.preventSwingReset) then
        self:SwingStart("mainhand", now, true)
        self:SwingStart("offhand", now, true)
        if spell == 75 then
            self.rangedAttackSpeedMultiplier = 0.85
        elseif spell == 3018 or spell == 2764 then
            self.rangedAttackSpeedMultiplier = 1
        end
        self:SwingStart("ranged", now, (spell ~= 75 and spell ~= 3018 and spell ~= 2764))
    end
    if self.casting then
        self.casting = false
    end
end

function SwingTimerAPI:UNIT_SPELLCAST_START(event, unit, guid, spell)
    if spell then
        local now = GetTime()
        local name, rank, icon, castTime, minRange, maxRange, spellId = GetSpellInfo(spell)
        local endOfCast = now + (castTime/1000)
        self.casting = true
        self.preventSwingReset = self.noreset_swing_spells[spell]
        for _, auraid in ipairs(self.prevent_reset_swing_auras) do
            local aura = WA_GetUnitAura(self.unit,53817)
            if aura then
                self.preventSwingReset = true
            end
        end
    end
end

function SwingTimerAPI:PLAYER_EQUIPMENT_CHANGED(event, equipmentSlot, hasCurrent)
    if equipmentSlot == 16 or equipmentSlot == 17 or equipmentSlot == 18 then
        local now = GetTime()        
        self:SwingStart("mainhand", now, true)
        self:SwingStart("offhand", now, true)
        self:SwingStart("ranged", now, true)
    end
end

function SwingTimerAPI:PLAYER_ENTER_COMBAT()
    local now = GetTime()
    self.isAttacking = true
    if now > (self.offExpirationTime - (self.offSpeed/2)) then
        if self.offTimer then
            self.offTimer:Cancel()
        end
        self:SwingStart("offhand", now, true)
    end
end

function SwingTimerAPI:PLAYER_LEAVE_COMBAT()
    self.isAttacking = false
    self.firstMainSwing = false
    self.firstOffSwing = false
end

swingTimerFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
swingTimerFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
swingTimerFrame:RegisterEvent("PLAYER_ENTER_COMBAT");
swingTimerFrame:RegisterEvent("PLAYER_LEAVE_COMBAT");
swingTimerFrame:RegisterUnitEvent("UNIT_ATTACK_SPEED",SwingTimerAPI.unit);
swingTimerFrame:RegisterUnitEvent("UNIT_SPELLCAST_START",SwingTimerAPI.unit);
swingTimerFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED",SwingTimerAPI.unit)
swingTimerFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED",SwingTimerAPI.unit);
swingTimerFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED",SwingTimerAPI.unit);

swingTimerFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            SwingTimerAPI[event](SwingTimerAPI, event, CombatLogGetCurrentEventInfo())
        else
            SwingTimerAPI[event](SwingTimerAPI, event, ...)
        end
end);
