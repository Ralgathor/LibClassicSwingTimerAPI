# M1 Session Script — library verification remainders + Classic+ spell probes

Consolidated in-game checklist for the M1 session (roadmap: 4everSwingTimer
docs/SPEC.md section 11). Everything here needs the beta client and play
time; nothing needs code changes first. Run in order - the dual-wield and
wand items double as verification for the addon's off-hand and ranged bars.

Client: WoW: Forever beta. Suggested: loglevel 2 + BugSack, and install the
current 4everSwingTimer build (it doubles as the test rig - its bars surface
exactly the library events under test).

## Part A - library §8.9 remainders

### A1. Dual-wield off-hand on Forever (never verified)

Char: any dual wielder (warrior/rogue/hunter melee).

1. `/run local L=LibStub("LibClassicSwingTimerAPI") local f=CreateFrame("Frame") L.RegisterCallback(f,"UNIT_SWING_TIMER_START",function(ev,u,s,e,h) print("START",h,s,e) end) L.RegisterCallback(f,"UNIT_SWING_TIMER_STOP",function(ev,u,h) print("STOP",h) end)`
2. Auto-attack a dummy. Expected: mainhand AND offhand START events
   interleaved, both hands' bars draining on their own cadence.
3. In 4everSwingTimer: both bars visible with correct labels; optional delta
   text sane.

### A2. Wand on Forever (assumed covered by PLAYER_SWING type 2)

Char: any caster with a wand.

1. Shoot Wand (5019) at a dummy with the same listener.
2. Expected: ranged START/STOP per shot with the wand speed; the addon's
   ranged bar tracks it. Note any anchor oddity (the library assumes
   PLAYER_SWING covers wands - this is the check).

### A3. Classic Era regression (all-client changes: PLAYER_DEAD reset etc.)

Char on Classic Era, melee.

1. Dummy: cadence identical to 2.1.x; parry haste visibly shortens the bar
   mid-swing (CLEU path) - this also confirms the addon renders UPDATE.
2. Die in the open world, accept an in-place resurrection: one STOP per
   active hand at death, clean START on the next swing, no errors.

## Part B - Classic+ spell probes (IMPROVEMENT_PLAN section 6)

### B1. Slam (candidate pause_swing_spells, Forever) - level 20+ warrior

With and without Improved Slam talented (talent 12862: removes the delay):

```lua
/run PS2=PS2 or CreateFrame("Frame") PS2:RegisterEvent("UNIT_SPELLCAST_START") PS2:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") PS2:SetScript("OnEvent",function(_,_,e,u,_,s) if u=="player" then print(e,s) end end)
```

1. Cast Slam mid-swing-cycle; record START/SUCCEEDED spell IDs; compare
   against PLAYER_SWING anchors (does the pause model or reset model match?).
2. `/run local n,_,_,_,_,_,id=GetSpellInfo("Slam") print(n,id)` - rank spell
   IDs straight from the spellbook.

### B2. Maelstrom Weapon (candidate prevent_reset_swing_auras, Forever) - Enhancement shaman

1. `/run local t={} for i=1,40 do local n,_,_,_,_,_,_,_,_,sid=UnitAura("player",i) if n then t[#t+1]=n.."="..sid end end print(table.concat(t,", "))`
   with stacks up - capture the aura spell ID.
2. Cast Lightning Bolt at 5 stacks (instant at rank 5): confirm it fires
   UNIT_SPELLCAST_SUCCEEDED that would otherwise reset the swing timer - and
   that the swing cadence is undisturbed.

## Part C - addon beta checklist (SPEC section 7, items not yet covered in effect testing)

1. Hunter: ranged bar per Auto Shot; strafe mid-shot reschedules once
   (amber); sustained strafe holds amber until standing (recast signature).
2. Cast mid-swing: interrupt treatment - red fill + red pip + outer halo +
   shake, then restart.
3. Parry: green stack (fill + spark + halo + pop) only on real parries -
   ordinary swings stay quiet (frame-race fix).
4. Dungeon pull mid-fight: no Lua errors, bars accurate (restricted content).
5. Reload: settings, position, palette persist.

## Exit criteria

All A/B items recorded (verdicts in the respective plan docs); C green with
no errors. Then: library 2.2.0 stable release prep (M2), addon 1.0.0-beta1
packaging and publishing prep (M4/M5: CurseForge/Wago name check, project
IDs, repo secrets, first packager run).
