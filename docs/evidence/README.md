# Evidence: parry-haste rule on WoW: Forever (build 70124, 2026-09-30)

Raw captures backing the parry-haste rule recorded in
`FOREVER_API_FINDINGS.md` section 8.10, the shipped formula in
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

Align the two files by wall-clock time: the trace `SESSION` markers carry
a wall-clock date plus the `GetTime()` at capture start; refine the offset
by pairing trace `UNIT_COMBAT player PARRY` events with combat-log
`SWING_MISSED ... PARRY` events (destination = player GUID). For the two
join sessions the refined offsets were constant:

- 2.4 s session: trace GetTime + 31075.643 = log wall-clock (parries);
  swing damage lands a further +0.660 s after `PLAYER_SWING`
- 3.4 s session: +31075.654; swing pipeline +0.649 s

The `PLAYER_SWING`-to-damage pipeline delay is absolute (~0.65 s at both
weapon speeds), not weapon-proportional.

## What these captures establish

- The shipped rule, verified at both weapon speeds: no effect before ~30%
  of the swing has elapsed (remaining above ~70% of weapon speed); then
  remaining -= 40% of weapon speed, no floor; a reduction landing in the
  past fires the swing immediately (in the parry's own frame).
- No 20% floor and no 60% cap exist on this engine.
- `UNIT_COMBAT` parry coverage is complete (64/66 on time in the 2.4 s
  join, 2/66 delayed ~0.83 s — not dropped).
- Open question (recorded in the findings, not resolved by these
  captures): ~2-5% of swing cycles land early (at 60% of the swing, or
  0.69-0.91 of it) with no parry event in either channel — the anomaly
  family; not extra swings (PLAYER_SWING and combat-log swing attempts
  are 1:1), not item casts (baseline-checked), not seal procs.

## Caveats

- The combat log is append-mode: it contains BOTH join sessions plus the
  boundary between them; split at the second `COMBAT_LOG_VERSION` header
  (~12:01:55) for per-session analysis.
- `GetTime()` is session-relative; the first trace session (91 anchors,
  12 parries) predates the trace v2 SESSION markers and the spellcast /
  library-update recording.
