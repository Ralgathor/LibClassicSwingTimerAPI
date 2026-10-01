# Upstream report draft — LibClassicSwingTimerAPI

Prepared issue text for
https://github.com/Ralgathor/LibClassicSwingTimerAPI/issues. Not shipped in
the package (`docs/` is a packager ignore); this file is the copy-paste
source and the record of what was reported and when.

Resolution: fixed library-side 2026-10-01 (parked login seed, unreleased — ships with the next LibStub MINOR after beta3's 35) and live-verified on the Forever beta in two login scenarios. See the library CHANGELOG [Unreleased] entry and the 4everSwingTimer repo docs/library-stale-swing-fix-report.md.

Suggested title:

> **A swing in flight at /reload is re-anchored at login, but its landing
> never fires `UNIT_SWING_TIMER_STOP` — consumers keep a stale "active"
> swing**

---

## Environment

- LibClassicSwingTimerAPI `v2.2.0-beta3` (LibStub MINOR 35), embedded in
  the consumer addon.
- Client: WoW: Forever beta, Interface 16001.
- Consumer: 4everSwingTimer 1.0.0-beta2 (repo:
  https://github.com/Ralgathor/4everSwingTimer), which renders bars purely
  from the library's `UNIT_SWING_TIMER_*` events and
  `UnitSwingTimerInfo`.

## Summary

A swing that is in flight when the UI reloads leaves consumers with a swing
that never lands. After login the library hands the consumer swing state for
that hand — either a `UNIT_SWING_TIMER_START` or seeded
`UnitSwingTimerInfo` data surfaced at
`UNIT_SWING_TIMER_INFO_INITIALIZED`; the exact producer is trivial to
confirm library-side, the consumer only observes the resulting "active"
state. The re-anchored swing's expiration then passes and no
`UNIT_SWING_TIMER_STOP` ever fires. The consumer's model stays "swing in
flight" indefinitely, until the next real swing's `START` overwrites it.

Auto-attack does not survive a `/reload`, so a swing reported at login can
never complete — the engine will not fire `PLAYER_SWING` for it.

## Reproduction (consumer-side)

1. Auto-attack a target (any hand; main-hand alone is enough).
2. `/reload` while the swing is in flight.
3. After login, run the consumer's diagnostic dump
   (`/4everswingtimer debug`). The affected hand shows `active=true` with
   the fill at the completed position (computed remaining time zero).
4. Wait: as the re-anchored expiration passes, no
   `UNIT_SWING_TIMER_STOP` arrives. The state persists until the next real
   swing.

Optional trace: the consumer ships an event trace
(`/4everswingtimer trace`) that records `PLAYER_SWING`, `UNIT_COMBAT`, the
player's spellcasts, and all seven `UNIT_SWING_TIMER_*` callbacks into
`SavedVariables` (`FourEverSwingTimerTrace`, written at logout or `/reload`;
read the file from `WTF\Account\...\SavedVariables` after the session).
Since the trace's recording flag resets on load, re-arm it right after the
reload to capture the post-login stream; login-instant events may precede
the re-arm, which is why the exact producer (START vs seeded info) is
easiest to confirm from the library itself.

## Consumer-side evidence

- After a mid-swing `/reload`, `/4everswingtimer debug` reports the hand as
  `active=true` with the swing landed (fill 0.000 remaining, expiration in
  the past).
- No `STOP` follows when the seeded expiration passes; the addon's bar
  keeps `bar.active` until the next real `START`.
- The stale state is visually silent in the common configuration: in drain
  fill mode a completed-but-active bar sits at exactly the parked position.
  It surfaced through behavior keyed on activity — the addon's "while
  swinging" visibility mode keeps the bar shown (empty) instead of hiding
  it, and the addon's effect-test trigger classified the stale bar as a
  live swing and fired on its parked state.

## Expected behavior

One of:

- the library does not surface a swing at login that the engine cannot
  complete (auto-attack is gone after a reload), or
- when a tracked swing's expiration passes without a `PLAYER_SWING`
  landing, the library fires `UNIT_SWING_TIMER_STOP` so consumers'
  state converges to parked.

## Impact

Any consumer that keys visibility, layout or logic on swing activity holds
wrong state after a reload until the next real swing. The state also
crosses a session boundary as a lie: "in flight" with a landed expiration.

## Consumer-side workaround (already shipped, for reference)

4everSwingTimer no longer treats a bar whose expiration has passed as
"in flight", independent of the missing `STOP`. A library-side fix (no
login seed for uncompletable swings, or the missing `STOP`) would remove
the need for consumers to second-guess the event stream.
