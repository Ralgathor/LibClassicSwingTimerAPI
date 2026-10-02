# Evidence: parry-haste rule on WoW: Forever (build 70124, 2026-09-30)

Raw captures backing the parry-haste rule recorded in
`FOREVER_API_FINDINGS.md` section 8.10 (FINAL entry), the shipped formula in
`LibClassicSwingTimerAPI.lua` (`lib:ApplyParryHaste`), and the beta report
in `PARRY_HASTE_BUG_REPORT.md`.

Both files are verbatim copies from the live beta client — no screenshots,
no transcription, no edits.

## Files

### `WoWCombatLog-2026-09-30.txt` (4.2 MB)

The client's own advanced combat log (`/combatlog`), append-mode across the
two join sessions. Format: `COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1`,
full source/destination GUIDs and names. Sessions:

- from ~11:09 — 2.4 s weapon join session (489 PLAYER_SWING anchors,
  66 player parries)
- from ~12:02 — 3.4 s weapon join session (264 anchors, 42 parries)

Player: `Ralgathor-ClassicBetaPvE2-`, GUID `Player-4620-0095BF89`.
Note: `SWING_DAMAGE` double-fires with `SWING_DAMAGE_LANDED` in advanced
logs — count `SWING_DAMAGE_LANDED` + `SWING_MISSED` (source = player) for
swing attempts, dedupe at 30 ms.

### `trace-2026-09-30.lua` (944 KB)

The `FourEverSwingTimerTrace` table extracted from
`WTF/Account/<account>/SavedVariables/4everSwingTimer.lua` — recorded by
the test rig's `/4everswingtimer trace` command (4everSwingTimer addon).
19,564 events across 4 SESSION-marked capture sessions (the first verbatim
session predates the SESSION markers and is included without one).
Line formats:

- `PLAYER_SWING <GetTime> <swingDuration> <swingType>` (0=MainHand)
- `UNIT_COMBAT <GetTime> <unitTarget> <action> <flagText> <amount> <school>`
- `UNIT_SPELLCAST_SUCCEEDED <GetTime> player <castGUID> <spellID>`
- `LIB_UNIT_SWING_TIMER_UPDATE <GetTime> player <speed> <expiry> mainhand`
- `SESSION <GetTime> <version> <buildNumber> <wall-clock date>`

## Files: haste-application captures (2026-09-30: 15:41 SnD, 15:55 SotC, 16:47 Redoubt proxy)

Backs `HASTE_APPLICATION_FINDINGS.md`. Three sessions in one client run:

- SnD session (15:41): rogue `Rolhgar` (GUID `Player-4620-011E60D2`),
  dual-wield (mainhand 1.683, offhand 1.782), Slice and Dice rank 1 (5171,
  +20% measured: 1.683→1.403 / 1.782→1.485).
- SotC control session (15:55): paladin `Ralgathor` (GUID
  `Player-4620-0095BF89`), one 3.4 two-hander, Seal of the Crusader rank 2
  (20162, 3.400→2.428, x1.4003), removed mid-swing by casting Seal of
  Righteousness (seals replace each other).
- Redoubt proxy session (16:47): the paladin, 1 point in Redoubt, fighting
  attacking melee mobs — answers whether a talent-proc aura fires
  `UNIT_SPELLCAST_SUCCEEDED` (it does not; aura spell ID 20128).

Both files are verbatim copies from the live beta client.

### `4everSwingTimer-2026-09-30.lua` (1.0 MB)

The full accumulated `FourEverSwingTimerTrace` SavedVariables table at the
end of the SotC session (all earlier sessions included; the SnD session is
the segment after the `SESSION 4318.226 ... 15:41:29` marker, the SotC
session after `SESSION 5170.413 ... 15:55:41` — both segments' GetTime
ranges numerically overlap the file's first paladin session, so analysis
must select by file position, not by GetTime value). The SnD session records
121 mainhand and 106 offhand PLAYER_SWING anchors, 19 SnD and 20 Sinister
Strike `UNIT_SPELLCAST_SUCCEEDED` casts, and 17 offhand combat-start
`LIB_UNIT_SWING_TIMER_UPDATE` anchors (zero mainhand mid-swing updates —
the rescale gate held throughout). The SotC session records 13 mainhand
anchors, 4 SotC casts and 3 seal-replacement removals in swing windows.

### `WoWCombatLog-093026_154137.txt` (300 KB)

The client's advanced combat log, append-mode across BOTH sessions (SnD
first, SotC after the 15:55 boundary — split there for per-session analysis).
Player-attributed swing attempts: `SWING_DAMAGE_LANDED` + `SWING_MISSED`
(source = player GUID). SnD session: 157 landed + 70 missed = 227 = the
trace's 121 + 106 anchors. SotC session: 12 landed + 1 missed = 13 = the
trace's 13 anchors, with one continuous 37–815 damage profile across both
speed windows (single weapon — the 2.428 anchors are the SotC-hasted value,
not a second weapon). SnD appears as `SPELL_AURA_APPLIED`/`REMOVED` 5171
(15 each — recasts replace the aura), with `SPELL_AURA_APPLIED` landing
4 ms after the matching `SPELL_CAST_SUCCESS` in the same channel; the SotC
timeline shows each `SPELL_AURA_REMOVED` 20162 at the same instant as the
replacing SoR `SPELL_AURA_APPLIED`. Note for parsing: unit names contain
spaces inside quotes ("Ornery Galestrider"), so whitespace-based field
splitting corrupts combat-log lines — split on commas only.

## How to reproduce the join

**The decisive analysis needs no join at all**: read swings AND parries from
the combat log alone (player swing attempts as cycle anchors, parries as
`SWING_MISSED ... PARRY` with destination = player GUID). That single-file
read is what settled the rule — see below.

To align the trace with the log, use the trace `SESSION` markers (wall-clock
date plus the `GetTime()` at capture start) and refine by pairing trace
`UNIT_COMBAT player PARRY` events with combat-log `SWING_MISSED ... PARRY`
events (destination = player GUID). Caveat, learned the hard way: the
parry-fitted offset is NOT a pure clock offset — it absorbs the UNIT_COMBAT
parry dispatch lag (0.10–0.30 s behind the log records, two clusters), so a
single fitted constant is only good to ±0.1 s and the two event streams must
not be mixed when measuring engine rules. Fitted constants for reference:
2.4 s session ≈ 31075.6–31075.7, 3.4 s session ≈ 31075.6 (log wall-clock
minus trace GetTime).

## What these captures establish

- **The engine implements the documented classic parry-haste rule, exactly**
  (combat-log-only read: swings and parries from the same file, 96 of 98
  single-parry cycles fit): a parry with more than 60% of the swing
  remaining cuts the remainder by 40% of weapon speed (landings match to
  milliseconds); between 20% and 60% the swing is reduced to 20% remaining —
  the floor measured at 0.484 s on the 2.4 s weapon and 0.685 s on the 3.4 s
  weapon (20% at both speeds, ±20 ms; weapon-proportional, which no dispatch
  latency can be); under 20% remaining, no effect.
- **PLAYER_SWING is a pre-resolution event**: the swing's own UNIT_COMBAT
  damage event arrives a median 0.451 s (2.4 s weapon) / 0.486 s (3.4 s)
  after PLAYER_SWING — same-channel, weapon-independent; the combat log
  records the attempt a further ~0.13–0.23 s later (~0.65 s total).
- **UNIT_COMBAT parry dispatch lags its combat-log record** by 0.10 and
  0.25–0.30 s (two clusters). Relative to the PLAYER_SWING-anchored timer, a
  UNIT_COMBAT parry stamp therefore sits ~0.55–0.72 s after the engine's
  parry instant. This single skew produced the earlier (now retracted)
  "no 20% floor / early parries discarded" readings, and it resolves the
  former anomaly family: floor-band parries whose UNIT_COMBAT dispatch
  arrives after the already-hasted PLAYER_SWING land in the next cycle, so
  the hasted cycle shows "no parry event" — ~2–5% of trace cycles, but only
  ~2 of 688 no-parry cycles are off cadence in the combat log.
- `UNIT_COMBAT` parry coverage is complete (the join pairs every trace
  parry with a log record; the earlier "2/66 delayed ~0.83 s" reading was
  the dispatch lag seen through a tight join window).

## What the haste captures establish (see HASTE_APPLICATION_FINDINGS.md)

- **Dynamic-family haste applies mid-swing on Forever**: SnD rescales the
  in-flight swing's remaining time proportionally (13 clean gain windows at
  25–82% offsets; the snapshot and progress-preserving models are rejected
  everywhere). Both hands are affected.
- **SnD expiry lengthens dynamically too** (four of five expiry windows land
  between the hasted and base speeds; snapshot-on-removal rejected). One
  window overshoots the new full speed by +0.085 s — open anomaly.
- **Snapshot-family haste does NOT**: the SotC control shows M0 in both
  directions (4 gain windows at 19–59% and 3 seal-replacement removal
  windows at 33–55%, all residuals within ±0.033; M2 off by 0.39–0.79 s).
  The in-flight swing completes on the speed it started with; the new speed
  applies from the next swing.
- **Player UNIT_SPELLCAST_SUCCEEDED spell IDs stay plain mid-combat** (all
  19 SnD casts and all SotC/SoR/Judgement casts recorded readable in
  open-world fighting).
- **Talent-proc auras do NOT fire `UNIT_SPELLCAST_SUCCEEDED`** (Redoubt
  proxy session): four Redoubt applications (spell 20128 — two APPLIED,
  two REFRESH on re-proc, with REMOVED_DOSE per block consumed) produced
  no SUCCEEDED event on any spell ID at the proc instants, in the trace or
  the combat log; the spell appears only in AURA events. The procs follow
  ordinary non-critical incoming WOUND events — the rewritten Forever
  trigger (10% per damaging melee hit) verified live. Consequence: Flurry
  (same mechanism class) cannot ride the library's cast-success trigger.
- The library's `not isForever` rescale gate held throughout both sessions
  (zero mainhand mid-swing UPDATEs) — correct for SotC by design, but it
  means the bar lagged the engine on every SnD cast, which is the reported
  anomaly.

## Caveats

- The combat log is append-mode: it contains BOTH join sessions plus the
  boundary between them; split at the second `COMBAT_LOG_VERSION` header
  (~12:01:55) for per-session analysis.
- `GetTime()` is session-relative; the first trace session (91 anchors,
  12 parries) predates the trace v2 SESSION markers and the spellcast /
  library-update recording.
- The SnD trace file is the accumulated SavedVariables across ALL sessions;
  the rogue and SotC segments must be selected by file position (after the
  `SESSION 4318.226` and `SESSION 5170.413` lines respectively), because
  their GetTime values numerically overlap the first paladin session's.

---

# Evidence: Classic Era regression pass (2026-10-02)

### `SwingTestLog-classic-era-2026-10-02.lua` (87 KB)

Verbatim `SwingTestLogDB` SavedVariables from the Classic Era client
(1.15.9.70003, Living Flame / Season of Discovery), library 2.2.0-beta4
(MINOR 36): 10 login/reload sessions, warrior then hunter. Recorded by the
harness in `../tools/SwingTestLog/`; summarize it with
`luajit ../tools/analyze-swingtestlog.lua SwingTestLog-classic-era-2026-10-02.lua`.
Line format: `<clock> <GetTime> <KIND> <fields>`, with `STATE` lines giving
each hand's `UnitSwingTimerInfo` as PARKED / IN-FLIGHT / LANDED. Sessions 1–9
run the beta4 file; session 10 (`NOTE DEATH fix check`) runs the
`PLAYER_DEAD` parking fix. Results and analysis:
`../CLASSIC_ERA_REGRESSION_2026-10-02.md`.

### `SwingTestLog-forever-2026-10-02.lua` (11 KB)

Same harness on the WoW: Forever beta (client 1.60.1.70170, paladin),
library 2.2.0-beta4 plus the `PLAYER_DEAD` parking fix, embedded in
4everSwingTimer. Three sessions; the death check is under
`NOTE DEATH fix forever` in session 2. On Forever the harness logs
`PLAYER_SWING` as `SWING` and parries from `UNIT_COMBAT` (CLEU is refused).
