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

## Caveats

- The combat log is append-mode: it contains BOTH join sessions plus the
  boundary between them; split at the second `COMBAT_LOG_VERSION` header
  (~12:01:55) for per-session analysis.
- `GetTime()` is session-relative; the first trace session (91 anchors,
  12 parries) predates the trace v2 SESSION markers and the spellcast /
  library-update recording.
