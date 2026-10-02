# Classic Era regression pass — 2.2.0-beta4 (2026-10-02)

The 2.2.0 changes that touch every client (the parked `PLAYER_ENTERING_WORLD`
seed from beta4, the `PLAYER_DEAD` reset, the shared parry-haste rule) had
only been verified on WoW: Forever. This pass runs them on a Classic Era
client. It closes the "Known unverified" line on 2.2.0-beta4 and is the last
test gate before 2.2.0 stable.

| | |
|---|---|
| Client | 1.15.9.70003, realm Living Flame (Season of Discovery, Classic Era codebase) |
| Library | 2.2.0-beta4, LibStub MINOR 36, standalone install (no other embedded copy) |
| Characters | Tâlhmor (warrior, tests 1–5), Tälhmor (hunter, death retest and fix check) |
| Lua errors | None (BugSack clean for the whole session) |
| Raw log | [`evidence/SwingTestLog-classic-era-2026-10-02.lua`](evidence/SwingTestLog-classic-era-2026-10-02.lua), verbatim |

## Result

| # | Test | Result |
|---|---|---|
| 1 | Swing cadence on a dummy | ✅ Pass |
| 2 | Parry haste | ✅ Pass (same-frame edge case noted) |
| 3 | Death + resurrection | ✅ Pass, after a fix to the death reset |
| 4 | Login / reload state (beta4 parked seed) | ✅ Pass |
| 5 | Haste rescale (Slice and Dice planned; Flurry used, no rogue available) | ✅ Pass |

## How the pass was run

The harness is a throwaway addon, [`tools/SwingTestLog/`](tools/SwingTestLog/).
It records every library callback plus combat context (own swings, parries,
casts, own auras, auto-attack toggle, combat state, death, equipment) into
`SwingTestLogDB`, one session per login or reload. About 0.5 s after each
`PLAYER_ENTERING_WORLD`, and at `PLAYER_DEAD`, it records each hand's
`UnitSwingTimerInfo` as `PARKED` (expiration == lastSwing), `IN-FLIGHT`
(expiration in the future) or `LANDED`.

To rerun:

1. Copy `tools/SwingTestLog/` into the client's `Interface/AddOns/` and
   enable it next to the library.
2. Before each step, `/stl note TEST n <name>`. `/stl state` dumps the state
   at any time; `/stl echo` mirrors the log to chat.
3. `/reload` or log out to write
   `WTF/Account/<account>/SavedVariables/SwingTestLog.lua`.
4. `luajit tools/analyze-swingtestlog.lua <that file>`. Per session it lists
   each STOP more than 50 ms from the landing the last START/UPDATE predicted,
   restarts before the predicted landing, STOP→START gaps, and every parry and
   death line.

## Detail

### 1. Cadence — pass

109 main-hand landings in the warrior session. Every STOP landed 0.05–0.085 s
before the predicted landing, with no drift: each swing re-anchors. The
analyzer's two −1.549 s outliers are extra attacks: two `HIT`s in the same
frame, where the library restarts the swing at once, and the next landing is
on time from the restart.

### 5. Haste rescale — pass (Flurry instead of Slice and Dice)

Flurry fires an `UPDATE` to speed 1.549 on a 2.014 s weapon, exactly
2.014 / 1.3. Applied mid-swing, the remaining time divides by 1.3 (START
2.014 at 1478.661, Flurry at 1478.822 → `left=1.425`). The same check passed
at a second weapon speed (2.316 → 1.782). The original plan names Slice and
Dice "or any haste aura", so Flurry covers the classic rescale path.

### 2. Parry haste — pass, one edge case

Parries that land mid-swing match the engine:

| Parry at | Swing | Rule | Library `left=` | Actual landing |
|---|---|---|---|---|
| 1518.479 | 1.549 s | 20% floor | 0.310 | +0.311 s |
| 2468.213 | 2.600 s | full 40% cut | 1.339 | +1.339 s |
| 2532.586 | 2.600 s | full 40% cut | 1.076 | +1.078 s |

**Edge case — parry in the same frame as the player's own swing start.**
`lib:ApplyParryHaste` computes `remaining == speed` and returns ("before this
swing started"). The engine is inconsistent on this boundary:

- 1477.454: the engine applied the full cut (landing 1.207 s later =
  2.014 − 0.806) and the library sent no `UPDATE`, so the bar was 0.807 s late.
- 1526.780: the engine did not cut (landing 1.551 s later at speed 1.549).

v2.1.3 cut every parry. It also had a floor bug: it set the expiration to the
absolute value `0.2 * speed`, which ended the swing at once. 2.2 fixes that
bug and skips same-frame parries. With one sample each way, this is
documented rather than changed; more same-frame samples are needed to settle
the engine's ordering.

### 4. Login / reload — pass

Three reloads in mid-fight (each session opens with `COMBAT enter`), one
fresh login and one zone change: every hand read `PARKED`, with time left
≤ 0, and no `START` or `UPDATE` came before auto-attack was toggled back on.
The first swing after re-engaging started cleanly every time.

### 3. Death — pass, after a fix

First run (warrior): the player was not swinging at death (last swing 85 s
earlier), so only the post-resurrection START was exercised.

Retest (hunter, 22:02:30, auto-attacking): one `STOP mainhand` fired at
`PLAYER_DEAD` with 0.54 s left on the swing. The client fires `PLAYER_DEAD`
a second time 0.58 s later; that fired nothing. The first swing after
resurrection started cleanly.

**Bug found:** right after the STOP, `UnitSwingTimerInfo` still reported the
main hand as `IN-FLIGHT, left=0.540`. `lib:PLAYER_DEAD` cancelled the timer
and fired STOP but left the expiration in the future. Event-driven consumers
were unaffected; anything polling the state saw a live swing until the old
landing time passed.

**Fix (Unreleased):** `lib:PLAYER_DEAD` now parks each stopped hand
(`expiration = lastSwing`, the convention of the beta4 login seed) before its
STOP fires.

**Fix check (22:09:42, fixed file installed on the same client):** one STOP
at death and the main hand reads `PARKED` at once (`left=-0.851`, the time
since its last swing); the duplicate `PLAYER_DEAD` stays silent; clean START
after resurrection.

**Fix check on WoW: Forever (22:21:23, client 1.60.1.70170, paladin, fixed
file embedded in 4everSwingTimer):** death 1.115 s into a 2.4 s swing (START
3606.048, death 3607.333); one STOP in the same frame and the main hand reads
`PARKED left=-1.285` at once. Forever fired `PLAYER_DEAD` only once. After
resurrection the first auto-attack swing started cleanly on its
`PLAYER_SWING` anchor. The same log also shows the beta4 seed parked at a
fresh login, a mid-fight reload and two zone changes, and three parry cuts
matching their landings within 2 ms (`left=` 0.351, 0.596, 0.617). Raw log:
[`evidence/SwingTestLog-forever-2026-10-02.lua`](evidence/SwingTestLog-forever-2026-10-02.lua).
The harness runs on both clients; on Forever it logs `PLAYER_SWING` as
`SWING` and `UNIT_COMBAT` parries, since CLEU is refused there.

## Observations, not compared with 2.1.x

These are not blockers. They may be older behavior; none was checked against
v2.1.3.

- **Mount summon out of combat fires a swing.** Casting a mount (1217141 /
  1217142) fires `START mainhand` and a STOP one swing later, with no
  auto-attack. Classic's cast-reset path treats any completed cast as a swing
  reset.
- **Weapon swap starts timers.** Equipping a main-hand weapon (slot 16) fired
  `START mainhand` and `START ranged` without auto-attack.
- **UPDATE on a landed swing.** Attack-speed changes after a swing has landed
  (death dropping buffs, rebuffing) fire an `UPDATE` with time left < 0.
- **Moving hunter.** While moving with a ranged swing pending, the library
  repeats `UPDATE ranged left=0.973` about every 0.5 s (11 s in the log, some
  duplicated in the same frame) until the shot fires or the player stops.
  This looks like the classic Auto Shot hold-while-moving.

## Still open before 2.2.0 stable

- ~~Death fix check on WoW: Forever~~ — passed 2026-10-02 (see test 3).
- Changelog: drop the beta4 "Known unverified" line at release prep, and
  note the same-frame parry edge case.
