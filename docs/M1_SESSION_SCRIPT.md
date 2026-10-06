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

Caveat (2026-09-30 probe): aura data is blocked mid-combat on WoW: Forever -
UnitAura/C_UnitAuras error with "Auras cannot be accessed when secret". Run
this probe out of combat, or read the aura spell ID from the combat log's
SPELL_AURA_APPLIED records instead (docs/HASTE_APPLICATION_FINDINGS.md s4).

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
5. Verbatim capture - RESOLVED (2026-09-30 SavedVariables trace, 91 anchors,
   12 timestamped player parries): NO floor (parries with 1.014/1.433 s
   remaining landed at remaining-0.96, to 4-11 ms); no-effect threshold ~30%
   elapsed (no-effect at 0.718 s, effect at 0.742 s on the 2.4 s weapon);
   clamp-0 landings fire ~0.2 s later at the engine's next update.
   ApplyParryHaste updated accordingly; the third capture's conflicting
   parry timestamp was screenshot noise (its landing fits any effective
   parry under the no-floor rule).
   SUPERSEDED (2026-09-30 log-only join): the no-floor and ~30%-threshold
   readings were cross-stream artifacts (UNIT_COMBAT parry stamps sit
   ~0.55-0.72 s after the engine's parry instant relative to PLAYER_SWING
   anchors); the engine rule is the classic one with the 20% floor - see
   findings 8.10 FINAL.
6. Anomaly family (updated after the second verbatim trace): the anomaly
   lands swings at anchor + 60% of weapon speed with NO parry event, and
   ~4-5% of cycles show early re-anchoring landings (two shapes: ~0.6w gaps
   and 1.65-2.06 s gaps on the 2.4 s weapon). CRITICAL CONFOUND (findings
   8.10): the anomaly landing time is algebraically identical to the
   parry-haste landing for any parry before 60% of the swing elapsed, so
   individual mid-band parry readings cannot be attributed. Next probes:
   (a) single-mob fights to isolate the anomaly; (b) mid-band parries
   (t_p 0.72-1.4) hoping for normal-cadence follow-ups to bracket the
   no-effect threshold from above; (c) keep the trace armed - the library
   UPDATE lines let the model-vs-engine check run every session. Also:
   the dungeon run surfaced a getUnit secret-GUID crash (fixed - see
   findings 8.10); re-verify no Lua errors on the next run.
   RESOLVED (2026-09-30): the anomaly family is the classic rule's floor
   band - parries whose UNIT_COMBAT dispatch arrives after the
   already-hasted PLAYER_SWING and lands in the next cycle; in the combat
   log only ~2 of 688 no-parry cycles are off cadence (findings 8.10 FINAL).
7. Combat-log join (attribution for the anomaly): test /combatlog on the
   beta - run it, fight one mob, toggle off, check Logs for WoWCombatLog.txt
   and SWING_MISSED PARRY lines (the client writes this file itself; addon
   CLEU access remains refused, but the text log may not be restricted).
   If it writes: run /combatlog AND /4everswingtimer trace in the same
   session - join offline by wall-clock time (the trace session marker) and
   a shared event (a Judgement cast appears in both). The log gives source/
   dest attribution (whose attack was parried, extra SWING_DAMAGE lines),
   which settles the anomaly: unreported parries vs extra-attack procs vs
   engine-internal. PLAYER_SWING is not a combat-log event - the log is a
   join, not a replacement for the trace.
   PLAYER_SWING lands at the hastened expiry, no Lua errors.
   RESOLVED (2026-09-30): the join ran (two sessions, two weapon speeds);
   the log-only read settled the rule and the anomaly (findings 8.10 FINAL).

### B4. By-name aura presence mid-combat (C_UnitAuras.GetAuraDataBySpellName) - SPEC 10.5 probe 6

The one aura getter never probed on WoW: Forever. The 2026-09-30
investigation (HASTE_APPLICATION_FINDINGS sections 4 and 7) closed
GetPlayerAuraBySpellID (nil mid-combat with SnD up) and
GetAuraDataByIndex (throws "Auras cannot be accessed when secret while
tainted"); the section 7.1 source-level read assessed the stock UI's
by-index path only - the by-name getter is engine-side C and was never
tried. ForeverSwing's seal icon leans on it as its tier-1 read
(ref/ForeverSwing/Class.lua, in the 4everSwingTimer repo), claiming it
"still works when the game hides the names of individual buffs in
combat". One probe settles whether that claim is open or refuted on
this build.

NOTE (2026-10-04 session): every /run line below fits the client's
script-size cap. The first draft's mid-combat line did not ("cannot run
script too large") and never executed. Partials from that session: the
function exists, secrecy 2 re-confirmed for 5171, a plain localized
name; the out-of-combat baseline printed nil but was run without
confirming the buff was up, so it is not evidence; the mid-combat call
is still pending at capture time (RESOLVED below). SwingTestLog automates the rerun: /stl watch <name> (default "Slice and Dice") arms AURA lines that record every by-name outcome on UNIT_AURA and combat transitions, /stl scan (out of combat) is the M1 B2 index capture, /stl queue dumps IsCurrentSpell, and CASTSTART lines join Slam casts to swing anchors (M1 B1) - the tool was extended for this on 2026-10-04 (docs/tools/SwingTestLog).
RESOLVED (2026-10-04, build 70205): verdict 2 - dark. Nil at every
in-combat probe, including the aura's application instants; full plain
data out of combat on the same aura instance (and on the Well Fed
control, id 1248406). Recorded in HASTE_APPLICATION_FINDINGS section
7.1; evidence: docs/evidence/SwingTestLog-forever-2026-10-04.lua.

Char: rogue with Slice and Dice (5171 rank 1 / 6774 rank 2; the call
matches the name, not the ID) - the same aura the closed investigation
used. Paladin alternative: Devotion Aura (10290, always on) or Seal of
the Crusader (20162); substitute the spell ID below.

Setup, out of combat (captures the localized name - hardcoding English
names would not match on non-enUS clients, ForeverSwing's own caveat):

```lua
/run print("fn", C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) local s=C_Secrets and C_Secrets.GetSpellAuraSecrecy print("secrecy", s and s(5171))
/run local i=C_Spell.GetSpellInfo(5171) AURANAME=i and i.name print("name",AURANAME)
```

Expected: the function exists (ForeverSwing nil-guards it); secrecy 2
(ContextuallySecret - matches the 2026-09-30 classification probe); a
plain name. All three confirmed 2026-10-04.

Baseline, still out of combat, with the buff demonstrably up - for a
rogue use a food or elixir buff and set AURANAME to it (SnD does not
survive leaving combat; a nil with no buff up is a missing buff, not a
dark API):

```lua
/run AURANAME="Well Fed"
/run local ok,d=pcall(C_UnitAuras.GetAuraDataBySpellName,"player",AURANAME,"HELPFUL") print("ooc",ok,type(d),d and d.spellId,d and d.duration,d and d.expirationTime)
```

Expected: a full table, plain numbers (the by-ID call returned full data
out of combat for 10290 on build 70124). If this fails with the buff
definitely up, the call is dark on this client and the probe is moot.

Mid-combat (open world, auto-attack a mob with the aura up; set
AURANAME first - setup line 2, or AURANAME="Slice and Dice"):

```lua
/run local ok,d=pcall(C_UnitAuras.GetAuraDataBySpellName,"player",AURANAME,"HELPFUL") print("IC",ok,type(d))
/run print("byID same moment", C_UnitAuras.GetPlayerAuraBySpellID(5171))
```

The by-ID line re-confirms the gate is active at that instant (expected
nil), so a by-name table is a genuine divergence and not a missing buff.
If the IC line printed a table, still in combat, dump the fields (print
reveals the underlying number even for secret-flagged values, so pair
each raw read with its issecretvalue flag):

```lua
/run local d=C_UnitAuras.GetAuraDataBySpellName("player",AURANAME,"HELPFUL") if type(d)=="table" then print(d.spellId,d.applications,d.duration,d.expirationTime) end
/run local d=C_UnitAuras.GetAuraDataBySpellName("player",AURANAME,"HELPFUL") if type(d)=="table" then local s=issecretvalue print("sec",s(d.duration),s(d.expirationTime)) end
```

Verdicts - record in HASTE_APPLICATION_FINDINGS section 7.1, then flip
SPEC 10.5's probe list and the seal rows in 4everSwingTimer's
SPEC/BENCHMARK:

1. Throws the "Auras cannot be accessed when secret" error: the by-name
   getter shares the by-index gate. Presence stays closed - record it as
   the last aura call probed and dark. ForeverSwing's tier-1 claim is
   refuted on this build; its seal icon in combat is its tier-3 fallback
   alone (last cast + learned duration, blind to early consumption).
2. Returns nil: same verdict as GetPlayerAuraBySpellID - dark.
3. Returns a table with secret (or zeroed) duration/expirationTime:
   partial reopen. Presence alone, combined with UNIT_AURA (which fires
   fine mid-combat), gives application/removal edges: Flurry proc
   detection, Maelstrom Weapon stacks via applications if plain, seal
   consumption at Judgement. Expiry stays unschedulable from the data,
   but the removal edge observed at expiry closes the dynamic-haste
   one-swing lag (section 6) without waiting for the next PLAYER_SWING
   anchor.
4. Returns a full plain table: aura state becomes a library signal
   again - real expirationTime for the dynamic-haste table, Flurry,
   Maelstrom Weapon, Seal of the Crusader expiry. The section 6 expiry
   gap closes outright.

Optional, for verdicts 3 or 4: repeat once mid-dungeon (restricted
content is stricter - player SUCCEEDED spell IDs are unverified there,
open item 5), and dump the whole table once (for k, v in pairs(d) with
the issecretvalue guard per field) to map which fields stay plain.

### B5. Aura-count and combo-point reads mid-combat (UNIT_AURA edge-inference gates)

The 2026-10-04 capture found the one aura signal that survives combat:
UNIT_AURA fires at every application and removal instant, unidentified
(HASTE_APPLICATION_FINDINGS 7.1 item 4). Building inference on it is gated
on two reads, both automated into SwingTestLog (docs/tools/SwingTestLog):

1. `C_UnitAuras.GetAuraCount("player", "HELPFUL")` mid-combat: a plain
   count gives every UNIT_AURA edge a direction (+1/-1) and cuts false
   attribution. The tool logs a COUNT line on every UNIT_AURA fire and at
   combat transitions whenever the function exists; its session CAPS line
   records existence. Play any fight and read the lines.
2. `GetComboPoints("player", "target")` mid-combat with combo points up:
   a plain read makes SnD's expected expiry exact (duration is a known
   function of combo points), shrinking the expiry-watch window from
   9-21 s to milliseconds. Run `/stl cp` mid-fight with points up; the
   tool logs the read and its issecretvalue flag.

Char: rogue (the SnD fights are already the capture pattern). Verdicts -
plain counts/points: the edge-inference design becomes implementable
(file it in HASTE_APPLICATION_FINDINGS 7.1 item 4 and SPEC 10.5);
secret/nil/throw: the edge channel alone is too ambiguous, record both as
closed alongside the other aura reads, NeverSecret ask stays the only
path.
STATUS (2026-10-04 evening session, build 70205): the CAPS line read
`count=false cp=true` - `GetAuraCount` does not exist on this client,
that gate is CLOSED by nonexistence (no COUNT lines can ever appear).
`GetComboPoints` exists and read `CP 0.000 sec=false` mid-combat, but
2.3 s after the SnD cast consumed the points. RERUN: `/stl cp`
immediately after a Sinister Strike (points up, before spending) - one
read settles whether the edge-inference lead survives in weakened form
(exact expiry expectation from CP, no direction corroborator) or is
closed.

Night update: both manual `/stl cp` reads missed the points window (the
first mid-combat 2.3 s after the SnD cast consumed them; the night one
out of combat, 5 s before the pull). The tool now auto-logs `CP at-snd`
at every SnD cast (5171/6774) - an instant where points are guaranteed
up mid-combat, since the cast itself requires them. The next SnD cast
in any fight lands the decisive line with no user timing.

RESOLVED (2026-10-04 night, build 70205): the gate is OPEN - CP at-snd
read 1.000 and 2.000, sec=false both times, mid-combat at the cast
instants. Full chain captured end to end: cast 5837.353 (CP 1) ->
expected expiry 5846.353 -> fade edge at 5846.353 exactly (0 ms). The
SnD-half design is implementable as filed (findings 7.1 item 4); the
Flurry half still needs its crit-instant capture. One caveat recorded:
an out-of-combat fade near a reload boundary fired late (+1.96 s,
post-reload) - the mid-combat watch instances land at 0/+49/+2 ms.

Flurry half (2026-10-05 correction: the trigger is DETERMINISTIC in
classic data - every melee crit applies or refreshes Flurry while
talented, so the crit alone is the application signal and the aura edge
is optional corroboration, not identification; the probabilistic
candidate+anchor-settler design is Deadly Aspects' problem, not
Flurry's). Remaining unknowns for the capture (warrior at a higher
cap): the engine rule on Forever (does every crit trigger it, both
hands, refresh-on-crit) and the per-rank factor (talent read out of
combat). Expiry is swing-count driven under the classic rule (crits
refresh to 3 charges, swings consume them) - no combo-point read; the
library owns the swing stream. The Redoubt edge-simultaneity re-capture
is demoted to nice-to-have corroboration.

The hunter talent proc Wowhead Forever lists as spell 19552 "Deadly
Aspects" (classic-era 19552 = Quick Shots, the Improved Aspect of the
Hawk proc) is a ranged proc-class dynamic-haste source - the third
edge-inference family member after SnD (cast-class, chain validated)
and Flurry (crit-class, capture pending), and the easiest of the three:
its application correlates with PLAYER_SWING type 2 (the library logs
every ranged swing), and its duration is fixed in classic data (12 s),
so application and expiry are both edge-watchable with no combo-point
dependency. The existing tool captures it with no changes.

Char: hunter with Aspect of the Hawk and Improved Aspect of the Hawk
(note the talent rank).

1. Out of combat, proc up (shoot until it procs, then stop):
   `/stl watch Deadly Aspects` (the Wowhead-Forever name; fall back to
   any ranged haste buff visible) and `/stl aura` - the AURA line gives
   the actual spell ID, duration and applications: the Forever ID
   against classic 19552, the duration against 12 s.
2. `/stl note deadly-aspects rank N`, then shoot a dummy or mob: the
   tool logs every PLAYER_SWING type 2 (ranged anchors) and every
   UNIT_AURA edge mid-combat; proc application edges should sit at
   ranged-swing instants, and the anchor durations before/during/after
   give the factor (base/hasted ratio, the SnD-rank-2 method; classic
   reference 3/6/9/12/15 percent by rank - verify per rank on this
   client).
3. Let it fade mid-shooting: the fade edge vs application + duration
   is the expiry-watch datum (time-fixed class, like SnD).

This session also covers the ranged-reload probe (SPEC 10.5 probe 2)
CAVEAT (application half, 2026-10-05 review): an aura-gain edge at a
swing instant is expected from ANY on-hit effect (enchants, trinket and
talent procs key off the same swings) - swing+edge is a candidate
generator, not an identification. The settler is the next ranged
anchor's plain speed payload: hasted = real proc (candidate confirmed),
unchanged = revert (one shot of bounded error, self-correcting), with
the fade edge at the expected expiry as the temporal cross-check.
Step 2 analysis must therefore count false candidates - edges at
swing instants followed by an UNCHANGED anchor speed - against real
proc applications (anchor speed drops); if an enchanted weapon or
on-hit trinket is available, capture with it up for the noise
measurement.

and the hunter checklist items (SPEC 7 item 4) in the same fights.

The tool now also logs UNIT_ATTACK_SPEED (ATKSPEED lines, secrecy flags
included): the event fires live in combat (verified: weapon swap and the
SotC change) while its data reads are secret - if the B6 capture shows
ATKSPEED lines at the proc application instants, it is a far tighter
candidate generator than the aura edge (it fires only on real
attack-speed changes; on-hit procs that do not change attack speed do
not fire it), and it also answers the dynamic-haste fire question.
Tool notes: the tool logs UNIT_ATTACK_SPEED (ATKSPEED lines, secrecy flags,
the double-fire visible) on every fire, and SPEED lines (UnitAttackSpeed's
three returns plus UnitRangedDamage, num()-masked with issecretvalue flags)
at login, at the combat enter/leave restriction flips, and on demand
(`/stl speed`) - one fight re-verifies the findings 4.2 secrecy rule on the
current build. The ATKSPEED lines settle whether the event fires at
dynamic-haste cast instants (open item 4) and for ranged-only and
off-hand-only changes (the Layer-1 question).

CONFIRMED (2026-10-05, build 70205): UNIT_ATTACK_SPEED fires at the SnD
application instant (simultaneous with the cast, mid-combat, secret
payload) and at the expiry (+0.30 s after the fade edge, plain), and it
double-fires per change - any consumer must dedupe. The 4.2 secrecy rule
is re-verified with a boundary nuance: the combat-enter instant still
reads plain (the flip lands after the event).

ROUND 1 (2026-10-05): refresh-no-fire CONFIRMED twice; fade fire twice
more (+93/-24 ms vs the CP-formula expiry, matching the recast duration -
replace-on-recast confirmed); application fire 4 total; CP plain
mid-combat at 1.000 and 2.000.

ROUND 2 - CONFIRMED (2026-10-05): the mid-combat fade fired ATKSPEED x2
at +412 ms of the CP-formula expiry, secret payload, with the anchor
transition visible in the same fight (hasted 1.403/1.485 up to the fire,
unhasted 1.683/1.782 from 620 ms after it). The rogue side of the
transition-parity design is COMPLETE; the SnD implementation is no longer
capture-gated. Remaining: the warrior (Flurry charge-0) and hunter
(Deadly Aspects pair) captures.

Transition-parity verification list (findings 7.1 item 4): SnD recast
while active (expect NO fire); Flurry charge-0 fire at the 3rd swing's
landing; the Deadly Aspects gain/fade pair ~12 s apart; the combat-enter
plain-window bracket.
the cast instants).

### B7. Engine-drawn cooldown icon (value-sink visual check) - any class

The oracle runs (2026-10-05) proved `StatusBar:SetValue` accepts secrets
and that every read-back path is secret, but the probe bar sat off-screen:
nobody has seen whether an icon anchored to a secret fill lands in the
right place. This is the timeline concept's engine-drawn row. Display-only;
it cannot reopen the oracle.

1. Pick a spell with a cooldown between 6 and 30 s and cast it once out of
   combat (or note its spell ID).
2. `/stl sinkview` (follows the last spell cast) or `/stl sinkview <id>`.
   A movable panel appears: a 10 s bar with 0-10 s ticks, the spell icon
   riding the fill edge, a number top-right, and a native cooldown swipe
   at the right end. Out of combat everything reads plain - the baseline.
3. Pull a dummy or a mob, cast the spell mid-combat, and watch one full
   cooldown. Mark it: `/stl note sinkview <pass|fail> <what you saw>`.
4. `/stl sinkview off`, `/reload`.

PASS: mid-combat the icon parks at the right edge while more than 10 s
remain, then slides right to left along the ticks, agrees with the number
and the swipe, and reaches the left edge as the swipe ends. FAIL modes to
note: the icon freezes, jumps to one edge, vanishes, or drifts from the
swipe. The log carries `SINKVIEW remaining=secret` at the flip and an
ERROR line if `SetValue`, `SetText` or `SetCooldownFromDurationObject`
rejects the secret. Countdown digits on the swipe need the "Show cooldown
numbers" option; the swipe alone is enough.

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
