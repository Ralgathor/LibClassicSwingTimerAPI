# Transition-Parity Implementation Plan — UNIT_ATTACK_SPEED as the unified haste trigger

Status: plan, 2026-10-05, revision 2 (review pass: the player gate, the Rule 4
cast window, the expected-expiry gate on Rule 3, the back-dated un-haste, and
the deferral of Phases B/C). Design and evidence: `HASTE_APPLICATION_FINDINGS.md`
section 7.1 item 4 (all rogue-side pillars proven on build 70205). Phase A is
the implementation contract and is the only phase that ships code. Phases B
and C are design notes: no tables, registrations or fields land for them until
their captures do (AGENTS.md rule 2 — no speculative surface). Pending
captures: warrior (Flurry charge-0 fire) and hunter (Deadly Aspects gain/fade
pair) — `M1_SESSION_SCRIPT.md` B6.

## 1. Goal

On WoW: Forever, kill the one-swing expiry lag of the dynamic-haste family
(today: Slice and Dice). `UNIT_ATTACK_SPEED` fires at every attack-speed
transition (proven: application simultaneous with the cast, 5 cases; fade
-24 to +412 ms after the combo-point-formula expiry, 4 cases including one
mid-combat with a secret payload; refresh fires nothing, 2 cases; double-fire
per change — dedupe required). The event carries no value and no hand, and it
is ANONYMOUS: any attack-speed source fires it (Blade Flurry, Berserking,
haste trinkets and potions, mob attack-speed debuffs, weapon swaps, seals,
forms). So a fire alone never identifies an SnD fade; the fade is attributed
by TIMING against the expected expiry computed at the cast (combo points read
plain at the SUCCEEDED instant — proven, `CP at-snd 1.000/2.000 sec=false`;
duration 9+3(n-1) — engine-verified). Every decision stays settled by the
next plain PLAYER_SWING anchor.

## 2. Rules (the handler contract, evaluated in this order)

| # | UNIT_ATTACK_SPEED fire (player unit only) with... | Action |
|---|---|---|
| 0 | a previous fire < 50 ms ago | none — the double-fire duplicate |
| 1 | a dynamic-table SUCCEEDED < 50 ms ago | none — the SUCCEEDED path already applied the factor (or correctly skipped a refresh) |
| 4 | any other player SUCCEEDED < 50 ms ago, or an equipment change < 150 ms ago | none — snapshot family (M0): the in-flight swing completes on its old speed; the next anchor re-anchors (existing mechanism) |
| 3 | `dynamicHasteActive` set AND the fire inside the expected-expiry window `[E - 0.25, E + 0.75]` | UN-HASTE, back-dated to `min(now, E)`; clear the flag — this kills the one-swing lag |
| 5 | anything else | none — the next anchor settles any untracked transition (today's behavior) |

Rule 2 (deterministic procs, Flurry) and the Phase C replacement of Rule 5
are deferred; see sections 6 and 7.

Design notes on the windows:

- Rule 1 and the cast half of Rule 4 use 50 ms, not 150 ms: every captured
  application fire is simultaneous with its cast (0 ms, same timestamp). A
  tight window matters because rogues cast on every GCD — a wide "any cast"
  window would swallow a real fade fire whenever an unrelated ability landed
  near it. A swallowed fade falls back to the anchor clear (today's
  behavior), never to a wrong rescale.
- The equipment half of Rule 4 keeps 150 ms: the ordering of
  PLAYER_EQUIPMENT_CHANGED vs the fire is uncaptured (checklist item 6).
- The Rule 3 window: lower bound -0.25 s covers the earliest fire (-24 ms);
  upper bound +0.75 s covers the latest (+412 ms) with margin. The one +1.96 s
  outlier was an out-of-combat fade across a reload boundary and is
  deliberately outside — it falls back to the anchor clear.
- An unrelated speed transition that lands inside the window (e.g. a Blade
  Flurry fade within ~1 s of the SnD expiry) is misattributed; the error is
  bounded to one swing, self-corrected by the next anchor, and the flag clear
  is near-correct anyway because SnD fades at E.

The blanket Layer-1 stale-mark is REJECTED (M0 — snapshot in-flight expiries
are not stale) and Phase A does not mark unexplained fires either.

## 3. Current code map (v2.2.0, MINOR 37)

- `lib:UNIT_ATTACK_SPEED(_, unitGUID)` — line ~659. The classic proportional
  rescale, per hand, each gated `and not isForever`; reads run through
  `ResolveSecret`. Registered for "player" and "target" at line ~1072. The
  `skipNextAttackSpeedUpdate` block is set only from CLEU (refused on
  Forever), so it is dead on Forever; the synthetic call from
  `Unit:SwingEnd` (druid/paladin) is therefore unreachable there too.
- `unit.isPlayer` — set ONLY on the target (`PLAYER_TARGET_CHANGED`, line
  ~391): it means "the target is a player character" and is nil on
  `self.player`. It must NOT be used to identify the player unit.
- `lib:ApplyDynamicHaste(unit, factor)` — line ~495. Per-hand progress-
  preserving shortening: `speed / factor`, `expiry = now + remaining /
  factor`, 50 ms young-swing guard, cancels and re-arms the hand's C_Timer,
  fires `UNIT_SWING_TIMER_UPDATE`.
- SUCCEEDED handler dynamic branch — line ~842: `if unit.dynamicHasteActive
  ~= spell then unit.dynamicHasteActive = spell; ApplyDynamicHaste end`.
- PLAYER_SWING anchor handler — lines ~619-630: an anchor speed above
  `cachedSpeed * 1.02` clears `dynamicHasteActive`. KEEP as the settler and
  the fallback for every fire Phase A declines.
- `lib:PLAYER_EQUIPMENT_CHANGED` — line ~950: slots 16/17/18 restart the hands.
- `Unit:ResetTransientState` — line ~155 (called by PLAYER_ENTERING_WORLD and
  PLAYER_TARGET_CHANGED) and `lib:PLAYER_DEAD` — line ~984: neither clears
  `dynamicHasteActive` today.
- `dynamic_haste_spells` — line ~93; on Forever holds SnD rank 1
  (5171 = 1.2), set at line ~1162.
- Upvalue localization block — lines ~13-15.

## 4. Phase A — implement now, Forever-gated

A1. Unit state fields (prototype defaults in the `Unit` table, nil):
    `atkSpeedLastFire`, `lastDynamicCast`, `lastCast`, `lastEquipChange`,
    `dynamicHasteFactor`, `dynamicHasteExpiry`.
    Invariant: `dynamicHasteFactor` and `dynamicHasteExpiry` are written
    together with `dynamicHasteActive` and only read while it is set, so the
    anchor clear (A7) needs no change.

A2. Duration table, next to `dynamic_haste_spells` (Forever block, line
    ~1162):
    ```
    local dynamic_haste_duration = {}   -- declared with the other tables
    dynamic_haste_duration[5171] = function(cp) return 9 + 3 * (cp - 1) end
    ```
    Localize `GetComboPoints` in the upvalue block (convention).

A3. SUCCEEDED handler (player unit, Forever):
    - Set `unit.lastCast = now` for every SUCCEEDED (the Rule 4 cast window).
      Place it so the auto-attack toggle (6603/6803) is EXCLUDED — the toggle
      changes no speed and must not swallow a fade.
    - Dynamic branch, rewritten:
      ```
      if isForever and spell and dynamic_haste_spells[spell] then
          unit.lastDynamicCast = now
          -- expected expiry from the at-cast combo points (plain, proven);
          -- secret/unreadable -> nil -> Rule 3 disabled for this application
          local cp = ResolveSecret(GetComboPoints("player", "target"), nil)
          local duration = dynamic_haste_duration[spell]
          local expiry = nil
          if duration and type(cp) == "number" and cp >= 1 then
              expiry = now + duration(cp)
          end
          if unit.dynamicHasteActive ~= spell then
              unit.dynamicHasteActive = spell
              unit.dynamicHasteFactor = dynamic_haste_spells[spell]
              unit.dynamicHasteExpiry = expiry
              self:ApplyDynamicHaste(unit, unit.dynamicHasteFactor)
          else
              -- refresh: no rescale (engine-verified); the recast REPLACES
              -- the duration (verified: fades matched the recast's 9 s)
              unit.dynamicHasteExpiry = expiry
          end
      end
      ```
    The refresh branch updating `dynamicHasteExpiry` is what makes a recast
    at expiry safe: the late fade fire of the OLD aura (+0.3-0.4 s) is then
    outside the NEW window and is ignored, and the library's swing stays
    hasted — matching the engine, which re-applied the aura.

A4. `lib:PLAYER_EQUIPMENT_CHANGED`: as the FIRST statement, outside the
    16/17/18 slot check (any slot can change speed, e.g. a glove haste
    enchant): `if isForever then self.player.lastEquipChange = GetTime() end`.

A5. New `function lib:RemoveDynamicHaste(unit, fadeTime)` — the inverse of
    ApplyDynamicHaste, per hand (main/off; ranged excluded until a dynamic
    ranged spell is verified), back-dated to the fade instant:
    ```
    local now = GetTime()
    local factor = unit.dynamicHasteFactor
    per hand, when speed > 0, expiry > now, and lastSwing < fadeTime - 0.05:
        cancel the hand's timer
        speed  = speed * factor
        expiry = fadeTime + (expiry - fadeTime) * factor
        fire UNIT_SWING_TIMER_UPDATE; re-arm the C_Timer (expiry - now)
    after both hands: unit.dynamicHasteActive = nil
    ```
    - `fadeTime = min(now, E)`: the aura edge lands at E (0/+49/+2 ms
      measured) while the fire trails it by up to ~0.4 s; scaling from `now`
      would leave a ~(lag x (factor-1)) error (60-80 ms at +412 ms). The
      back-date mirrors `FOREVER_PARRY_EVENT_SKEW`.
    - `lastSwing < fadeTime - 0.05` replaces the plain 50 ms young-swing
      guard: a hand anchored after the fade already carries the unhasted
      payload (and that anchor normally cleared the flag first).
    - The flag is cleared even if no hand qualified (no stuck flag).

A6. The Forever branch in `lib:UNIT_ATTACK_SPEED`, immediately after
    `local now = GetTime()` (before the skip block):
    ```
    if isForever and unit == self.player then
        -- Rule 0: dedupe the double-fire (proven: two identical fires per change)
        if unit.atkSpeedLastFire and now - unit.atkSpeedLastFire < 0.05 then
            unit.atkSpeedLastFire = now
            return
        end
        unit.atkSpeedLastFire = now
        -- Rule 1: the dynamic cast already applied the factor / skipped a refresh
        if unit.lastDynamicCast and now - unit.lastDynamicCast < 0.05 then
            return
        end
        -- Rule 4: snapshot triggers (M0): no action, the next anchor re-anchors
        if (unit.lastCast and now - unit.lastCast < 0.05)
            or (unit.lastEquipChange and now - unit.lastEquipChange < 0.15) then
            return
        end
        -- Rule 3: the tracked source's fade, attributed by expected expiry
        local expiry = unit.dynamicHasteExpiry
        if unit.dynamicHasteActive and expiry
            and now >= expiry - 0.25 and now <= expiry + 0.75 then
            self:RemoveDynamicHaste(unit, math.min(now, expiry))
        end
        -- Rule 5: no action; the next anchor settles
        return
    end
    ```
    The target unit is unchanged: on Forever its classic path stays inert
    (`not isForever` gates). The classic path below is untouched.

A7. Anchor handler: no change. The `dynamicHasteActive` clear stays as the
    settler and the fallback for every declined fire (no CP read, fire
    outside the window, fire swallowed by Rule 4, Improved SnD — see A10).

A8. Reset paths: clear `dynamicHasteActive` in `Unit:ResetTransientState`
    (loading screens) and in `lib:PLAYER_DEAD` (the aura drops on death; its
    fade fire is outside the window, so without this the flag stays set and
    the first SnD cast after the resurrection is mistaken for a refresh).
    These two lines run on every flavor, but the flag is only ever set on
    Forever, so classic behavior is unchanged.

A9. Dispatch-order notes:
    - Application: SUCCEEDED is dispatched before the fire (CAST logged
      before ATKSPEED at the same timestamp). If the order flipped, the fire
      would find no new `lastDynamicCast` and, for a fresh application, the
      flag not yet set -> Rule 5 no-op, then SUCCEEDED applies: harmless.
    - Early removal (cancel, death handled by A8): the fire is outside the
      window -> ignored; the next anchor clears the flag (today's behavior).
    - Weapon swap with SnD up: the swap fire is Rule 4 (if the ordering
      holds, checklist 6) or outside the window; the flag survives, which is
      correct. If the anchor expiry-clear misfires on the new base, tighten
      the clear's cache update there (pre-existing exposure, unchanged).

A10. OPEN DECISION — Improved Slice and Dice. The 9+3(n-1) function is
     verified untalented. The classic talent lengthens the duration
     (+15/30/45%); its Forever value and talent-tree position are
     unverified. Default (recommended): ship the untalented formula only.
     A talented rogue's fade fire then lands after the window, is ignored,
     and falls back to the anchor clear — no regression, just no gain for
     talented rogues until a capture verifies the multiplier and its
     out-of-combat talent read. Do not widen the window to cover it: a
     window several seconds wide multiplies misattribution.

A11. Parry interplay: ApplyParryHaste shortens remaining; RemoveDynamicHaste
     lengthens it — both are remaining-time adjustments and compose
     (checklist 7).

## 5. Classic flavors

Zero behavior change: every new branch is Forever-gated, the classic
UNIT_ATTACK_SPEED path is untouched, the A8 clears touch a field only Forever
sets, and `luac -p` (or `luajit -bl`) must stay clean.

## 6. Phase B — deterministic procs (Flurry): DEFERRED, no code until the warrior capture

Prerequisites the capture and design must settle before any code lands:

- Engine rule on Forever: every crit applies/refreshes; both hands;
  refresh-on-crit; per-rank factor; charge-0 fade fires the event.
- Crit/fire ordering: UNIT_COMBAT trails the engine by 0.10-0.30 s (the
  parry-skew finding), so the fire most likely arrives BEFORE the crit.
  A "recent crit" window at fire time cannot work; the design needs a
  pending fire that a crit arriving within ~0.35 s resolves.
- Crit attribution: UNIT_COMBAT on target tokens also reports other
  players' and pets' crits on that target, once per token naming it. Group
  play would generate false Flurry applications; the capture must show a
  filter that isolates the player's own crits, or Phase B is not viable.
- Factor bookkeeping: Flurry is not in `dynamic_haste_spells`; Rule 3 uses
  `dynamicHasteFactor` (A1), which already generalizes. Flurry's fade is
  swing-count driven, so its Rule 3 attribution is the third hasted swing
  after the last crit, not a timed window.

## 7. Phase C — probabilistic procs (Deadly Aspects): DEFERRED, no code until the hunter capture

Prerequisites:

- ID, factor by talent rank, duration, and the fire pair ~12 s apart.
- Parity is corrupted by any unexplained transition (debuffs, trinkets) and
  stays wrong for the rest of the fight if only toggled. Re-derive it at
  every anchor from the plain payload against the combat-enter baseline,
  rather than only flipping it per fire.
- Baseline: the plain PLAYER_REGEN_DISABLED read (proven plain at that
  instant), NOT `rangedBaseSpeed` — that is the tooltip weapon speed and
  excludes quiver haste. A fight entered with a haste buff already up
  starts from a hasted baseline; the anchor re-derivation covers it.
- Candidate revert needs the pre-candidate expiry stashed.

## 8. In-game verification checklist (Phase A)

1. SnD cast mid-swing: one UPDATE at the cast (existing) and NO second
   UPDATE from the fire (Rule 1).
2. SnD expiry mid-combat on a dummy: UPDATE at the fade fire with the
   back-dated lengthened expiry (Rule 3); the next anchor agrees within
   tens of ms.
3. SnD recast while active: no UPDATE (refresh: no fire, flag holds); the
   later fade lands in the RECAST's window.
4. SnD recast within ~0.4 s AFTER expiry (before the late fade fire): no
   un-haste from the old aura's fire; the swing stays hasted.
5. Recast after a fade: application UPDATE once (parity alternation).
6. Weapon swap with SnD active: log the order of EQUIP vs ATKSPEED; no
   un-haste; the next anchors hasted on the new base.
7. Parry inside a fading SnD window: both adjustments compose; at most one
   swing of bounded error.
8. Blade Flurry used and fading while SnD is up: no un-haste outside the
   SnD window.
9. Mob attack-speed slow applied/removed while SnD is up (e.g. a Thunder
   Clap mob): no un-haste outside the SnD window.
10. Death with SnD up, resurrect, cast SnD: the cast applies (A8).
11. Talented rogue (Improved SnD): no wrong un-haste; anchor-clear fallback
    (A10).
12. Duel / player target: target swing timer behavior unchanged.
13. Restricted content (dungeon): no Lua errors; a secret CP read disables
    Rule 3 for that cast and falls back to the anchor clear.
14. Classic Era smoke: zero behavior change.

## 9. Release discipline

- Changelog entry under `[Unreleased]` written with the change (library
  convention).
- LibStub MINOR and TOC `## Version` bump at release preparation only.
- The addon bumps `REQUIRED_LIB_MINOR` when the next library tag ships.
- Evidence pointers stay in `HASTE_APPLICATION_FINDINGS.md` 7.1 item 4 and
  `docs/evidence/`.
