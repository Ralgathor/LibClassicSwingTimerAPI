# Bug report draft: C_SwingTimer range checking non-functional (WoW: Forever beta)

Status: draft, 2026-09-28, from the probe results in FOREVER_API_FINDINGS.md
section 4.4 (event) and the 2026-09-28 query probe (query nil with a target in
melee range AND out of range, after EnableRangeCheck(0, true)). Companion to the
blocked "Range state" entry in IMPROVEMENT_PLAN.md section 4.

Filed in two forms: the in-game bug reporter (character-limited) and the full
forum / WoW UI Discord version below.

## In-game short form (fits the reporter's limit)

```
SWING TIMER RANGE APIs DEAD (build 70009): C_SwingTimer.IsTargetWithinSwingRange
returns nil with a target in melee range AND out of range, after
EnableRangeCheck(0,true). PLAYER_SWING_RANGE_UPDATE fires only once, at the
EnableRangeCheck call (payload 0,false,false), never again on range changes.
The native swing timer's out-of-range dimming cannot function either.
PLAYER_SWING itself works fine, so only the range subsystem seems unwired.
```

## Full version (forum / dev thread)

Title: C_SwingTimer range checking is non-functional on the Forever beta
(IsTargetWithinSwingRange always nil; PLAYER_SWING_RANGE_UPDATE never fires)

Build: WoW: Forever beta, 1.6.0.1 (build 70009, Sep 23 2026), Interface 16001.
Tested from addon (tainted) context via /run macros - identical results.

Summary

Both channels of the C_SwingTimer range subsystem are dead on this build:
the event never fires beyond a single initial push, and the query returns
nil regardless of range state. Range awareness for swing timers is
therefore impossible for addons, and the built-in swing timer's own
out-of-range presentation cannot function either.

Repro 1 - the event

1. Enable range checking:  /run C_SwingTimer.EnableRangeCheck(0, true)
2. Register PLAYER_SWING_RANGE_UPDATE and print its payload.
Expected: fires on range transitions with (swingType, isInRange, checksRange).
Actual: fires exactly ONCE, at the EnableRangeCheck call, with the initial
state (0, false, false), then never again. Walking in and out of melee
range of the target produces no events. (Probed 2026-09-24 and unchanged
2026-09-28.)

Repro 2 - the query

1. With a mob targeted and standing IN melee range, auto-attacking:

   /run local q=C_SwingTimer.IsTargetWithinSwingRange print("exists:",
   type(q)) C_SwingTimer.EnableRangeCheck(0, true) print("MH:",
   C_SwingTimer.IsTargetWithinSwingRange(0))

2. Repeat while standing out of melee range, target still selected.
Expected: true in range, false (or a documented value) out of range.
Actual: nil in BOTH states, in both runs (2026-09-28). Previously also
confirmed nil with no target.

Contrast

PLAYER_SWING works reliably (one event per swing attempt, plain-number
payload, readable in restricted content), so the swing event wiring is
fine - the range subsystem specifically appears unwired after the initial
EnableRangeCheck push.

Impact

Blizzard_SwingTimer implements its out-of-range presentation through this
subsystem (PLAYER_SWING_RANGE_UPDATE, with IsTargetWithinSwingRange as the
query fallback on target change): with the event dead and the query nil,
the built-in swing timer can never show out-of-range state on this build.
Any addon implementation is equally blocked.

Ask

Is the range subsystem intended to work in the beta? If
PLAYER_SWING_RANGE_UPDATE is the intended channel, its wiring looks missing
after the EnableRangeCheck call. If the query is the intended fallback, it
needs to return range state instead of nil. Either fix unblocks the built-in
UI and addons.
