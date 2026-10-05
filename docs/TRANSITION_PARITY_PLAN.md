# Transition-Parity Implementation Plan — UNIT_ATTACK_SPEED as the unified haste trigger

Status: plan, 2026-10-05. Design and evidence: `HASTE_APPLICATION_FINDINGS.md`
section 7.1 item 4 (all rogue-side pillars proven on build 70205). Pending
captures: warrior (Flurry charge-0 fire) and hunter (Deadly Aspects gain/fade
pair) — `M1_SESSION_SCRIPT.md` B6. This plan is the implementation contract:
phase A is fully evidence-backed; phases B and C are scaffolding now, activated
by their table entries when the captures land.

## 1. Goal

On WoW: Forever, kill the one-swing expiry lag of the dynamic-haste family and
unify application/fade detection on one event: `UNIT_ATTACK_SPEED` fires at the
instant any attack speed changes (proven: application simultaneous with the
cast, 5 cases; fade at the expiry, 4 cases; refresh fires nothing, 2 cases;
double-fire per change — dedupe required). The event carries no value and no
hand; direction comes from classification plus the tracked state, and every
decision is settled by the next plain anchor.

## 2. Rules (the handler contract)

| # | UNIT_ATTACK_SPEED fire with... | Action |
|---|---|---|
| 1 | a recent SUCCEEDED of a dynamic-table spell | none — the SUCCEEDED path already applied the factor; the fire is corroboration |
| 2 | a recent outgoing crit (Phase B) | apply the deterministic-proc factor (Flurry) |
| 3 | no identified trigger, `unit.dynamicHasteActive` set | UN-HASTE now: progress-preserving lengthening; clear the flag; this kills the one-swing lag |
| 4 | a recent SUCCEEDED of a non-dynamic spell, or a recent equipment change | none — snapshot family (M0): the in-flight swing completes on its old speed; the next anchor re-anchors (existing mechanism) |
| 5 | no identified trigger, nothing tracked | Phase A: none (the anchor settles). Phase C: parity candidate for the probabilistic-proc class (Deadly Aspects) |

The blanket Layer-1 stale-mark is REJECTED for snapshot fires (M0 — the
in-flight expiry is not stale); only unexplained fires (Rule 5 candidates)
may mark uncertainty, and Phase A does not implement it.

## 3. Current code map (v2.2.0, MINOR 37)

- `lib:UNIT_ATTACK_SPEED(_, unitGUID)` — line ~659. The classic proportional
  rescale, per hand, each gated `and not isForever`; the reads run through
  `ResolveSecret` (secret falls back to the cached speed, so on Forever the
  classic path is inert twice over). Already registered for "player" and
  "target" at line ~1072. Contains a windowed skip pattern
  (`skipNextAttackSpeedUpdate` / `...Count`) — the dedupe precedent to reuse.
- `lib:ApplyDynamicHaste(unit, factor)` — line ~495. Per-hand progress-
  preserving shortening: `speed / factor`, `expiry = now + remaining / factor`,
  50 ms young-swing guard, cancels and re-arms the hand's C_Timer, fires
  `UNIT_SWING_TIMER_UPDATE`.
- SUCCEEDED handler dynamic branch — line ~842: `if isForever and spell and
  dynamic_haste_spells[spell] then if unit.dynamicHasteActive ~= spell then
  unit.dynamicHasteActive = spell; self:ApplyDynamicHaste(...) end end`.
  `dynamicHasteActive` stores the spell ID (single active source).
- PLAYER_SWING anchor handler — lines ~610-635: the current expiry mechanism —
  an anchor speed above `cachedSpeed * 1.02` clears `dynamicHasteActive`.
  This is the one-swing lag Rule 3 removes; KEEP it as the settler/defense.
- `lib:PLAYER_EQUIPMENT_CHANGED` — line ~950: slots 16/17/18 restart the
  hands. The weapon-swap classification trigger.
- `lib:UNIT_COMBAT` — line ~648: player PARRY only, calls ApplyParryHaste.
  Phase B adds the outgoing-crit branch here.
- `dynamic_haste_spells` — line ~93, populated per flavor; on Forever it
  currently holds SnD rank 1 (5171 = 1.2).
- No PLAYER_REGEN registration exists; combat-adjacent handlers are
  PLAYER_ENTER_COMBAT / PLAYER_LEAVE_COMBAT (the auto-attack toggle).

## 4. Phase A — all proven (implement now, Forever-gated)

A1. Unit state fields (on the Unit table, nil-initialized in the Unit
    constructor): `atkSpeedLastFire`, `lastDynamicCast`, `lastEquipChange`.

A2. SUCCEEDED handler, dynamic branch: add `unit.lastDynamicCast = now`
    (the Rule 1 classification window).

A3. `lib:PLAYER_EQUIPMENT_CHANGED`: add
    `if isForever then self.player.lastEquipChange = GetTime() end`
    (the Rule 4 window).

A4. New `function lib:RemoveDynamicHaste(unit)` — the exact inverse of
    ApplyDynamicHaste, per hand (main/off; ranged excluded until a dynamic
    ranged spell is verified):
    ```
    speed = speed * factor
    expiry = now + remaining * factor
    same 50 ms young-swing guard (a fade at a swing boundary after the
      anchor already re-anchored unhasted leaves dynamicHasteActive nil,
      so the guard and the flag agree)
    cancel + re-arm the hand's C_Timer; fire UNIT_SWING_TIMER_UPDATE
    clear unit.dynamicHasteActive (after both hands)
    ```

A5. The Forever branch at the top of `lib:UNIT_ATTACK_SPEED` (player unit
    only; the target unit keeps today's behavior):
    ```
    if isForever and unit.isPlayer then
        local now = GetTime()
        -- dedupe the double-fire (proven: two identical fires per change)
        if unit.atkSpeedLastFire and now - unit.atkSpeedLastFire < 0.05 then
            unit.atkSpeedLastFire = now
            return
        end
        unit.atkSpeedLastFire = now
        -- Rule 1: the dynamic cast already applied the factor
        if unit.lastDynamicCast and now - unit.lastDynamicCast < 0.15 then
            return
        end
        -- Rule 4: snapshot triggers (seal/form casts arrive via SUCCEEDED
        -- with no dynamic-table entry; equipment changes via A3) — no action
        if unit.lastEquipChange and now - unit.lastEquipChange < 0.15 then
            return
        end
        -- Rule 3: un-haste the tracked dynamic source
        if unit.dynamicHasteActive then
            local factor = dynamic_haste_spells[unit.dynamicHasteActive]
            if factor then
                self:RemoveDynamicHaste(unit, factor)
            end
            return
        end
        -- Rule 5 (Phase A): no tracked source, no action; the next anchor
        -- settles any untracked transition. Phase C replaces this branch.
        return
    end
    ```
    The classic path below is untouched (`not isForever` gates stay).

A6. Anchor handler: no change — the `dynamicHasteActive` clear stays as the
    settler and the defense against a missed fire.

A7. Dispatch-order caveat: at the cast instant the capture shows SUCCEEDED
    dispatched before UNIT_ATTACK_SPEED (CAST logged before ATKSPEED at the
    same timestamp). If the order ever flips, a cast fire could reach Rule 3
    before the SUCCEEDED branch sets the flag — the un-haste would misfire
    once and the next anchor corrects it (bounded one-swing error, the
    standard class). The `lastDynamicCast` window makes the steady-state
    order irrelevant after the first cast of each source.

A8. Parry interplay: ApplyParryHaste shortens remaining; RemoveDynamicHaste
    lengthens it — both are remaining-time adjustments and compose. Add to
    the verification list: a parry inside a fading SnD window.

A9. Weapon swap while a dynamic source is active: the equipment window makes
    the fire a Rule 4 no-action; PLAYER_EQUIPMENT_CHANGED restarts the hands,
    the next anchors arrive hasted on the new base, and `dynamicHasteActive`
    survives (correct — the aura is still up). Verify in-game; if the anchor
    expiry-clear misfires on the new base (speed comparison against the
    post-swap cache), tighten the clear's cache update there.

## 5. Phase B — deterministic procs (activate on the warrior capture)

- Add `unit.lastCrit` set in the UNIT_COMBAT outgoing-crit branch
  (WOUND CRITICAL on the target tokens — the findings' validated filters).
- Add `deterministic_proc_spells = { [flurryAuraOrTalentID] = factor }`,
  populated only after the capture verifies the Forever engine rule (every
  crit applies/refreshes; both hands; refresh-on-crit) and the per-rank
  factor.
- The handler's Rule 2 window: `if unit.lastCrit and now - unit.lastCrit
  < 0.15 and deterministic_proc_spells[...] then apply; return end`.
  Flurry application = crit + fire; Flurry fade = fire with no crit and no
  cast while the flag is set (Rule 3 generalizes: the tracked-source flag
  names which factor to remove). The charge count is the cross-check only.

## 6. Phase C — probabilistic procs (activate on the hunter capture)

- Parity state per hand: `unit.rangedHasted` (and melee equivalents),
  initialized at combat enter — register PLAYER_REGEN_DISABLED
  (Forever-gated) and read the three speeds in the plain window (proven:
  the reads are plain at the PLAYER_REGEN_DISABLED instant); the library
  already caches `rangedBaseSpeed` for the comparison. ResolveSecret keeps
  the read safe if the window is missed.
- `probabilistic_proc_spells = { [deadlyAspectsID] = factor }` after the
  capture (ID, factor by talent rank, and the fire pair ~12 s apart).
- Rule 5 becomes: fire + no trigger + nothing tracked -> if the parity says
  "not hasted" and a probabilistic entry exists for the class, apply the
  factor as a CANDIDATE to the in-flight swing; the next anchor confirms
  (hasted -> keep; unchanged -> revert to the pre-candidate expiry, which
  must be stashed for the revert). Parity says "hasted" -> fade of an
  untracked/probabilistic source: un-haste with the tracked candidate factor.

## 7. Classic flavors

Zero behavior change: every new line is Forever-gated (`isForever`), the
classic UNIT_ATTACK_SPEED path is untouched, and `luajit -bl` must stay
clean. Phase A touches no table the classic flavors read.

## 8. In-game verification checklist (Phase A)

1. SnD cast mid-swing: one UPDATE at the cast (existing) and NO second
   UPDATE from the ATKSPEED fire (Rule 1 window).
2. SnD expiry mid-combat on a dummy: UPDATE at the fade fire with lengthened
   expiry (Rule 3); the next anchor agrees; no double-UPDATE from the
   anchor clear.
3. SnD recast while active: no UPDATE at all (refresh: no fire, guard holds).
4. Recast after a fade: application UPDATE once (parity alternation).
5. Paladin seal cast / swap mid-combat: NO UPDATE at the fire (Rule 4); the
   in-flight swing completes on its old speed (M0); the next anchor
   re-anchors.
6. Weapon swap with SnD active: no un-haste; the next anchors hasted on the
   new base.
7. Parry inside a fading SnD window: both adjustments compose; one swing of
   bounded error at most.
8. Restricted content (dungeon): no Lua errors; Rule 3 needs no data read,
   so restricted darkness changes nothing.
9. Classic Era smoke: zero behavior change (`issecretvalue` nil there; all
   new branches Forever-gated).

## 9. Release discipline

- Changelog entry under `[Unreleased]` written with the change (library
  convention).
- LibStub MINOR and TOC `## Version` bump at release preparation only.
- The addon bumps `REQUIRED_LIB_MINOR` when the next library tag ships.
- Evidence pointers stay in `HASTE_APPLICATION_FINDINGS.md` 7.1 item 4 and
  `docs/evidence/`.
