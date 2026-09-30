# Bug report draft: event-pipeline timing on the WoW: Forever beta (PLAYER_SWING precedes the attack; UNIT_COMBAT parries lag)

Status: draft, 2026-09-30, second edition. **Supersedes the first draft in
full** — that draft claimed two parry-haste deviations from classic (early
parries discarded; no 20% floor). Both were measurement artifacts: the
parries were read from `UNIT_COMBAT` stamps and the swings from
`PLAYER_SWING` anchors — two event streams whose dispatch latencies differ
by ~0.55–0.72 s on this client. Reading swings and parries from the same
file — the client's own `/combatlog`, the measurement method the classic
wiki itself used — shows the engine implements the documented classic rule
exactly, floor included. What actually deviates is the event pipeline, and
that is what this report asks about.

Filed in two forms: the in-game beta reporter (character-limited) and the
full forum / WoW UI Discord version below.

## In-game short form (243 characters — the reporter caps at 255)

```
b70124 timing: PLAYER_SWING fires ~0.45s before the swing resolves (constant across weapon speeds); UNIT_COMBAT PARRY dispatch lags its log record 0.10-0.30s, at times past the hasted swing. Parry haste matches classic. Docs? WoWUIDev Discord.
```

## Full version (forum / dev thread)

Title: PLAYER_SWING fires ~0.45 s before the swing resolves and UNIT_COMBAT
PARRY dispatch lags its combat-log record by 0.10–0.30 s (WoW: Forever
beta) — parry haste itself matches the classic rule

Build: WoW: Forever beta, 1.60.1 (build 70124), Interface 16001.

Method: the client's own advanced combat log (`/combatlog`) plus verbatim
SavedVariables event traces (`PLAYER_SWING` + `UNIT_COMBAT`, millisecond
timestamps, written to disk at logout) across two join sessions and two
weapon speeds (2.4 s and 3.4 s): 753 player swing attempts and 108 player
parries, every one timestamped in both channels.

Finding 1 — parry haste matches classic, exactly. With swings and parries
both read from the combat log (one file, no cross-file clock join, no free
parameters), 96 of 98 single-parry cycles fit the documented rule: more than
60% of the swing remaining → reduce the remainder by 40% of weapon speed
(landings match to milliseconds); between 20% and 60% → reduce to 20%
remaining (the floor lands at 0.484 s on the 2.4 s weapon and 0.685 s on
the 3.4 s weapon — 20% at both speeds, within ±20 ms); under 20% remaining
→ no effect. A dispatch artifact cannot imitate this: the floor scales with
weapon speed and nothing else in the pipeline does.

Finding 2 — PLAYER_SWING is a pre-resolution event. Same-channel
measurement (trace only): the swing's own `UNIT_COMBAT` damage event
arrives a median 0.451 s (2.4 s weapon) and 0.486 s (3.4 s weapon) after
`PLAYER_SWING` — roughly constant, not weapon-proportional; the combat log
records the attempt a further ~0.13–0.23 s later. Blizzard's own bar
(`Blizzard_SwingTimer.lua`) anchors on `PLAYER_SWING` with no lead
compensation (`swingEndTime = GetTime() + duration`), and the generated API
documentation declares the event `SynchronousEvent = true` with no
description of what it marks.

Finding 3 — UNIT_COMBAT parry dispatch lags its combat-log record. Two
clusters: 0.10 and 0.25–0.30 s behind the outgoing-hit dispatch relative to
the log records. Consequence for addon authors: on a 2.4 s weapon, a
floor-band parry's `UNIT_COMBAT` event can arrive after the already-hasted
`PLAYER_SWING`. In the SavedVariables traces this produced a family of
~2–5% of swing cycles that appeared to land early with no parry event at
all; in the combat log only ~2 of 688 no-parry cycles are off cadence, and
those cycles do contain the parry record.

Ask: (1) document what `PLAYER_SWING` is supposed to mark — Blizzard's own
bar treats it as the swing instant, but the attack resolves ~0.45 s later
at every weapon speed tested; (2) say whether the `UNIT_COMBAT` dispatch
latency is intended, and whether the event's payload will ever be populated
(`GetCurrentCombatTextEventInfo()` returns nil on this build). Addon
authors combining `PLAYER_SWING` with combat events for mid-swing
adjustments currently need an undocumented ~0.65 s correction (0.45 s
PLAYER_SWING lead + 0.10–0.30 s parry dispatch lag).

Evidence: the verbatim captures and the join recipe are in `docs/evidence/`
in the library repository (LibClassicSwingTimerAPI).
