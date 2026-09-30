# M1 Session Script — library verification remainders + Classic+ spell probes

Consolidated in-game checklist for the M1 session (roadmap: 4everSwingTimer
docs/SPEC.md section 11). Everything here needs the beta client and play
time; nothing needs code changes first. Run in order - the dual-wield and
wand items double as verification for the addon's off-hand and ranged bars.

Client: WoW: Forever beta. Suggested: loglevel 2 + BugSack, and install the
current 4everSwingTimer build (it doubles as the test rig - its bars surface
exactly the library events under test).

LibStub minor is equal (34) on the 2.2.0-beta2 release and the
feature/forever-support build with the parry fix, so load order decides
which library copy wins: replace the embedded LibClassicSwingTimerAPI.lua
inside 4everSwingTimer's Libs/ with the fix-candidate build for the parry
items; do not rely on a second copy loading later.

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

### B3. Parry haste on Forever (UNIT_COMBAT handler shipped, needs final captures)

1. Outgoing parry: melee a frontal mob until IT parries YOU, with the UC macro
   from the appendix active. Expect the parry on the defender's tokens
   (target/nameplate), never "player" - the outgoing DODGE analog is captured
   (2026-09-30); the outgoing PARRY itself is not yet.
2. Dungeon mid-fight: UNIT_COMBAT tokens stay plain (display-feed channel),
   the lib fires UNIT_SWING_TIMER_UPDATE on player parries, the next
3. Parry direction coverage - RESOLVED (2026-09-30 third capture): player
   parries fire UNIT_COMBAT reliably (seven of seven) and outgoing parries do
   NOT haste the player (three observed, normal cadence after); the second
   capture's P-less hastes were most likely transcription loss. The formula is
   settled: no effect before 20% of the swing elapsed or at <=20% remaining;
   otherwise remaining -= 40% of weapon speed, floored at 20%. Optional
   confirmation: a parry landing 11-30% into the swing would pin the exact
   no-effect threshold line.
4. Late-band parry (early-band bug discriminator): with the same probe, catch
   a PA player line in the last 20% of the swing (more than 80% of the weapon
   speed after the last S). Normal cadence after = the early discard band is
   intended tuning and the tail matches the documented rule; a swing arriving
   LATER than normal (gap > weapon speed) = swapped-comparison bug confirmed
   (the lib would then model the delay as an engine deviation). Beta report
   drafted in FOREVER_API_FINDINGS section 8.10.
5. Verbatim capture for the floor question (fifth capture flagged it):
   enable /chatlog (the client writes every print to Logs\WoWChatLog.txt in
   the game folder), run the PA2 probe, tank a few minutes, then read the
   parry->landing offsets straight from the file. Every directly measured
   offset so far (0.301, 0.456, 0.116) lands below the 20% floor and fits
   no-floor exactly, while four parry-less gaps fit the floor - screenshot
   transcription cannot separate them. This settles floor vs no floor and
   likely the exact early-band threshold; the shipped floor is held until
   then (bounded one-cycle error either way).
   PLAYER_SWING lands at the hastened expiry, no Lua errors.

## Part C - addon beta checklist (SPEC section 7, items not yet covered in effect testing)

1. Hunter: ranged bar per Auto Shot; strafe mid-shot reschedules once
   (amber); sustained strafe holds amber until standing (recast signature).
2. Cast mid-swing: interrupt treatment - red fill + red pip + outer halo +
   shake, then restart.
3. Parry: green stack (fill + spark + halo + pop) on real parries only.
   With the parry-fix library loaded the stack fires in real time at the
   parry (mid-swing UNIT_SWING_TIMER_UPDATE) and the landing stays quiet;
   on the beta2 library it fires at the hastened landing (early-landing
   fallback) and ordinary swings stay quiet (frame-race fix).
4. Dungeon pull mid-fight: no Lua errors, bars accurate (restricted content).
5. Reload: settings, position, palette persist.

## Exit criteria

All A/B items recorded (verdicts in the respective plan docs); C green with
no errors. Then: library 2.2.0 stable release prep (M2), addon 1.0.0-beta1
packaging and publishing prep (M4/M5: CurseForge/Wago name check, project
IDs, repo secrets, first packager run).
