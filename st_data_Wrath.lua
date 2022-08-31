local lib = LibStub("LibClassicSwingTimerAPI", true)
if not lib then return end

lib.reset_swing_spells = {
	[16589] = true, -- Noggenfogger Elixir
	[2645] = true, -- Ghost Wolf
	[51533] = true, -- Feral Spirit
	[2764] = true, -- Throw
	[3018] = true, -- Shoots,
	[5019] = true, -- Shoot Wand
	[5384] = true, -- Feign Death
	[75] = true, -- Auto Shot
	[20066] = true, -- Repentance
}

lib.prevent_swing_speed_update = {
	[768] = true, -- Cat Form
	[5487] = true, -- Bear Form
	[9634] = true, -- Dire Bear Form
}

lib.next_melee_spells = {
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

lib.prevent_reset_swing_auras = {
	[53817] = true, -- Maelstrom Weapon
}

lib.pause_swing_spells = {
	[1464] = true, -- Slam (rank 1)
	[8820] = true, -- Slam (rank 2)
	[11604] = true, -- Slam (rank 3)
	[11605] = true, -- Slam (rank 4)
	[25241] = true, -- Slam (rank 5)
	[25242] = true, -- Slam (rank 6)
	[47474] = true, -- Slam (rank 7)
	[47475] = true, -- Slam (rank 8)
}

lib.ranged_swing = {
	[75] = true, -- Auto Shot
	[3018] = true, -- Shoot
	[2764] = true, -- Throw
	[5019] = true, -- Shoot Wand
}

lib.reset_ranged_swing = {
	[58433] = true, -- Volley
	[58432] = true, -- Volley
	[42234] = true, -- Volley
	[42245] = true, -- Volley
	[42244] = true, -- Volley
	[42243] = true,  -- Volley
}
