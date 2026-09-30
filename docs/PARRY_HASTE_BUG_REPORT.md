# Bug report draft: parry haste deviates from the classic rule (WoW: Forever beta)

Status: draft, 2026-09-30, superseding the earlier short form (which said
~20% and asked about a swapped comparison — both corrected by later data:
the clean no-effect bracket reaches ~30% elapsed, and the swapped-comparison
hypothesis was rejected when a deep parry fired the swing early instead of
delaying it). From the verbatim SavedVariables event traces in
FOREVER_API_FINDINGS.md section 8.10: three sessions, build 70124, 440+
swing anchors, 37 timestamped player parries, measured with a trace addon
recording PLAYER_SWING and UNIT_COMBAT to disk — no screenshots, no
transcription.

Filed in two forms: the in-game beta reporter (character-limited) and the
full forum / WoW UI Discord version below.

## In-game short form (249 characters — the reporter caps at 255)

```
Parry haste bug? Measured on b70124: parries early in a swing (<30% elapsed) never haste (30+ verbatim samples; classic gives the full cut) and deep parries fire the swing in the same frame (no 20% floor). Intended Classic+ change? WoWUIDev Discord.
```

## Full version (forum / dev thread)

Title: Parry haste deviates from the documented classic rule on the Forever
beta (early parries discarded; late parries fire the swing instantly)

Build: WoW: Forever beta, 1.60.1 (build 70124), Interface 16001.

Method: SavedVariables event traces (PLAYER_SWING + UNIT_COMBAT,
millisecond timestamps, written to disk at logout) across three sessions,
440+ swing anchors, 37 timestamped player parries, mostly one or two mobs.

The documented classic parry-haste rule: a successful parry reduces the
remaining swing timer by 40% of the defender's weapon speed (sources
disagree only on the tail: capped at 20% of the swing remaining, or no
effect when the cut would drop below 20%).

Observed on this build — two deviations:

1. Early parries do nothing. A parry in the first ~30% of the swing leaves
the cadence untouched (30+ clean samples; no effect at 0.718 s elapsed on a
2.4 s weapon, effect confirmed from 0.934 s). The documented rule gives
these parries the FULL cut — a parry right after a swing should land the
next swing at 60% of the swing time.

2. No 20% floor — late parries fire the swing instantly. A parry with
0.231 s remaining on a 2.4 s weapon fired the swing in the parry's own frame
(the swing event and the parry combat-feedback event share the same
timestamp). Both documented tail readings are contradicted: nothing caps
the remaining swing at 20%, and the effect certainly does not stop.

The middle band matches classic exactly: remaining swing minus 40% of
weapon speed predicts the landing to within 30 ms across seven measured
parries (e.g. 1.014 s remaining -> swing 0.050 s later).

Ask: intended Classic+ tuning, or a bug? If intended, the deviation from
every documented version of the mechanic is worth calling out in the beta
notes; if a bug, early parries should presumably receive the documented
full cut and the tail should respect the 20% floor.

Related observation (one line): separately, ~2–5% of swing cycles in the
traces land early (at 60% of the swing time, or 0.69–0.86 of it) with no
parry event at all — possibly the same mechanism dropping events, possibly
unrelated; happy to share the trace data.
