# Swing Timer Improvement Plan

Status: Phases 1 and 2 APPLIED 2026-09-28. Phase 1: `PLAYER_SWING` payload
validation + all-client `PLAYER_DEAD` reset. Phase 2: Forever ranged reads
switched to the third `UnitAttackSpeed` return (probe-verified 2026-09-28,
open world; see §2). Changelog entries under `[Unreleased]`. Phase 3 remains
spec only, not applied (separate branch). The BCC min-damage divergence guard
(§2) is deferred pending the BCC probe. Section 6 (Classic+ spell coverage) is
researched but pending in-game verification — no table entries applied. Working
tree: branch
`feature/forever-support`; version numbers bump at release preparation, per
AGENTS.md.

Companion document to `docs/FOREVER_API_FINDINGS.md`: that file is the
Forever / Midnight API investigation record; this one holds the forward-looking
improvement plan drawn from external reference implementations. Section
references of the form §N point into `FOREVER_API_FINDINGS.md`.

Sources analyzed (2026-09-28): Blizzard's own `Blizzard_SwingTimer.lua`
(Gethe/wow-ui-source, `forever` branch); the EllesmereUI Forever swing timer
(PR #2128 — merged into that repo 2026-09-19, removed from its main during the
2026-09-24 audit cycle; studied from commit diff `4fd2a17`); SuperSwingTimer-WoW
v0.2.3 (`SuperSwingTimer_State.lua`); Conceal issue #28
(joaoc-pires/wow-addon-conceal). Full index in section 5.

## 1. Phase 1 — hardening, low risk (approved scope) — APPLIED 2026-09-28

**Decision recorded 2026-09-28: the `PLAYER_DEAD` reset applies to ALL clients**
(maintainer decision), not Forever-only. Classic Era must re-run the regression
check (§8.9 item 1) once Phase 1 is applied.

### 1a. `PLAYER_SWING` payload validation (Forever only)

The applied handler (§8.4) rejects only secret values; a malformed payload
(non-number, NaN, non-positive, infinite) would be cached into
`unit.mainSpeed`/`offSpeed`/`rangedSpeed` and propagate into fired events. The
verified payload (§4.5) is always a plain positive number, so the extra guard is
pure crash-proofing with zero behavior change in every observed case. Insert
after the secret check:

```lua
	if type(swingDuration) ~= "number"
		or swingDuration ~= swingDuration -- NaN
		or swingDuration <= 0
		or swingDuration == math.huge then
		return -- malformed payload; do not cache it as a weapon speed
	end
```

(Reference: EllesmereUI #2128 rejects the same classes — secret, non-number,
NaN, `<= 0`, `math.huge` — before using the payload.)

### 1b. `PLAYER_DEAD` reset (all clients)

The library has no death handling: a player who dies and is resurrected in place
(no loading screen, so `PLAYER_ENTERING_WORLD` never fires) keeps stale swing
timers until the next swing. New handler plus `frame:RegisterEvent("PLAYER_DEAD")`
alongside the other lifecycle events:

```lua
function lib:PLAYER_DEAD()
	local unit = self.player
	if not unit then
		return
	end
	if unit.mainTimer and not unit.mainTimer:IsCancelled() then
		unit.mainTimer:Cancel()
		self.callbacks:Fire("UNIT_SWING_TIMER_STOP", unit.id, "mainhand")
	end
	if unit.offTimer and not unit.offTimer:IsCancelled() then
		unit.offTimer:Cancel()
		self.callbacks:Fire("UNIT_SWING_TIMER_STOP", unit.id, "offhand")
	end
	if unit.rangedTimer and not unit.rangedTimer:IsCancelled() then
		unit.rangedTimer:Cancel()
		self.callbacks:Fire("UNIT_SWING_TIMER_STOP", unit.id, "ranged")
	end
	unit.casting = false
	unit.channeling = false
	unit.isAttacking = false
	unit.preventSwingReset = false
	unit.auraPreventSwingReset = false
	if unit.feignDeathTimer then
		unit.feignDeathTimer:Cancel()
	end
	unit.feignDeathTimer = nil
end
```

Design notes:

- Fires `UNIT_SWING_TIMER_STOP` only for hands with an active, uncancelled timer;
  consumers see the bar end at death instead of sitting stale — correct
  semantics. `PLAYER_DEAD` is a player-only event; the target unit is untouched.
- Cached speeds and expiration times are deliberately left untouched (an expired
  `expirationTime` reads as already-ended; `PLAYER_ENTERING_WORLD` owns full
  reinitialization).
- `firstMainSwing`/`firstOffSwing` are left to `PLAYER_LEAVE_COMBAT` — death drops
  combat, so that handler fires anyway.
- `auraPreventSwingReset` is cleared defensively: `SPELL_AURA_REMOVED` may not
  fire on death, and a stale flag would wrongly suppress post-resurrection cast
  resets.
- Behavior change on classic flavors (new `STOP` events at a point where
  consumers previously saw a stale bar) — changelog under `Fixed` when applied.

Verification when applied (extends §8.9): die in the open world, accept an
in-place resurrection — expect one `UNIT_SWING_TIMER_STOP` per active hand at
death, no Lua errors, and a clean `START` on the next swing. Run once on Classic
Era (all-client change) and once on Forever.

## 2. Phase 2 — Forever ranged-speed source (probe-gated; this branch) — APPLIED 2026-09-28

Blizzard's native bar and EllesmereUI #2128 both read ranged speed from the
third `UnitAttackSpeed` return; this library reads `UnitRangedDamage` (call
sites: `Unit:SwingStart` ranged branch, `PLAYER_ENTERING_WORLD`,
`PLAYER_TARGET_CHANGED`, `UNIT_ATTACK_SPEED` ranged branch). SuperSwingTimer
additionally documents `UnitRangedDamage` returning MIN DAMAGE (not speed) on
the TBC 2.5.5 Legion-based client. **Gate: no code lands before the probe
extends open item 2 (§9 — never run with a ranged weapon equipped):**

- `/run local _,_,r=UnitAttackSpeed("player") print(r,issecretvalue(r) and "SECRET" or r)`
- `/run local r=UnitRangedDamage("player") print(r,issecretvalue(r) and "SECRET" or r)`
- Both, open world out of combat AND mid-fight, hunter with bow equipped; compare
  each against the live `PLAYER_SWING` type-2 duration.

If the third return is confirmed plain and matches the swing duration: switch
the Forever ranged reads to it with `UnitRangedDamage` as fallback, and add the
min-damage divergence guard for BCC (fresh plain read wildly divergent from the
cached speed → keep the cached value). If the probe is inconclusive, ship nothing
and record the result here.

**Gate resolved 2026-09-28 — CONFIRMED (open-world probe, hunter with bow;
dungeon not retested — §4.2 already documents instanced mid-fight secrecy and
the switch does not change mid-combat behavior):** out of combat, the third
return = `UnitRangedDamage` = the live `PLAYER_SWING` type-2 duration
(2.0910000801086, plain). Mid-fight, both API reads flag secret together while
the swing payload stays plain — no secrecy advantage either way. Applied as a
`GetRangedSpeed(unitId, fallback)` helper (Forever reads the third return
first, falls back to `UnitRangedDamage`; classic clients keep
`UnitRangedDamage` byte-identically) at all four ranged-read call sites:
`Unit:SwingStart`, `PLAYER_ENTERING_WORLD`, `PLAYER_TARGET_CHANGED`,
`UNIT_ATTACK_SPEED`. **The BCC divergence guard remains deferred** — the BCC
sub-test was not run (the submitted captures were all Forever-client); add it
only after probing a BCC character with a bow equipped.

## 3. Phase 3 — classic ranged accuracy via Auto Shot cooldown (separate branch)

SuperSwingTimer anchors the ranged timer to Auto Shot's own spell cooldown
(`GetSpellCooldown(75)`: `startTime` is the swing start, `duration` is the hasted
swing speed), which replaces guessed cast windows outright. This library's
equivalent guess is `autoShotCastTime = 0.52 * (rangedSpeed / rangedBaseSpeed)`
plus the tooltip-scraped base speed. Candidate: use the existing
`GetSpellCooldownCompat` shim (§8.1) where `duration > 0` as the authoritative
ranged speed (and, if measurements support it, the anchor), keeping current
behavior as fallback. Constraints:

- Classic flavors with CLEU only (`isClassic or isBCC or isWrath`; Cata changes
  ranged mechanics — out of scope until measured).
- Wand/thrown (`3018`/`2764`/`5019`) keep the existing path; spell 75 covers
  Auto Shot hunters.
- A per-flavor measured cadence pass (Era/BCC/Wrath) before merge — why this is
  not bundled with Phases 1–2.
- Optional sub-item: `GetNetStats()` latency in the `FAILED_QUIET` recast delay.

## 4. Rejected or deferred (with reasons — do not re-litigate without new data)

| Item | Verdict | Reason |
|---|---|---|
| Range state (`PLAYER_SWING_RANGE_UPDATE` / `C_SwingTimer.IsTargetWithinSwingRange`) | Blocked upstream | §4.4: the event fires exactly once, at the `EnableRangeCheck` call — `(0, false, false)` — then never again; range transitions produce nothing; the query returned nil without a target and - probe 2026-09-28 - nil with a target in melee range AND out of range after EnableRangeCheck(0, true): the query path is dead too. Broken beta wiring; in-game report filed. Revisit when Blizzard acts. |
| `C_Spell.IsCurrentSpell` queue-state exposure | Deferred | New permanent public API surface (needs a maintainer decision on shape); unprobed on Forever (may be restriction-affected). The `next_melee_spells` tables stay regardless — they anchor swings, a different job. |
| Periodic sanity resync ticker (SuperSwingTimer's 0.10 s / 1.0 s speed polls) | Deferred | Polling against the library's event-driven design; on Forever the rescale is intentionally disabled (§9 item 16, verified no-rescale); on classic flavors `UNIT_ATTACK_SPEED` fires reliably. |
| Registration gating (register events only when needed, per Blizzard's manager) | Rejected | The library is always "enabled"; consumers depend on events firing unconditionally. Gating changes library semantics for zero measured gain. |
| Parry haste heuristic (§8.10 option A/E) | Deferred per §8.10 | Decision already recorded: B + D (passive self-correction + Blizzard request). |
| `C_DurationUtil` duration objects | Rejected for the library | §4.5 disproved the need: `PLAYER_SWING` carries plain numbers; duration objects are a consumer-side display concern (EllesmereUI uses them for its own bars). |

## 5. Reference index (for future archaeology)

- **Blizzard `Blizzard_SwingTimer.lua`** — `forever` branch of Gethe/wow-ui-source,
  build 1.60.1 (70009). `PLAYER_SWING` registration gated on weapon presence +
  `showSwingTimer` CVar; ranged speed from the third `UnitAttackSpeed` return;
  `WEAPON_SLOT_CHANGED`; no mid-swing correction either — re-anchors at each
  `PLAYER_SWING` (confirms this library's Forever model matches the engine's own).
  Validated 2026-09-28 against the full addon (Lua + XML + TOC; the XML is pure
  presentation, so the Lua is the complete behavioral surface): the bar handles
  NONE of the classic swing mechanics — no parry haste, no cast-completion reset,
  no cast hold, no pause spells, no instant resets (Feign Death), no off-hand
  first-swing half-cycle prediction, no ranged movement-cancel delay, no
  next-melee queue state, no death handling (a stale bar survives death when
  visibility is "Always"; combat-gated visibility clears it only as an OnHide
  side effect). What it does handle beyond per-swing re-anchoring: weapon-swap
  reset of an in-flight bar (`ResetSwingTimerForEquippedWeapon`) and range
  visuals (`PLAYER_SWING_RANGE_UPDATE` — the event §4.4 shows is broken on the
  beta). It is a pure display layer over `PLAYER_SWING` — accurate at each swing
  anchor, wrong in between whenever the engine modifies an in-flight swing. This
  confirms §9 item 15 reading (a): the reset rule is live in the engine while
  the built-in bar is a simplistic event-driven UI, so this library's
  reconstruction remains the only source of mid-cycle accuracy on Forever.
- **EllesmereUI PR #2128** (`feat(qol): add Forever swing timer`, dfrisone;
  merged 2026-09-19, removed from main in that repo's 2026-09-24 audit cycle —
  study commit diff `4fd2a17`): payload validation classes; `C_DurationUtil`
  bindings; `C_Spell.IsCurrentSpell` queued-attack highlight (base IDs
  78/845/6807 resolve localized names for all ranks); `PLAYER_DEAD` reset;
  availability gating on plain `UnitAttackSpeed` returns;
  `PLAYER_REGEN_DISABLED/ENABLED` for visibility.
- **SuperSwingTimer-WoW v0.2.3** (`SuperSwingTimer_State.lua`): Auto Shot
  cooldown anchor (spell 75); `GetNetStats()` latency cache; 0.10 s/1.0 s speed
  sanity sync; `UnitRangedDamage` min-damage quirk (TBC 2.5.5);
  `C_Spell.IsAutoRepeatSpell` + `IsMounted` guards (transient autorepeat stop
  events must not clobber the ranged timer); movement pinning in the cast
  window; `GetRangedHaste` estimation (note: `GetHaste()` is melee haste, not a
  valid fallback); ranged-start dedupe window (0.25 s + latency); GCD query via
  spell 61304; castGUID guard in `UNIT_SPELLCAST_*` handlers.
- **Conceal issue #28** (joaoc-pires/wow-addon-conceal): confirms the native
  `Blizzard_SwingTimer` frames (`SwingTimerMainHand/OffHand/RangedFrame`) exist
  and are managed by addons for visibility — downstream signal that this
  library's Forever output coexists with (and duplicates) the native bars. If
  users report double bars, a README note on the `showSwingTimer` CVar is the
  cheap fix.

## 6. Classic+ spell coverage (researched 2026-09-28; in-game verification pending)

Sources and full findings: FOREVER_API_FINDINGS.md §9 item 5 (Daybreak Forever
datamine, TheWoWDB `wow-forever`, Wowhead Forever, wowforevertalents.com — 48 new
Forever abilities swept across all nine classes). **No table changes applied** —
both candidates below are blocked on in-game verification per AGENTS.md (a wrong
guess ships a broken release to every downstream addon).

### 6a. Slam pause (candidate: `pause_swing_spells`, Forever)

Slam is new to the Forever trainer (Rank 1 at level 20, 1.5 s cast, 18 s
cooldown); base Slam presumably delays the melee swing, and the Improved Slam
talent (spell 12862) removes the delay entirely ("Slam no longer interrupts or
delays your melee swing"). The Era-routed `pause_swing_spells` is empty, so today
a Forever Slam cast resets the swing on completion — wrong both with and without
the talent. Gate: verify in-game which cast events fire for Slam (probe below),
with and without Improved Slam talented, and whether the observed `PLAYER_SWING`
anchors match the pause model or the reset model. Design question for the
maintainer: talent-conditional behavior cannot live in a static table — either
model the no-talent default (pause) and accept a one-cycle transient for
Improved Slam players, or detect the talent (no obvious 12.x talent-inspection
API) and skip.

### 6b. Maelstrom Weapon aura (candidate: `prevent_reset_swing_auras`, Forever)

Maelstrom Weapon is a new-in-Forever Enhancement talent; a five-stack Lightning
Bolt at rank 5 is instant and must not reset the swing (the exact case the
`prevent_reset_swing_auras` mechanism exists for — BCC 408505, Wrath 53817). Two
gaps stack on the Forever path: the Era-routed table is empty, and the flag
mechanism is CLEU-based (`SPELL_AURA_APPLIED`/`REMOVED` — dead on Forever, §4.1),
so a Forever fix needs `UnitAura`-based detection (the library already upvalues
`UnitAura`). Gate: capture the Maelstrom Weapon buff spell ID in-game (probe
below), then confirm a 5-stack instant Lightning Bolt fires
`UNIT_SPELLCAST_SUCCEEDED` that would otherwise reset the timer.

### 6c. Probes (add to the next in-game session)

```lua
-- Slam: which cast events fire, with and without Improved Slam talented
-- (cast Slam mid-swing-cycle; record START/SUCCEEDED spell IDs; compare
--  against PLAYER_SWING anchors from the FOREVER_API_FINDINGS appendix listener)
/run PS2=PS2 or CreateFrame("Frame") PS2:RegisterEvent("UNIT_SPELLCAST_START") PS2:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") PS2:SetScript("OnEvent",function(_,_,e,u,_,s) if u=="player" then print(e,s) end end)

-- Maelstrom Weapon buff spell ID while stacks are up (Enhancement shaman)
/run local t={} for i=1,40 do local n,_,_,_,_,_,_,_,_,sid=UnitAura("player",i) if n then t[#t+1]=n.."="..sid end end print(table.concat(t,", "))

-- Slam rank spell IDs straight from the spellbook (Forever may differ from
-- classic-era 1464+ even though Wowhead's Forever page resolves 1464)
/run local n,_,_,_,_,_,id=GetSpellInfo("Slam") print(n,id)
```

### 6d. Cleared by the sweep (no action needed)

`1282503` = Blazewind Blast — an instant *item effect*, no table entry (appeared
in the §4.3 capture only because `UNIT_SPELLCAST_SUCCEEDED` fires for all
units). The other 47 new Forever abilities are instants or passives with no
swing-timer interaction: Eureka! (1259812/13/17/21/23), Strider Kick (1317257),
Hydra Shot (1293020), Spearing Strike (1310222), Twist of Light (1310735), and
the talent/passive set. New Forever engineering bombs are unaudited (optional
follow-up; a missing `noreset` entry self-corrects at the next swing).
