local lib = LibStub("LibClassicSwingTimerAPI", true)
if not lib then return end

lib.reset_swing_spells = {
	[75] = true, -- Auto Shot
}

lib.reset_swing_channel_spells = {
	[257044] = true, -- Rapide Fire
}

lib.prevent_swing_speed_update = {
	[768] = true, -- Cat Form
	[5487] = true, -- Bear Form
	[9634] = true, -- Dire Bear Form
}

lib.next_melee_spells = {}

lib.noreset_swing_spells = {
	[12051] = true, -- Evocation
	[120360] = true, -- Barrage
	[56641] = true, -- Steady Shot
	[19434] = true, -- Aimed Shot
}

lib.prevent_reset_swing_auras = {}

lib.pause_swing_spells = {}

lib.ranged_swing = {
	[75] = true, -- Auto Shot
}

lib.reset_ranged_swing = {
}
