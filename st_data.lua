local lib = LibStub("LibClassicSwingTimerAPI", true)
if not lib then return end

lib.reset_swing_spells = {
	[2764] = true, -- Throw
	[3018] = true, -- Shoots,
	[5019] = true, -- Shoot Wand
	[5384] = true, -- Feign Death
	[75] = true, -- Auto Shot
	[257044] = true, -- Rapide Fire
}

lib.prevent_swing_speed_update = {
	[768] = true, -- Cat Form
	[5487] = true, -- Bear Form
	[9634] = true, -- Dire Bear Form
}

lib.next_melee_spells = {}

lib.noreset_swing_spells = {
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
	[48467] = true, -- Hurricane (rank 5)
	[27012] = true, -- Hurricane (rank 4)
	[17402] = true, -- Hurricane (rank 3)
	[17401] = true, -- Hurricane (rank 2)
	[16914] = true, -- Hurricane (rank 1)
	[12051] = true, -- Evocation
	--35474 Drums of Panic DO reset the swing timer, do not add
}

lib.prevent_reset_swing_auras = {}

lib.pause_swing_spells = {}

lib.ranged_swing = {
	[75] = true, -- Auto Shot
	[3018] = true, -- Shoot
	[2764] = true, -- Throw
	[5019] = true, -- Shoot Wand
}

lib.reset_ranged_swing = {
}
