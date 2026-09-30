# WoW: Forever / Midnight API Restrictions — Investigation Findings

Status: design document (`docs/FOREVER_API_FINDINGS.md`, excluded from addon packages
via `.pkgmeta`). Investigation findings and implementation spec for the Forever
support work; in-game verification checklist (8.9) still pending.
Implementation: APPLIED on branch `feature/forever-support` (2026-09-25) — code
changes plus the `CHANGELOG.md` `[Unreleased]` entries (entries are written with
the change, per the enforced AGENTS.md rule). Only the version **numbers**
(LibStub `MINOR` 32 → 33 and TOC `## Version: 2.1.6` → 2.2.0) are held back and
bumped together at release preparation. The `## Interface: 16001` TOC line is
functional (required for the addon to load on the Forever beta), not versioning,
and is included. Pending the in-game verification checklist (8.9). Note: the ranged cast-window narrowing at the CLEU `SPELL_CAST_START`
branch is dead on Forever regardless of its `isClassic` gate (CLEU never fires
there) and was correctly left unchanged; ranged timing on Forever comes from
`PLAYER_SWING` type 2 plus the `FAILED_QUIET` extension.
Date of investigation: 2026-09-24/25. All results verified live on the Forever beta client.

## 1. Executive summary

WoW: Forever (BlizzCon 2026 announcement) runs Mainline's UI architecture and inherits
the Midnight (12.0.x) addon API restrictions — the "Secret Values" system that limits
addons from performing "complex logic and decision making based off combat information".
Live probing on the Forever beta confirms the restrictions are enforced there today.

Impact on LibClassicSwingTimerAPI in Forever:

1. **Misdetection**: Forever reports `WOW_PROJECT_ID = 1` (the `WOW_PROJECT_MAINLINE`
   value), so the library's `isRetail` flag is true and it loads retail spell tables and
   retail swing-clip logic in a Classic-rule-set game.
2. **No swing events**: `RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` is silently
   refused (returns `false`, no error). The library's entire CLEU-driven swing detection
   (`SWING_DAMAGE`, `SWING_MISSED`, parry haste, aura tracking, ranged resets) never runs.
3. **Secret weapon speeds in combat**: `UnitAttackSpeed` / `UnitRangedDamage` return
   secret values while fighting in instanced content; the library's comparisons and
   arithmetic on them throw Lua errors mid-fight.
4. **Guaranteed error**: the global `GetSpellCooldown` is nil (removed in retail 11.0.0,
   replaced by `C_Spell.GetSpellCooldown`); the Feign Death watcher at line 602 errors
   on first FD cast.
5. **Good news**: `UNIT_SPELLCAST_SUCCEEDED` fires in combat with **plain, classic-era
   spell IDs** — the ID-table logic and cast-reset detection remain viable, and Forever
   reuses Classic spell IDs, so the Classic-era tables are the right base for the
   Forever path.
6. **Native swing APIs exist**: Blizzard ships a `C_SwingTimer` system with a
   `PLAYER_SWING` event backing the built-in swing timer — event-accurate swing
   detection is possible in Forever without CLEU. Runtime payload verified:
   `(swingDuration, swingType)` = plain-number weapon speed + hand type
   (MainHand=0, OffHand=1, Ranged=2), usable directly by the library's swing math.
   The payload was verified **plain even mid-fight in a dungeon** — the full numeric
   contract holds everywhere. The event is player-only (no target swing tracking).

The library currently does not load in Forever at all (no matching `## Interface` line
for `16001`).

## 2. Test environment

| Item | Value |
|---|---|
| Client | WoW: Forever beta |
| Build | `1.6.0.1`, build `70009`, dated Sep 23 2026 |
| Interface | `16001` |
| `WOW_PROJECT_ID` | `1` (== `WOW_PROJECT_MAINLINE`) |
| API set | Mainline 12.1.5-era (Blizzard statement via WoW UI Discord) |
| Test character | Paladin |
| Method | In-game `/run` and `/dump` probes (tainted execution context, same as addon code); macros are capped at 255 chars — long scripts get truncated and error with `unfinished string` |

## 3. Background: the Midnight restrictions

- Introduced in retail pre-patch 12.0.0 (Jan 2026), carried into 12.1.x. Blizzard's
  stated goal: limit addons' "complex logic and decision making based off combat
  information", not UI look-and-feel customization.
- Implemented as **Secret Values**: values returned by combat-related APIs that tainted
  (addon) code can store and pass around but cannot compare, do arithmetic on, or
  convert. Taint enforcement pops "blocked from an action only available to the Blizzard
  UI" dialogs for restricted actions (observed with the forced-taint macro environment,
  internally named `ForceTaint_Strong`).
- After backlash, Blizzard scoped several restrictions: they apply during **boss
  encounters and Mythic+ runs**. In the Forever beta, `C_CombatLog.IsCombatLogRestricted()`
  returned `true` for the whole dungeon session (in and out of combat), while stat
  secrets only flipped on mid-fight — at least two restriction tiers.
- Detection/inspection tooling that exists in-client:
  `issecretvalue(value)`, `C_Secrets.ShouldCooldownsBeSecret()`,
  `C_Secrets.ShouldSpellCooldownBeSecret(spell)`,
  `C_Secrets.ShouldUnitAuraInstanceBeSecret(unit, auraInstanceID)`,
  `C_CombatLog.IsCombatLogRestricted()`, `GetRestrictedActionStatus(type)`,
  and the `/api` documentation browser (which now annotates security restrictions).

## 4. Probe results (all live-verified)

### 4.1 API availability

| Probe | Result | Note |
|---|---|---|
| `/dump GetSpellCooldown` | nil | Global removed (retail 11.0.0); Feign Death path broken |
| `/dump C_Spell.GetSpellCooldown` | function | Replacement namespace present; returns a table; `isEnabled`/`isActive`/`maxCharges` are non-secret, `startTime`/`duration` go secret when restrictions active |
| `RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` | returned `false`, no error | Silent refusal from tainted code. First attempt also triggered the `ForceTaint_Strong` "blocked action" popup |
| `issecretvalue` | function | Secret Values system active in Forever |
| `UNIT_SPELLCAST_SUCCEEDED` registration | works | Listener fired in combat |
| `GetBuildInfo()` | `1.6.0.1`, `70009`, `16001` | Reliable Forever signature (project ID is not) |

### 4.2 Secret-value state by context

Paladin, one dungeon session. "Plain" = normal readable value; "SECRET" = `issecretvalue() == true`.

| Probe | Open world, out of combat | Open world, mid-fight | Dungeon, out of combat | Dungeon, mid-fight |
|---|---|---|---|---|
| `UnitAttackSpeed("player")` | 2.4, plain | 2.4, **SECRET** | 2.4, plain | 2.4, **SECRET** |
| `UnitRangedDamage("player")` | 0 (no weapon), plain | 0, **SECRET** | 0 (no ranged weapon), plain | 0 (no ranged weapon), **SECRET** |
| `C_Secrets.ShouldCooldownsBeSecret()` | false | **true** | false | **true** |
| `C_CombatLog.IsCombatLogRestricted()` | **true** | **true** | true | true |

Implications:

- **Stat secrets apply in ALL combat** — open-world fighting hides weapon speeds the
  same as instanced combat. The secret guards and `PLAYER_SWING` anchoring are needed
  in every combat context; the patch needs no content-type branching.
- **The combat-log restriction appears always-on in this beta** — `true` even out of
  combat in the open world. This retroactively explains the outright CLEU
  registration refusal: globally restricted, not encounter-scoped. Broader than
  Midnight retail's announced "encounters and M+" scoping — worth a line in the
  dev thread.
- Speed math (comparisons, `lastSwing + speed`, ratio multipliers) is fatal in ANY
  combat, but speeds read fine out of combat — cached values captured before the
  pull remain usable (secrecy applies to fresh API reads, not previously stored
  plain numbers).

### 4.3 Spellcast payload (the decisive test)

`UNIT_SPELLCAST_SUCCEEDED` listener over one combat, Paladin, dungeon:

| Spell ID | Identified spell | Era | Secret? |
|---|---|---|---|
| `19750` | Flash of Light | Classic | plain |
| `20288` | Seal of Righteousness | Classic | plain |
| `6603` | Attack toggle | Classic | plain |
| `20271` | Judgement | Classic | plain |
| `678` | Rend (another unit — event fires for all units) | Classic | plain |
| `1282503` | Unknown — new Classic+ content, 7-digit ID | Forever | plain |

Key conclusions:

- The event fires in combat and **spell IDs are plain** — `table[spellID]` lookups work.
- IDs are **classic-era** (Rend `678`, SoR `20288`, Judgement `20271`), not retail IDs.
  The Forever path should reuse the Classic-era spell tables, not the retail ones.
- New Classic+ spells (e.g. `1282503`) have no entries yet and need identification.

**Correction (2026-09-29, live bug report):** the "spell IDs are plain" conclusion
is not universal. Mid-fight in restricted content, the target unit's
`UNIT_SPELLCAST_START` spell ID came back **SECRET** (BugSack locals showed
`spell=<secret number>`; the handler's `noreset_swing_spells[spell]` lookup raised
"attempted to index a table that cannot be indexed with secret keys"). The 4.3
probe only listened to `UNIT_SPELLCAST_SUCCEEDED` during one player run — payload
secrecy differs per event and/or per unit: at minimum `START` on the target is
secret mid-fight while `SUCCEEDED` read plain in the earlier session (the player's
`SUCCEEDED` may stay plain, matching the two-tier pattern in 4.2; unverified).

All `UNIT_SPELLCAST_*` handlers now route the payload spell ID through
`ResolveSecret(spell, nil)` (no cached fallback exists for an event payload):
a secret ID degrades to "unknown spell" — cast-state flags still update
(`casting` is hoisted out of the spell guard in `UNIT_SPELLCAST_START` so the
cast-based swing reset still fires), the spell-ID list lookups are skipped.
Re-probe: run the 4.3 listener against `UNIT_SPELLCAST_START` for both `player`
and `target`, mid-fight and out, and record which event/unit pairs go secret.

### 4.4 Native swing timer APIs (C_SwingTimer) — discovered via `/api search swing`

**Recheck 2026-09-25 (pre-filing verification):** `/dump C_SwingTimer` shows exactly
the two baseline functions; `/api search swing` returns the identical 11 matches —
no new events or functions since the first survey. The API surface is unchanged;
the in-game reports and Discord drafts file as written. Additional recheck probes:
vararg capture confirms the `PLAYER_SWING` payload is still exactly
`(swingDuration, swingType)` — no new fields; registering `PLAYER_SWING_UPDATE`
fails with "Attempt to register unknown event" (definitively nonexistent, versus
restricted events which register silently-false — the two refusal modes are
distinguishable); `/api dump <System>` returns "No System found" on this client —
namespace `/dump` + `/api search` is the working enumeration method.

Blizzard's built-in swing timer is backed by an addon-facing API system. Confirmed
present on the Forever beta via the in-game `/api` documentation browser
(11 matches for "swing"):

| API | Signature / payload | Notes |
|---|---|---|
| System | `C_SwingTimer` | The whole namespace |
| Event | `PLAYER_SWING` → `swingDuration, swingType` | The swing event proper; registered as `PLAYER_SWING` (community PR EllesmereUI #2128 uses it for main-hand, off-hand and ranged bars) |
| Event | `PLAYER_SWING_RANGE_UPDATE` → `swingType, isInRange, checksRange` | Range-state tracking. **Verified behavior: fires exactly once, at the moment `C_SwingTimer.EnableRangeCheck(swingType, true)` is called — a single initial state push `(0, false, false)` — and then never again.** Registration alone produces no events; silent through melee and ranged combat; no fires observed on range transitions (tested walking in/out). Query `IsTargetWithinSwingRange(0)` returned nil without a target; in-range result still untested. Reported back to the dev, who asked "check when it fires" — likely probing suspected broken event wiring |
| Function | `C_SwingTimer.EnableRangeCheck(swingType, enable)` | Toggles the range checking |
| Function | `C_SwingTimer.IsTargetWithinSwingRange(swingType)` | Query current range state |
| Enums | `Enum.PlayerSwingType` = { MainHand=0, OffHand=1, Ranged=2 } (dumped live) + `EditMode*SwingTimer*` enums | Maps 1:1 to the library's `mainhand`/`offhand`/`ranged` identifiers |

Supporting infrastructure from `/api search duration` (215 matches):

- `C_DurationUtil.CreateDuration()`, `C_DurationUtil.CreateDurationTextBinding()` —
  the 12.x **duration object** system: secret-safe time spans with methods such as
  `SetTimeFromStart(startTime, duration, modRate)`, `SetTimeFromEnd(endTime, duration)`,
  `SetTimeSpan(startTime, endTime)`, `GetRemainingDuration()`, `GetElapsedDuration()`,
  `GetRemainingPercent()`, `HasExpired()`, `HasSecretValues()`, `Reset()`, clock
  objects (`LuaDurationClockObjectAPI` / manual clocks).
- Widgets accept duration objects directly (e.g. `Cooldown:SetCooldownFromDurationObject`,
  text bindings for font strings) — this is how secret timings are rendered without
  addons ever doing arithmetic on raw numbers.
- Text rendering config surface: `DurationTextBindingColorOptions`,
  `DurationTextBindingFormatComponent`, `DurationTextBindingFormatOptions`,
  `Enum_DurationTextBindingProperty`, and `Enum_DurationTimeModifier` (the `modifier`
  argument on duration getter methods) — what consumers use to render "1.2s"-style
  swing text from a duration object without reading the numbers.
- Community reference implementation: EllesmereUI PR #2128 — "Forever-native
  PLAYER_SWING event and duration bindings for main-hand, off-hand, and ranged bars",
  event-driven, hooks only.

Implications for this library:

- **Event-accurate player swing detection is possible in Forever** — the CLEU loss is
  not fatal for the player unit; `PLAYER_SWING` replaces `SWING_DAMAGE`/`SWING_MISSED`.
- ~~**`swingDuration` is most likely a duration object**, not a plain number~~ —
  disproven at runtime (section 4.5): it is a plain number, readable even in
  restricted content. The library's numeric contract (speed/expiration/lastSwing
  numbers) holds everywhere; the duration-object infrastructure is not needed.
- **Player-only**: `PLAYER_SWING` has no target variant. The library's target swing
  tracking (`UnitSwingTimerInfo("target", ...)`, `UNIT_SWING_TIMER_*` for target) has
  no Forever data source and must degrade gracefully or stay unpopulated.
- ~~`Enum.PlayerSwingType` values must be dumped~~ — resolved (section 4.5):
  MainHand=0, OffHand=1, Ranged=2.
- Reset/clip logic still needs the `UNIT_SPELLCAST_*` path (spell IDs are plain,
  section 4.3) — `PLAYER_SWING` gives swing anchors; casts give resets.

### 4.5 `PLAYER_SWING` runtime payload (live-verified)

Registered from addon code (works; fired repeatedly during auto-attacks) and captured
in combat via a listener. Observed payload for a two-handed paladin:

| Payload field | Observed | Meaning |
|---|---|---|
| `swingDuration` | `3.4` — a plain **number** (not a duration object; a probe assuming `HasSecretValues()` errored with "attempt to index a number value", proving the type) | The weapon swing speed — identical to `UnitAttackSpeed("player")` at the same moment |
| `swingType` | `0` | `Enum.PlayerSwingType.MainHand` |
| Hunter follow-up | `swing: 2, 2.0910000801086` — plain number, no `SECRET` branch | Auto Shot fires the event with `swingType = 2` (Ranged) and the ranged weapon speed as `swingDuration`. Ranged coverage confirmed; payload plain in the tested context |
| Dungeon mid-fight (paladin) | `swing: 0, 3.40000000953674` (repeated) — plain number | **Payload stays plain during active restrictions** — at the same moment `UnitAttackSpeed("player")` returned SECRET. The event is the sanctioned, always-readable channel; the raw stat APIs are what get locked down |
| Full combat sequence (paladin, 2.4s weapon) | One `swing: 0, 2.4000000953674` per completed auto-attack, interleaved with a busy `COMBAT_TEXT_UPDATE` stream (AURA/ABSORB/ENERGIZE/BLOCK/MISS/DAMAGE) | Cadence and reliability confirmed: one event per swing, stable payload, coexists with the combat-text listener. Confirms the parry handler must filter to `"PARRY"` only — CT fires many times per second in real combat |

The event therefore provides both the anchor (swing occurred) and the duration (full
weapon speed) in one payload — exactly the inputs `Unit:SwingStart(hand, now)` needs:
`expirationTime = swingTime + swingDuration`. No `UnitAttackSpeed` read, no
`UnitRangedDamage` read, no CLEU required for the player's swing cycle.

Secrecy verdict (final probe, mid-fight in a dungeon): `swingDuration` stayed a
**plain number** while `UnitAttackSpeed` was secret at the same time. The Forever path
is therefore fully event-accurate with the library's normal numeric contract
(`speed`/`expirationTime`/`lastSwing` as numbers) — no duration-object pass-through
needed. The secret guards (section 8) remain as crash-proofing for the legacy
`UnitAttackSpeed`/`UnitRangedDamage` reads.

## 5. Impact map on LibClassicSwingTimerAPI.lua

| Code path | Lines | Impact in Forever |
|---|---|---|
| Flavor detection | 17–27 | `isRetail = true` in Forever (project ID 1). Wrong tables (`:1421+`), wrong clip logic (`:176`, `:552`, `:676`), no Classic ranged handling |
| CLEU registration | 746 | Silently refused; `COMBAT_LOG_EVENT_UNFILTERED` handler at `:354` never runs. No `SWING_DAMAGE`/`SWING_MISSED` detection, no parry haste (`:358–377`), no aura tracking (`:391`), no ranged resets via CLEU (`:404`) |
| `Unit:SwingStart` | 89–159 | `UnitAttackSpeed`/`UnitRangedDamage` reads and subsequent arithmetic/comparisons error mid-fight when values are secret |
| `lib:UNIT_ATTACK_SPEED` | 430–498 | Same — every comparison/multiplier against fresh reads errors when secret |
| `lib:PLAYER_TARGET_CHANGED` | 308–353 | `UnitAttackSpeed("target")` errors on mid-fight retarget in instances |
| Feign Death watcher | 601–609 | Calls nil global `GetSpellCooldown` → hard Lua error on first FD cast (any flavor path, retail 11.x+ and Forever) |
| `UNIT_SPELLCAST_*` handlers | 539–745 | Events fire, but the payload spell ID can be **secret** mid-fight (2026-09-29 live error, target `UNIT_SPELLCAST_START`); handlers now guard the spell ID — see the 4.3 correction. Next-melee anchoring via `next_melee_spells` still works when the ID is readable |
| `PLAYER_ENTER_COMBAT` offhand start | 700–710 | Functional; uses cached/secret-guarded reads needed |
| Tooltip ranged-speed scan | 184–216 | Item data is not combat info; expected to remain plain (unverified in combat) |
| `WeakAuras.ScanEvents` forwarding | ~763–789 | WeakAuras halted development before Midnight; moot on Forever |
| TOC `## Interface` | .toc line 1 | `120005, 100200` does not match `16001`; addon does not load in Forever at all |

Note on retail 12.0 (Midnight): the same findings apply to the existing retail support —
CLEU dead in restricted content, secret speeds mid-fight, FD global removed. Any Forever
fix should be designed so the retail path can share the same guards.

## 6. Design constraints (from AGENTS.md)

- Embedded library via LibStub; breaking changes to public API/events are forbidden.
- Any change to the Lua file bumps the LibStub `MINOR` version; TOC `## Version` and
  `CHANGELOG.md` `[Unreleased]` entries follow.
- Classic flavors (Era/BCC/Wrath/Cata/Mists) must keep current behavior unchanged.
- Spell lists must be verified against the correct expansion; do not blend conflicting
  lists; surface gaps rather than silently patching them.
- No test suite — verification is in-game; the fix must be testable with the probes in
  the appendix.

## 7. Solution options

### Tier 1 — correctness and crash-proofing (uncontroversial)

1. `isForever` detection from `GetBuildInfo()` (interface `16001` band, e.g.
   `interface >= 16000 and interface < 20000`; the `1.6.x` version string is a
   candidate but only Blizzard's future numbering knows). Route Forever to the
   Classic-era tables and classic swing behavior, not the retail branch.
2. Guard event registration: check the boolean returned by `RegisterEvent`; skip CLEU
   entirely on Forever (and tolerate refusal on retail 12.x).
3. Feign Death compat shim: `C_Spell.GetSpellCooldown(5384)` on clients where the old
   global is gone (`info.isEnabled`/`info.isActive` are non-secret), old three-return
   global on classic flavors. Fixes a guaranteed error on retail 11.x+ and Forever.
4. `issecretvalue()` guards on `UnitAttackSpeed`/`UnitRangedDamage` reads: when secret,
   keep the last cached speed and skip recalculation instead of erroring. Speeds
   captured out of combat stay usable mid-fight.
5. TOC: add the Forever interface line so the addon loads there.

### Tier 2 — Forever swing behavior (product decision)

Original premise ("without CLEU there is no event for melee swings at all") was
disproven by the discovery of `C_SwingTimer` / `PLAYER_SWING` (section 4.4). Options:

- **(a) Partial mode**: ship next-melee anchoring (Heroic Strike/Raptor Strike/Maul
  already call `SwingStart` on cast success at `:545`), combat-start offhand logic, and
  speed-cached estimates. Timer runs in bursts for next-melee classes; never tracks
  plain auto-attack cycles. Documented as degraded.
- **(b) Tier 1 only**: Forever loads cleanly, no errors, timer mostly inert in
  restricted content. Revisit when Blizzard's API surface evolves.
- **(c) No Forever interface line**: addon does not load in Forever yet.
- **(d) Forever-native mode (new, superseding (a))**: build the Forever path on
  `PLAYER_SWING` + `Enum.PlayerSwingType` for the player's three swing timers (payload
  verified: plain-number swing speed + hand type, section 4.5), keep the
  `UNIT_SPELLCAST_*` ID tables for resets/clips, and expose the swing via the library's
  event system with the normal numeric contract where values are plain. Target-unit
  tracking stays unsupported on Forever and the API must say so.

**Recommendation: Tier 1 + (d).** All payload unknowns are resolved (section 4.5 —
plain numbers even mid-fight in restricted content), so the full numeric contract holds
and no pass-through fallback is needed. The complete implementation spec is in
section 8; it is **pending maintainer approval — nothing has been applied** to
`LibClassicSwingTimerAPI.lua` (exploratory edits were reverted; working tree is at
MINOR 32).

## 8. Implementation plan (spec — pending approval, not yet applied)

**Architecture decision — single file, no dedicated Forever script.** The
Forever-specific code (~100–120 lines: detection, `PLAYER_SWING` handler,
registration gating, FD shim, rescale skip, `FAILED_QUIET` gate, seven secret
guards) stays in `LibClassicSwingTimerAPI.lua`: (a) the library is distributed as
an embedded file list — a new file forces every downstream addon to update its
embed manifest, a breaking change to the ecosystem for zero functional gain;
(b) most Forever code is small conditionals inside shared functions that cannot
live in a separate file without restructuring the internals used by every current
classic consumer (highest regression risk on the flavors with real users);
(c) AGENTS.md documents the single-file layout. The `PLAYER_SWING` handler and
Forever registration go in a visibly delimited, commented "WoW: Forever" block.
Revisit triggers for a future split: Forever code growing past a few hundred
lines (e.g., `PLAYER_SWING_UPDATE` + target attribution + duration-object support
all landing), Forever spell tables diverging materially from classic-era ones,
or Forever launching with a stable API making a clarity-driven split worth a
coordinated major version.

Single release: LibStub `MINOR` 32 → 33, TOC `## Version: 2.1.6` → `2.2.0`, changelog
entries under `[Unreleased]`. Line numbers refer to the current working tree (MINOR 32).
Classic flavors must show zero behavior change (`issecretvalue` is nil there, so every
guard short-circuits false).

### 8.1 Detection, cooldown shim (insert after line 15, before `local isRetail` at 17)

```lua
local issecretvalue = issecretvalue -- present on 12.x clients and WoW: Forever; nil on classic clients

-- The GetSpellCooldown global was removed from 11.x+ clients (retail and WoW: Forever).
-- Fall back to C_Spell.GetSpellCooldown (table return) where the old global no longer exists.
local GetSpellCooldownCompat
if GetSpellCooldown then
	GetSpellCooldownCompat = GetSpellCooldown
elseif C_Spell and C_Spell.GetSpellCooldown then
	GetSpellCooldownCompat = function(spell)
		local info = C_Spell.GetSpellCooldown(spell)
		if not info then
			return nil, nil, nil
		end
		return info.startTime, info.duration, info.isEnabled and 1 or 0
	end
end

-- WoW: Forever shares the mainline client (WOW_PROJECT_ID == 1) but runs Classic rules.
-- The project id cannot distinguish it; use the interface build range instead.
local _, _, _, interface = GetBuildInfo()
local isForever = interface >= 16000 and interface < 20000
```

Line 17 becomes: `local isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and not isForever`
(the retail branch at `:1421` must not match on Forever).

### 8.2 Flavor grouping (line 23)

`local isClassicOrBCCOrWrathOrCata = isClassic or isBCC or isWrath or isCata or isForever`

Forever then follows classic clip behavior (`:176`), equipment-changed ranged handling
(`:686+`), and the FD ranged reset (`:601+`) — correct for a Classic-rule-set client.

### 8.3 Spell tables (line 807)

`if isClassic then` → `if isClassic or isForever then` — Forever loads the Classic-era
tables (classic-era IDs verified live: Rend 678, SoR 20288, Judgement 20271,
Flash of Light 19750, Attack 6603; ranged_swing 75/3018/2764/5019 unverified on
Forever — see open items).

### 8.4 New handler `lib:PLAYER_SWING` (insert before `lib:UNIT_ATTACK_SPEED`, line 430)

```lua
function lib:PLAYER_SWING(_, swingDuration, swingType)
	-- WoW: Forever native swing event. Payload verified on the beta: swingDuration is
	-- the weapon swing speed as a plain number (readable even in restricted content,
	-- where UnitAttackSpeed returns secret values); swingType is
	-- Enum.PlayerSwingType (MainHand=0, OffHand=1, Ranged=2).
	if not isForever then
		return
	end
	if issecretvalue and issecretvalue(swingDuration) then
		return -- swing anchor without a usable duration; do not guess one
	end
	local hand
	if swingType == 0 then
		hand = "mainhand"
	elseif swingType == 1 then
		hand = "offhand"
	elseif swingType == 2 then
		hand = "ranged"
	else
		return
	end
	local unit = self.player
	if not unit then
		return
	end
	-- Cache the event-provided speed first so the UnitAttackSpeed reads inside
	-- SwingStart fall back to it when they return secret values.
	if hand == "mainhand" then
		unit.firstMainSwing = true
		unit.mainSpeed = swingDuration
	elseif hand == "offhand" then
		unit.firstOffSwing = true
		unit.offSpeed = swingDuration
	else
		unit.rangedSpeed = swingDuration
	end
	unit:SwingStart(hand, GetTime(), false)
end
```

Design notes: `PLAYER_SWING` replaces the CLEU `SWING_DAMAGE`/`SWING_MISSED` anchor —
main-hand, off-hand and ranged in one event. Pre-caching the speed keeps the existing
`UnitAttackSpeed` reads in `SwingStart` correct even when they return secrets (via the
8.5 guards). Resets/clips keep flowing through the `UNIT_SPELLCAST_*` handlers (spell
IDs verified plain). Parry haste and target-unit tracking have no Forever data source
and are simply absent — documented, not approximated.

### 8.5 Secret-value guards (fall back to cached speed; consolidated)

All secret reads go through one file-scope helper (simplify pass, applied with the
implementation):

```lua
local function ResolveSecret(value, fallback)
	if issecretvalue and issecretvalue(value) then
		return fallback
	end
	return value
end
```

Call sites (nine): `Unit:SwingStart` main/off/ranged; `UNIT_ATTACK_SPEED` main/off
+ ranged; `PLAYER_ENTERING_WORLD` ranged; `PLAYER_TARGET_CHANGED` ranged; the Feign
Death cooldown anchor (`ResolveSecret(start, GetTime())`). `PLAYER_ENTERING_WORLD`
and `PLAYER_TARGET_CHANGED` main/off use a separate dual-value guard (if either
value is secret, nil both so the existing `or 3` / `or 0` defaults apply), and
`lib:PLAYER_SWING` keeps an explicit early-return on a secret duration (no
fallback exists for an anchor). Assumes `issecretvalue(nil) == false` — verify
in-game with `/run print(issecretvalue(nil))` (release checklist item 10); the
pre-simplification code already relied on this at one call site, so the pass
unified an inconsistency rather than introducing a new assumption.

Forever rescale gate (open item 16, implemented alongside the guards): the three
`UNIT_ATTACK_SPEED` rescale conditions carry `and not isForever` — in-flight swings
are never rescaled on Forever (verified live); `PLAYER_SWING` re-anchors with the
new speed at the next swing.

When the fallback value equals the cached one, the `~= speed` comparisons make the
update a no-op — restricted-content reads degrade silently instead of erroring.
Retail 12.x gets the same crash-proofing for free.

### 8.6 Feign Death watcher (lines 601–609)

`local start, _, enabled = GetSpellCooldown(spell)` →
`local start, _, enabled = GetSpellCooldownCompat and GetSpellCooldownCompat(spell)`,
and before the `SwingStart(..., start, ...)` calls:
`if issecretvalue and issecretvalue(start) then start = GetTime() end`
(cooldown `startTime` is a secret in restricted content; using it as an anchor would
error). Classic flavors: compat resolves to the old global, guard short-circuits —
identical behavior.

### 8.7 Event registration (line 746+)

```lua
if not isForever then
	frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
if isForever then
	frame:RegisterEvent("PLAYER_SWING")
end
```

CLEU is skipped on Forever (registration is silently refused there anyway — registering
an unknown event would throw, so `PLAYER_SWING` stays Forever-gated until open item 11
confirms whether retail 12.x has it).

### 8.8 TOC, versioning, changelog

- `## Interface: 120005, 100200, 16001` and `## Version: 2.2.0`; LibStub `MINOR = 33`.
- Changelog `[Unreleased]`:
  - **Added**: WoW: Forever support — detected via interface build range (project id
    is unreliable), routed to Classic-era spell tables and swing behavior; swing
    detection via the native `PLAYER_SWING` event (payload verified readable in
    restricted content); CLEU not registered (the client refuses it).
  - **Changed**: `issecretvalue()` guards on all weapon-speed reads (12.x restriction
    system) — cached speeds used instead of mid-fight errors; benefits retail 12.x.
    Feign Death watcher now uses a `GetSpellCooldown` / `C_Spell.GetSpellCooldown`
    compatibility shim (old global removed in retail 11.0).

### 8.9 In-game verification checklist (blocking for release)

**Progress 2026-09-25 (library build from feature/forever-support, live on the
beta):** loads and initializes on Forever (LibStub instance, `SwingTimerInfo`
returns sane speed/expiration/lastSwing with correct expiry arithmetic). Core
swing loop verified (START/STOP per cycle, correct payloads). Cast-reset verified
through the library (FoL mid-cycle: STOP+START at cast completion, expiry =
completion + weapon speed). Instant no-reset verified (Judgement: cadence
undisturbed). SotC mid-swing verified: in-flight swing completed on the old
schedule, NO mid-swing UPDATE (rescale gate works), completing swing reported
the new speed 1.714, new cadence from the next swing. Weapon-swap reset verified
(STOP + fresh START with the new weapon speed 3.4, expiry = swap time + new
speed). `issecretvalue(nil)` verified `false` — the ResolveSecret assumption
holds. Hunter ranged verified live: correct speed 2.091, START/STOP per shot,
and the FAILED_QUIET movement-cancel UPDATE chain works. **Found and fixed during
test 8: double ranged anchor** — the same Auto Shot fired both `PLAYER_SWING`
and SUCCEEDED 75, producing identical STOP/START pairs per shot (state-safe but
would double-count for consumers edge-detecting STOP). Fix: `ranged_swing`
SUCCEEDED anchor gated off on Forever (`and not isForever`) — `PLAYER_SWING` owns
the ranged cycle, `FAILED_QUIET` owns movement cancels. Caveat to watch: wand
users (`Shoot Wand 5019`) — assumed covered by PLAYER_SWING type 2 like other
ranged attacks; verify at convenience.
**Recast-after-FAILED_QUIET measured on the beta (2026-09-25):** the engine
retries the auto shot every ~0.5s while moving (consecutive FAILED_QUIET events
0.43–0.56s apart), and the shot lands ~0.5s after the last cancel (measured
0.43s and 0.54s in two clean trials) — NOT the classic `0.5 + castTime` model
(≈0.87s for a 2.091 bow). Auto shot casts fire no UNIT_SPELLCAST_START on this
client (engine-internal). **Fix applied:** the FAILED_QUIET handler predicts
`now + 0.5` on Forever and keeps `now + 0.5 + autoShotCastTime` on classic
flavors. Re-test: after a movement cancel the UPDATE expiration should now
match the real shot landing (~0.5s).
**Remaining: dungeon mid-fight (secret guards under load), hunter re-test after
the anchor fix (expect one START per shot), dual-wield off-hand, Classic Era
regression.**

**Dungeon mid-fight verified (2026-09-25):** timers ran accurately through a full
pull where `UnitAttackSpeed` is secret — steady 2.428s cadence from the
`PLAYER_SWING` cache, zero errors (the ResolveSecret guard surface held under
load). The capture also verified mid-combat: a cast reset (one 1.45s gap =
mid-cycle completion restarting a full weapon speed out) and a weapon swap
(speed 2.428 → 3.400 with the new cadence from the next swing). Hunter re-test
after the anchor/recast fixes verified (single anchors, ~0.5s recast model,
8 measurements). **Remaining: dual-wield off-hand, Classic Era regression,
optional wand check.**

1. Classic Era regression: melee a dummy — timers behave exactly as 2.1.6.
2. Forever open world: swings fire `UNIT_SWING_TIMER_START` with correct
   speed/expiration; hunter Auto Shot drives the ranged bar (`swingType=2`).
3. Forever dungeon mid-fight: no Lua errors; timers keep running (payload plain).
4. Forever Feign Death: no error on cast; swing resets when the FD cooldown starts.
5. Retail 12.x: addon loads, no FD error; timers degrade silently in restricted content.
6. Dual-wield on Forever: off-hand fires `PLAYER_SWING` with `swingType=1` (open item 10).
7. ~~Hunter on Forever: `START_AUTOREPEAT_SPELL`/`STOP_AUTOREPEAT_SPELL`~~ —
   **verified** (both fire on toggling Auto Shot; `isShooting` is maintained, the
   FAILED_QUIET gate extension is fully viable). Remaining sub-check: moving
   mid-Auto Shot reschedules the ranged timer without errors (release-blocking
   in-game test of the patched handler).
8. ~~Non-restricted supporting events on Forever~~ — **verified**:
   `PLAYER_EQUIPMENT_CHANGED` (slots 16/17, payload hasItem) and
   `PLAYER_ENTER_COMBAT`/`PLAYER_LEAVE_COMBAT` (weapon swap drops and re-enters
   combat, first swing with the new weapon ~2.8s later at the new cadence).
9. Launch-day verification (blocked by the beta level cap): Feign Death mid-cycle
   on a hunter — does the instant-with-reset family apply on Forever? Until then
   the classic-table default ships with the documented one-cycle-transient risk
   (open item 15).
10. One-liner: `/run print(issecretvalue(nil))` — must print `false` (the
    `ResolveSecret` helper and the dual guards rely on nil not being secret;
    section 8.5).
11. Death reset (Phase 1, applied 2026-09-28): die in the open world, accept an
    in-place resurrection — `PLAYER_DEAD` should fire `UNIT_SWING_TIMER_STOP` once
    per active hand and the next swing should start a clean cycle. Run on Classic
    Era (all-client change) and on Forever.
    **Forever verified 2026-09-28 (hunter, listener macro on the lib callbacks):**
    died mid-swing-cycle (mainhand START at t=12978.4 on a 1.6 s dagger, ~0.3 s
    into the swing) — `[You died.]` followed immediately by a single
    `UNIT_SWING_TIMER_STOP player mainhand`; the ranged timer had already expired
    ~11 s earlier and correctly produced no second STOP. Post-resurrection
    combat (t=13059+) shows clean ranged cycles (2.091 speed, expiry = start +
    speed) and clean melee cycles (~1.55–1.6 s cadence), no visible Lua errors.
    This capture also closes the Phase 2 ranged-sanity glance (bar unchanged,
    correct 2.091 anchors after the source switch). **Remaining: Classic Era
    death-reset run + Classic Era regression.**

### 8.10 Parry haste on Forever (decision: B + D — passive self-correction plus the
API request; option A/E remains available as an opt-in if real-time haste is wanted
before Blizzard acts)

Mechanic: when a unit parries an incoming attack, its next main-hand swing is
shortened by 40% of weapon speed, floored at 20% of weapon speed remaining.

**Probe update 2026-09-30 (build 70124) — the "no direction discriminator" premise
is disproven; option B+D superseded by an exact path.** `UNIT_COMBAT`, the
2004-era defender-anchored combat-feedback event, was never probed here —
`/api search parry` cannot surface it (neither its name nor its payload contains
a searchable "parry" keyword; the event predates the documented-API system). It
is live on the Forever client: `RegisterEvent` returned true, and it fired
mid-combat with plain unitIDs. The capture: a player parry fired `player` +
`targettarget` (the same unit named by two tokens, identical timestamp), while
an outgoing dodge fired the mob's `nameplate1` + `target` tokens only —
direction IS the unitID, and the event fires once per unit token, so filtering
`unitTarget == "player"` catches exactly one event per defensive parry (pet
parries fire `pet`, filtered out). Same capture: `GetCurrentCombatTextEventInfo()`
returned nil — not secret values — for PARRY on this build; the generated docs
mark it `SecretReturns`, so any future payload would be classified, and the
Blizzard ask stays "populate the payload or add `PLAYER_PARRY`". Applied the
same day: `lib:UNIT_COMBAT` handler (player + PARRY filter, Forever-only
registration) and the parry math extracted into `lib:ApplyParryHaste`, shared
with the classic CLEU path (classic behavior byte-identical). Remaining
verification (M1 script B3): a direct outgoing-parry capture (the outgoing-dodge
analog is captured; the mob did not parry during the probe window) and a dungeon
mid-fight run. Side finding: every player-defender `UNIT_COMBAT` action
(WOUND/DODGE/PARRY/BLOCK) marks an incoming attack attempt — a readable
mob-swing-cadence signal with no combat log, usable for a future target-timer
lead (single-attacker fights; the schoolMask payload can separate melee from
spells).

**In-game result 2026-09-30 (build 70124, bar rig) — the flat parry formula is
rejected; the tiered engine rule applied.** First live run of the
`UNIT_COMBAT` handler: detection and the mid-swing UPDATE work (green stack
fired, the bar re-anchored), but the bar parked early — stuck full for up to
~40% of the weapon speed before the engine's actual hastened swing landed.
That is the flat formula over-hastening early parries: it reduces the
remaining swing by 40% of weapon speed unconditionally, while the engine caps
parries with more than 60% of the swing remaining at 60% remaining. The
earlier captures already fit the tiered rule (the 2.0 s gap on a 2.4 s weapon
is impossible under the flat reduction, which snaps every effective parry to a
1.44 s gap); the bar-parked-early observation is the direct confirmation. The
engine rule now implemented in `ApplyParryHaste` (all clients — the classic
CLEU branch was unreachable before 2.2.0, so the flat rule had never been
exercised against the engine; the Era regression pass should cover it):
more than 60% of the swing remaining → the swing lands at 60%; between 20%
and 60% → reduced by 40% of weapon speed, floored at 20%; 20% or less
remaining → no effect (a parry never delays the swing — the flat rule's
tail floor pushed the modeled swing later, which would also have flashed the
interrupt feedback on an ordinary swing via the START-while-active path).

**Second capture 2026-09-30 (raw-swing probe, build 70124) — engine haste
observed WITHOUT a player-PARRY event.** 17 `PLAYER_SWING` anchors on a 2.4 s
weapon: steady 2.36–2.42 s cadence, two non-anchoring extra swings (+0.276 s,
+0.735 s — no parry rule can produce a sub-1.44 s gap and the cadence continued
from the previous anchor; the §9 item 17 mystery signature, consistent with an
extra-attack proc), and two parry-hasted anchors (+1.452 s and +1.686 s, both
re-anchoring; both fit the tiered rule — band 1 with a parry at ~0.01/~0.25 s
into the swing, or band 2 at ~0.97/~1.21 s; the 1.686 s gap is
flat-band-1-impossible, further confirming the tiered formula). Zero `player
PARRY` lines in the window. Two candidate explanations: (A) incoming player
parries that the engine hastened but `UNIT_COMBAT` did not dispatch (coverage
gap), or (B) attacker-side haste — the player's attack being parried hastening
the player's own next swing, a deviation from the classic defender-only rule
(the defender's tokens would have fired PARRY and the player filter correctly
ignored them). The implementation stays safe either way — it can only
under-report: a missed haste leaves the bar un-hastened until the early swing
re-anchors it, bounded by one cycle, never wrong-direction. Discriminating
probe (M1 script B3 item 3): log every PARRY token alongside the swings — a
hasted anchor with `PA <mobtoken>` in the same frame as the *previous* swing is
attacker-side haste (B); `PA player` mid-cycle is an unreported incoming parry
(A); no PARRY at all is a third mechanism. If (B) is confirmed, the Forever
path would additionally need the outgoing-parry anchor-coincidence signal
(a PARRY on any token in the same frame as the player's own swing anchor).

- **The math is fully portable.** The block at `:358–377` only uses values the library
  already holds as plain numbers: `defender.mainExpirationTime`, the cached
  `defender.mainSpeed` (on Forever, refreshed by `PLAYER_SWING`'s plain payload), and
  `GetTime()`. No restricted API involved — works in restricted content as-is.

Verified probe facts (all live):

- The only parry signal is `COMBAT_TEXT_UPDATE` with `combatTextType == "PARRY"`
  (fires for DODGE/MISS/BLOCK/etc. as well). No dedicated event exists
  (`/api search parry` shows only stat-chance functions).
- It fires **in both directions** (player parries an incoming attack; a mob parries
  the player's attack) with **identical payloads** — the event carries only the type
  string; `GetCurrentCombatTextEventInfo()` returns nothing; the CombatText system
  exposes zero functions. **No direction discriminator exists.**
- It fires independently of floating-combat-text settings, and is not throttled.
- `PLAYER_SWING` fires per swing attempt, including parried/dodged/missed swings —
  an outgoing parry coincides with the player's own swing anchor (observed 0.07s
  apart); incoming parries do not align with swing anchors.
- Parry haste is live in the engine: observed swing gaps of ~2.0s and ~0.98s
  (double parry to the 20% floor) on a 2.4s weapon.

Historical context from the wiki (warcraft.wiki.gg `Event:COMBAT_TEXT_UPDATE` and
`API:GetCurrentCombatTextEventInfo`, via mirrors — the wiki blocks our fetch):

- The event payload is documented as `combatTextType` only, with
  `GetCurrentCombatTextEventInfo()` as the payload accessor — matches the live
  probes.
- The accessor **historically returned data**: xCT reads three values from it for
  `DAMAGE`, and old WoWInterface threads show it returned the *ability* for
  `SPELL_ACTIVE` reactive messages — Revenge (player dodged/parried/blocked,
  defensive) vs Overpower (target dodged the player's attack, offensive). Direction
  information has existed inside the combat text system since vanilla.
- Consequence for the request: on the Forever beta the accessor returns nothing
  (verified for `PARRY`, `PInfo = { [1]=true }`). The ask is therefore not "design
  a new API" but "wire up the payload accessor that has existed since 1.12" — a
  sharper, more grantable request. `CombatTextSetActiveUnit(unit)` also exists,
  anchoring the event to a watched entity.

Constraint: haste must apply only when the *player* parried. A wrong-direction
application shortens the bar incorrectly — the one error the library's accuracy
contract cannot absorb.

Options:

| # | Option | Accuracy | Complexity | Risk |
|---|---|---|---|---|
| A | Real-time, swing-correlation filter: on `PARRY`, skip if the player's own swing anchor (main **and off** hand — a dual-wielder's off-hand parry coincides with the off-hand's `PLAYER_SWING`) is <0.15s old; else apply haste | ~94% of incoming parries hastened; never wrong-direction with dual anchors | Moderate: handler + filter + shared `ApplyParryHaste` refactor | Heuristic on an event not designed for this; magic-number window; timing assumptions backed by three noisy captures |
| B | Passive self-correction: no parry handler; every `PLAYER_SWING` re-anchors, so a hastened swing that lands early simply starts the next cycle from reality | Never wrong; blind between a parry and the next swing (bar shows un-hasted time, bounded by one swing) | Zero — already implicit in the `PLAYER_SWING` design | None |
| C | Retroactive adjustment on early swings | Same output as B — nothing forward-looking to adjust | Pointless bookkeeping | Reject |
| D | Request a proper API from Blizzard (`PLAYER_PARRY` or a direction field) via the WoW UI Discord / Forever beta feedback | Exact, when it lands | A forum post; Blizzard has been responsive to addon-API requests throughout Midnight and the Forever beta | Timing unknown |
| E | Option A behind an opt-in consumer flag | Same as A | Small | Same as A, with consumer consent |

Recommendation: **B + D for the first Forever release.** B is the honest fit for the
library's accuracy contract — never wrong, zero code, error bounded and
self-correcting. D costs a forum post and would make the mechanic exact. A is solid
engineering but rests on timing assumptions and a heuristic; if real-time parry haste
is wanted before Blizzard acts, ship it as E (opt-in) with the dual-anchor filter and
the documented ~6% one-sided miss rate.

Implementation notes:

- Both options need the shared refactor: extract the parry math from the CLEU handler
  (`:358–377`) into `lib:ApplyParryHaste(unit)` — classic CLEU behavior byte-identical.
- Option B registers nothing new; the `PLAYER_SWING` handler (8.4) already implements
  it. Document in the changelog that parry haste is not reflected mid-swing on Forever
  pending a proper API.
- Option A/E handler (dual-anchor filter; `lastMainSwing`/`lastOffSwing` are set by
  `SwingStart` on every swing or cast reset):

```lua
function lib:COMBAT_TEXT_UPDATE(_, combatTextType)
	if combatTextType ~= "PARRY" then
		return
	end
	local unit = self.player
	if not unit then
		return
	end
	-- Direction filter: an outgoing parry is the result of the player's own swing and
	-- coincides with that hand's PLAYER_SWING; haste belongs to the defender only.
	local now = GetTime()
	if now - (unit.lastMainSwing or 0) < 0.15 or now - (unit.lastOffSwing or 0) < 0.15 then
		return
	end
	self:ApplyParryHaste(unit)
end
```

- Registration for A/E (Forever-only):
  `if isForever then frame:RegisterEvent("COMBAT_TEXT_UPDATE") end` — only the player
  has a timer on Forever.

**D — API request draft (post to the WoWUIDev Discord — the addon-dev server
where Blizzard's UI team announces API changes and takes feedback;
invite `discord.com/invite/txUg39Vhc6`, or search "WoWUIDev discord invite" for a
current link via WoWInterface/r/wowaddons. Cross-post to the Blizzard "UI and Macro"
forum, and optionally the Forever beta in-game feedback tool):**

**Step 0 — read the `#bugs` channel first** (per the server FAQ, it lists known
Forever beta bugs). Two reasons: (a) avoid posting a request for something already
known/fixed; (b) several probe findings could be beta bugs rather than final
behavior — specifically check whether the instance-wide CLEU refusal, the
mid-fight secret weapon speeds in a normal dungeon (Blizzard's stated scoping is
encounters/M+ only), the silent movement-cancelled channel, and the empty
`GetCurrentCombatTextEventInfo()` are listed there. A "known bug" answer loosens
parts of the degradation design at launch.

**Step 1 — short question first** (invites dialogue, checks for an existing way or
a planned event, and gauges engagement before the long post):

> I work on porting a swing timer library to the Forever beta. Does anyone know
> if there's an addon-facing way to detect when the player parries?
> `COMBAT_TEXT_UPDATE` fires
> PARRY for both directions (you parry / your attack gets parried), but there
> seems to be nothing to tell them apart. The parry haste mechanic will be
> invisible without CLEU. (Keep the backticks: Discord italicizes the "TEXT"
> inside COMBAT_TEXT_UPDATE without them.)

**Discord response (2026-09-25, WoW UI Discord):** "C_SwingTimer exists on forever,
you should look at that and if something is mechanically missing from it's behaviour
you should report that." — validates the option (d) design (`PLAYER_SWING` is the
sanctioned path) and invites a gap report on the SwingTimer system itself. Parry
haste is exactly such a gap: the engine shortens the in-flight swing (measured
~2.0s and ~0.98s gaps vs a 2.4s weapon) but nothing in the system reports the
shortening — `PLAYER_SWING` only fires at completion.

**Step 2 — ask how to report** (the dev invited a report but didn't say where; ask
in the same thread before filing. Superseded in practice: filed via the in-game
beta tool instead):

> Will do — what's the best way to report it? In-game beta bug report, the `#bugs`
> channel here, or somewhere else?

The answer selects the channel *and* the format: a bug-report queue wants the formal
reserve version below; a casual channel wants the short gap-report draft.

**Step 3 — response to the dev in-thread** (short form, primary — as posted,
maintainer's final wording; the `PLAYER_SWING_UPDATE` proposal was dropped from
the message in favor of naming the gap and letting the in-game reports carry
the proposed shape):

> Thanks! I'm already building on `C_SwingTimer`, and `PLAYER_SWING` works great.
> Filed the reports in-game. Short version: the engine modifies in-flight swings
> (parry haste, mid-swing haste), but `PLAYER_SWING` only fires on completion so
> the current behavior is incomplete. Also missing swing reset on spell cast.

(Expanded form, if the thread asks for depth — reply to the "report what's
mechanically missing" message; leads with the one event that unlocks the most,
points to the filed in-game reports for the rest):

> Thanks — I'm building on `C_SwingTimer` already; `PLAYER_SWING` works great and
> drives the whole timer. Filed the in-game reports as suggested, but I don't
> expect anyone to spelunk every classic swing interaction, so the short version
> of what's mechanically missing:
>
> The engine can modify an in-flight swing — parry haste shortens it when the
> player parries (measured ~2.0s and ~0.98s gaps on a 2.4s weapon mid-fight),
> haste effects rescale it mid-swing — but `PLAYER_SWING` only fires when the
> swing completes, so none of that is visible to an addon until the next swing
> lands. A single `PLAYER_SWING_UPDATE` event carrying the refreshed swing state
> would cover all of it.
>
> The other in-game report is cast-completion swing resets (classic rule, resets
> with exceptions like Feign Death, no event for it). And if unit-targeted swing
> events are ever on the table — CLEU used to expose any unit's swings, so enemy
> swing timers were possible; `C_SwingTimer` being player-only is the last gap
> for that.

(Drop the last paragraph to keep it single-issue if preferred.)

**Step 4 — full request** (revised to the gap-report framing the dev invited; post as
a follow-up in the same thread):

> Following up on `C_SwingTimer`: I do use it — `PLAYER_SWING` is great and drives
> the whole timer. The mechanical gap I've hit is **parry haste**: when the player
> parries, the engine shortens the in-flight swing (measured ~2.0s and ~0.98s gaps
> vs a 2.4s weapon mid-fight), but nothing in the SwingTimer system reports the
> shortening — `PLAYER_SWING` only fires at swing completion, so the addon's bar
> can't reflect the haste until the next swing lands. A general mid-swing update
> event (e.g. `PLAYER_SWING_UPDATE` with the refreshed swing state) would cover
> it — and would also solve mid-swing haste changes, which have the same gap.
> For context, the only parry signal elsewhere is
> `COMBAT_TEXT_UPDATE` PARRY, which fires both directions (you parry / your attack
> gets parried) with nothing to tell them apart.

**Reserve version — formal write-up** (superseded by the gap-report draft above as
the first follow-up; post this expanded form only if the dev asks to "file it
properly" or wants the full detail. Its "Current behavior" section doubles as the
evidence summary):

> **API request: player-scoped parry event (or direction data on
> COMBAT_TEXT_UPDATE)**
>
> For context: I maintain LibClassicSwingTimerAPI, an embedded swing-timer
> library used by several addons and WeakAuras on the classic clients, and I'm
> porting it to the Forever beta.
>
> **Current behavior:** Since the combat-log restrictions, the only parry signal
> available to addons is `COMBAT_TEXT_UPDATE` with `combatTextType == "PARRY"`. It
> fires identically for both directions — the player parrying an incoming attack,
> and the player's own attack being parried — with no way to distinguish them: the
> event payload is only the type string, `GetCurrentCombatTextEventInfo()` returns
> nothing, and the CombatText system exposes no query functions. (Verified on the
> Forever beta, build 70009.)
>
> **The gap:** Parry haste — the next main-hand swing reduced by 40% of weapon
> speed, floored at 20% — has been a core melee mechanic since Classic.
> `PLAYER_SWING` tells us when a swing completes, but nothing tells an addon that
> an in-flight swing timer was hastened by a defensive parry. Swing-timer addons
> can no longer reflect this mid-swing; the information self-corrects only at the
> next swing.
>
> **Request:** A general mid-swing update event in the spirit of `PLAYER_SWING`,
> e.g. `Event.SwingTimer.PlayerSwingUpdate` with the refreshed swing state —
> covering both parry haste and mid-swing haste changes. A minimal alternative:
> populate `GetCurrentCombatTextEventInfo()` for `COMBAT_TEXT_UPDATE`, or add a
> direction/defender field to the event.
>
> **Why this fits the restriction philosophy:** it exposes only the player's own
> defensive action — the same information the default floating combat text already
> renders — with no enemy data, no hidden values, and no automation potential
> beyond what the built-in swing timer already provides. It restores parity with
> the built-in tool rather than creating a new capability.
>
> Thanks — `PLAYER_SWING` has been a great addition, and the ongoing API
> engagement during the beta is much appreciated.

Receipts to keep ready if a dev asks for evidence: the `C_CombatText` empty
namespace dump, `GetCurrentCombatTextEventInfo()` returning nothing
(`PInfo = { [1]=true }`), and the vararg capture showing the event carries only
the type string.

**In-game beta report — 255-character forms, split into two tickets** (separate
reports triage and fix independently; each gets its own character budget):

Report 1 — mid-swing updates / parry haste (250 chars, verified facts, can be
filed immediately):

> C_SwingTimer: no mid-swing update event. Engine shortens the swing when the
> player parries, but PLAYER_SWING only fires at completion and COMBAT_TEXT PARRY
> is direction-ambiguous. Suggestion: PLAYER_SWING_UPDATE (also covers mid-swing
> haste changes).

(233-char alternative keeping the Discord pointer instead of the haste clause:
"...direction-ambiguous. Request: PLAYER_SWING_UPDATE. Details: WoWUIDev Discord.")
A general update event closes two matrix gaps at once — parry haste AND the
mid-swing haste rescale — and maps onto the library's existing
`UNIT_SWING_TIMER_UPDATE` callback vocabulary.

Report 2 — cast reset (239 chars; assumes the rule is live — file only AFTER the
open item 15 cadence test; if the rule was removed, reword as a confirmation
question instead):

> C_SwingTimer: no swing-reset notification. Classic rules reset the swing timer on
> cast completion (with exceptions; some instants like Feign Death also reset).
> Built-in bar ignores casts; no event reports resets. Details: WoWUIDev Discord.

**In-game beta report — 255-character form, combined** (superseded by the split;
kept for reference):

> Swing timer: 2 classic mechanics missing from C_SwingTimer: parry haste (no
> mid-swing event; COMBAT_TEXT PARRY is direction-ambiguous) and swing reset on
> cast completion (built-in bar ignores casts). Details: WoWUIDev Discord.

(~225 chars — fits even if the title line counts toward the limit. If the tool has
separate title/description fields: title "Swing timer: missing classic mechanics",
body as above.)

**In-game beta report — full draft** (for a forum/long-form channel; covers
the two classic swing interactions absent from the built-in timer and the
`C_SwingTimer` events. Item 2 wording depends on open item 15 — verify the
reset-on-cast rule first):

> **Title:** Swing Timer: missing classic swing mechanics (parry haste, cast reset)
>
> The built-in swing timer and the `C_SwingTimer` events model only the steady
> auto-attack cycle. Two classic swing interactions appear to have no coverage,
> with no way for addons to track them:
>
> 1. **Parry haste / mid-swing updates** — the engine shortens the in-flight
>    swing after the player parries (measured ~2.0s and ~0.98s gaps vs a 2.4s
>    weapon mid-fight). `PLAYER_SWING` only fires on completion; the only parry
>    signal, `COMBAT_TEXT_UPDATE` PARRY, fires for both directions (player
>    parries / player's attack gets parried) with no payload to tell them
>    apart. A general mid-swing update event (e.g. `PLAYER_SWING_UPDATE` with
>    the refreshed swing state) would cover parry haste and also mid-swing
>    haste changes.
>
> 2. **Swing reset on cast completion** — classic rules reset the swing timer
>    when a cast-time spell completes, with specific exceptions that do not
>    reset (e.g. engineering bombs, Evocation, Volley), and specific instant
>    spells that DO reset (e.g. Feign Death). The built-in bar doesn't react to
>    casts and no event reports a reset, so a timer bar goes stale until the
>    next swing lands. Can the system reflect or report resets, including the
>    exceptions? (If the rule was removed in Forever, confirming that is
>    equally useful.)
>
> Context: porting a swing timer library (LibClassicSwingTimerAPI) from the
> classic clients; these two mechanics are the gap between an accurate timer
> and what `C_SwingTimer` currently exposes. Everything else — per-swing
> anchors across all three hands (including missed/dodged/parried swings),
> next-melee abilities, movement-cancelled auto shots — works well with
> `PLAYER_SWING` plus the `UNIT_SPELLCAST_*` events.

### 8.11 Swing-reset logic on Forever (verified — ports unchanged; open item 4)

The library's reset model has two paths in `UNIT_SPELLCAST_SUCCEEDED` (`:539+`):

1. **Explicit per-expansion lists**: `reset_swing_spells` (reset even when instant —
   Ghost Wolf, Feign Death, Noggenfogger), `noreset_swing_spells` (casts that must
   not reset — dynamite, Evocation, Volley), `next_melee_spells` (Heroic Strike/
   Cleave/Maul/Raptor Strike — cast success IS the swing), `pause_swing_spells`
   (Slam), `reset_swing_on_channel_stop_spells` (Rapid Fire).
2. **The generic `casting` flag**: `UNIT_SPELLCAST_START` (fires only for cast-time
   spells) sets `unit.casting`; on `SUCCEEDED`, `casting and not preventSwingReset`
   resets both hands. Covers every cast-time spell automatically — this is why
   cast-time spells need no table entries and the paladin-heal gap is benign
   (Flash of Light resets via this path).

Supporting behavior that must hold on Forever: interrupts/failed clear `casting`
without resetting; spell `6603` (Attack) excluded from resets; channel stop handled
per list.

Forever status:

| Piece | Status |
|---|---|
| `UNIT_SPELLCAST_SUCCEEDED` + plain classic-era IDs | **Verified** (19750, 20288, 20271, 6603 captured) |
| `UNIT_SPELLCAST_START` fires for cast-time spells only | **Verified** (dungeon capture: `START` + `SUCCEEDED` for Flash of Light 19750 and Holy Light 647; `SUCCEEDED` only for instants SoR 20288 / Judgement 20271 — no `START` on instants, so the generic `casting`-flag reset path behaves exactly like classic) |
| `UNIT_SPELLCAST_INTERRUPTED` / `UNIT_SPELLCAST_FAILED` | **Verified** (Holy Light 647 interrupted without a `SUCCEEDED`; `FAILED` with plain ID 1866) — interrupts cannot falsely reset |
| `CHANNEL_START` / `CHANNEL_STOP` | **Verified** — natural completion (20578) and
   damage-interrupted channels (1159) both fire `CHANNEL_STOP` with plain IDs.
   One unconfirmed sub-case: movement-cancelled channel (capture showed no STOP —
   may be truncated). Era tables have an empty channel-stop list, so the only
   exposure is the `unit.channeling` flag; mitigation: clear `channeling` in
   `UNIT_SPELLCAST_INTERRUPTED`/`FAILED` and on `PLAYER_ENTER_COMBAT` instead of
   relying on `CHANNEL_STOP` alone (defensive on every flavor) |
| `UNIT_SPELLCAST_FAILED_QUIET` | **Verified** — fires with plain classic-era ID
   `75` (Auto Shot) on movement-cancel, plus `SUCCEEDED 75` and Raptor Strike `2973`.
   Spec change: the handler at `:727` is gated `isClassic` only — extend to
   `(isClassic or isForever)` so Forever hunters get the movement-cancel
   rescheduling (event, IDs and tables all verified there). Depends on
   `unit.isShooting` from `START_AUTOREPEAT_SPELL`/`STOP_AUTOREPEAT_SPELL`, which
   still needs verification on Forever (see release checklist) |
| Next-melee ability timing (`SUCCEEDED` at swing time, no `START`) | **Verified** —
   Heroic Strike `78` fired `SUCCEEDED` coinciding with a `PLAYER_SWING`, no `START`;
   ability-consumes-the-swing timing confirmed. Payload shape matches the library's
   handler signature (unit, castGUID, spellID) |
| Party/unfiltered casting noise | Non-issue: the probe's unfiltered `RegisterEvent` shows all units (doubled lines = two party casters); the library uses `RegisterUnitEvent("player","target")` + `getUnit()` filtering |
| CLEU-aura paths (`prevent_swing_speed_update` — druid forms / Seal of the Crusader; `prevent_reset_swing_auras`) | **Dead on Forever** (CLEU). Classic-era tables have empty aura lists (no loss); the form-change attack-speed skip is lost and must be handled via `UNIT_ATTACK_SPEED` alone, or via `UNIT_AURA` if the skip proves necessary |
| New Classic+ spells (`1282503` etc.) | Not in any table. Cast-time ones self-cover via the generic `casting` path; instant ones that should reset need identification (open item 5) |

Probe (one listener for the whole family):

```lua
/run SC=SC or CreateFrame("Frame") for _,x in pairs({"START","SUCCEEDED","FAILED","FAILED_QUIET","INTERRUPTED","CHANNEL_START","CHANNEL_STOP"}) do SC:RegisterEvent("UNIT_SPELLCAST_"..x) end SC:SetScript("OnEvent",function(_,e,u,g,s) print(e,s) end)
```

Test matrix: (1) cast-time spell (Flash of Light) — expect `START` then
`SUCCEEDED`; (2) instant (Judgement/SoR) — expect `SUCCEEDED` only;
(3) cancel a cast by moving — expect `INTERRUPTED` or `FAILED`;
(4) channel (bandage) — expect `CHANNEL_START`/`CHANNEL_STOP`;
(5) next-melee ability — expect `SUCCEEDED` at swing time, no `START`.

If all five behave as in classic, the reset logic ports to Forever unchanged —
no code changes beyond the isForever table routing already in the spec. One
defensive hardening to include regardless of flavor: clear `unit.channeling` in
`UNIT_SPELLCAST_INTERRUPTED_OR_FAILED` and `lib:PLAYER_ENTER_COMBAT` rather than
relying solely on `UNIT_SPELLCAST_CHANNEL_STOP` (movement-cancelled channels may end
silently on Forever; a stale `channeling` flag corrupts `SwingEnd`'s clip decision).

### 8.12 Swing-interaction coverage matrix (full-model audit)

| Interaction | Forever coverage | Verdict |
|---|---|---|
| Swing anchors, all hands/outcomes | `PLAYER_SWING` verified | Covered |
| Parry haste | No directional signal | Report item 1 |
| Reset on cast completion | Events verified; rule status unknown | Report item 2 / open item 15 |
| Next-melee abilities | Verified live | Covered |
| Instant resets / no-reset exceptions | SUCCEEDED + classic IDs verified | Covered |
| Interrupt/failed no-reset | Verified | Covered |
| Extra attacks (Windfury, sword spec) | Each extra swing fires `PLAYER_SWING` — anchored naturally | Covered |
| Auto attack toggle no-reset (`6603`) | `SUCCEEDED 6603` verified; library guards exclude it from resets | Covered |
| Auto Shot cycle + melee/ranged exclusivity | `PLAYER_SWING` type 2 anchors, `FAILED_QUIET 75` on movement, autorepeat events verified; cast-window + cancel gates extended per 8.11/8.12 | Covered |
| Feign Death reset | Library side covered (`reset_swing_spells` + FD shim 8.6); engine rule on Forever unverified — FD is an instant that resets (exception to "instants don't reset") | Rule check folded into open item 15 (FD mid-cycle test) |
| Weapon swap reset | `PLAYER_EQUIPMENT_CHANGED` — not yet verified on Forever | Release checklist item 8 |
| Combat enter/leave, offhand start | `PLAYER_ENTER_COMBAT`/`LEAVE` — not yet verified on Forever | Release checklist item 8 |
| Feign Death reset | `C_Spell` shim (8.6) | Covered after fix |
| Ranged cast-window + movement cancel | `FAILED_QUIET` gate extension specced; the cast-window handler at `:404` is ALSO `isClassic`-gated — extend both to `(isClassic or isForever)` | New spec item |
| Mid-swing haste rescale | Fresh `UnitAttackSpeed` reads are SECRET in restricted content → rescale is a no-op; timer snapshots at each `PLAYER_SWING` and self-corrects at the next swing | Known limitation, documented; the same `PLAYER_SWING_UPDATE` event would close it (Discord thread, not bug report) |
| Form-change speed skip (druid forms, SotC) | CLEU-aura path dead; degrades to `UNIT_ATTACK_SPEED` | Accepted; needs a druid test |
| Slam-style pause spells | Era table empty; new Classic+ equivalents unknown | Ties to open item 5 |
| Channel no-reset / stop-reset + channeling flag | Channel events verified; hardening specced | Covered |
| Target swing tracking | `PLAYER_SWING` is player-only | Absent by design, documented |

**Target-tracking investigation — CLOSED (no-op verified).**
`CombatTextSetActiveUnit` exists on Forever (`/dump` verified; calling it with
`"target"` returns without error), but it does **not** re-anchor the stream:
verified by the isolation test — with the "target" watched, the player standing
still and only taking hits, the stream still fired the player's own defensive
events (`DAMAGE`/`DODGE`/`BLOCK`/`PARRY`/`MISS` + debuffs on the player). A real
target anchor would have suppressed those. The function is inert on this client;
the combat text stream is permanently player-anchored. No side effect to restore
(the call did nothing). Target swing tracking stays: no data source, cadence
heuristics rejected (unattributed, direction-ambiguous types), documented as
unsupported on Forever.

**Reopened for analysis (2026-09-25, post-closure):** the player-anchored combat
text stream actually contains the target's swing attempts — every incoming melee
fires `DAMAGE`/`PARRY`/`DODGE`/`BLOCK`/`MISS` on the player — and the validated
swing-correlation filter (skip events coinciding with the player's own
`PLAYER_SWING`) can classify incoming vs outgoing. A target swing timer is
therefore implementable as a heuristic, with documented failure modes: multiple
attackers (any mob's swing anchors the timer — the harmful direction, systematic
in trash packs), the player's instant melee abilities (fire CT events without a
`PLAYER_SWING`), and mob ranged attacks. Two-track plan: (1) extend the Blizzard
ask with unit-targeted swing events / source attribution (fits the "mechanically
missing" framing — classic CLEU gave target swings, Forever gives nothing
attributable); (2) optionally an opt-in heuristic, single-melee-target only.
**Blocked on the PLAYER_SWING player-only isolation test (open item 10), which
was never formally run** — it is the foundation of the correlation filter.

## 9. Open items / to verify before or during implementation

1. ~~Open-world combat: re-run the `AS`/`RD`/`CD secret` probes mid-fight outside any
    instance~~ — **resolved (2026-09-25): secrets apply in ALL combat** — open-world
    mid-fight showed `UnitAttackSpeed`/`UnitRangedDamage` SECRET and
    `ShouldCooldownsBeSecret()` true, identical to dungeon combat. Additionally,
    `IsCombatLogRestricted()` reads `true` even out of combat in the open world —
    the combat-log restriction is always-on in this beta build (see 4.2).
2. ~~`UnitRangedDamage` with a ranged weapon equipped (non-zero speed), same contexts.~~ — **resolved (2026-09-28, open-world probe; dungeon not retested, not needed for the Phase 2 decision):** hunter with bow, open world. Out of combat: third `UnitAttackSpeed` return = `UnitRangedDamage` = 2.0910000801086, both plain, both equal to the live `PLAYER_SWING` type-2 duration. Mid-fight (`ShouldCooldownsBeSecret()` = true, confirmed live): swing payload stays plain 2.091 on every shot; both API reads flag secret in most samples (one plain sample at a combat boundary — the two-tier restriction flip, section 3). No secrecy advantage for either source; the third return is a valid ranged-speed source on Forever and the Phase 2 switch (IMPROVEMENT_PLAN.md §2) is confirmed and applied. Side finding: `print()` displays the underlying number even when `issecretvalue()` flags the value secret — display is not blocked, only comparison/arithmetic is.
3. ~~Does `UNIT_ATTACK_SPEED` still fire in combat when speeds are secret?~~ —
   **verified: fires** (weapon swap and Seal of the Crusader haste change, live in
   combat, plain unit payloads; fired for multiple units under unfiltered
   registration — the library's `RegisterUnitEvent` scoping avoids the noise).
   New sub-question from the SotC capture (open item 16): the in-flight swing was
   NOT rescaled by the haste change — it completed on the old 2.4s schedule and
   the 1.714 cadence began at the next swing. If confirmed, the library's
   proportional rescale in `UNIT_ATTACK_SPEED` is wrong for Forever and must
   defer to the next `PLAYER_SWING` anchor.
4. ~~Spellcast family on Forever (section 8.11)~~ — **fully verified**:
   `START` (cast-time only), `SUCCEEDED`, `INTERRUPTED`, `FAILED`, `FAILED_QUIET`
   (Auto Shot `75`), `CHANNEL_START`/`CHANNEL_STOP` (natural + damage-interrupted),
   next-melee coincidence (Heroic Strike `78`) — all plain, classic-era IDs. Only
   sub-case left: `CHANNEL_STOP` on a movement-cancelled channel (one silent
   capture, may be truncated; the channeling-flag hardening covers it either way).
5. ~~Identify `1282503` and other new Classic+ spell IDs relevant to swing mechanics
   (next-melee-style abilities, FD-class resets).~~ — **resolved (2026-09-28, external
   datamine research; in-game confirmation pending). Sources: Daybreak Forever
   (daybreakforever.com/skills, build 1.60.1.70009), TheWoWDB `wow-forever`
   database, Wowhead Forever, wowforevertalents.com (48 new abilities across all
   nine classes), classicwow.gg class guides.** Findings:

   - `1282503` = **Blazewind Blast** — an *item effect* (requires level 55,
     instant, 30 yd, Holy+Nature "Holystorm" hybrid school, 3x damage to Wolves
     and Worgen). Not a class ability; instant with no cast time, so it needs no
     table entry — it appeared in the §4.3 capture because
     `UNIT_SPELLCAST_SUCCEEDED` fires for all units (likely a mob's or another
     player's item proc/use).
   - **Slam is new to the Forever trainer** (Fury school, Rank 1 at level 20,
     1.5 s cast, 18 s cooldown — the cooldown is a Forever addition). The
     Era-routed tables have no Slam handling (`pause_swing_spells` empty — the
     §8.12 acknowledged gap), so the library currently treats a Forever Slam
     cast as a plain cast → reset on completion.
   - **Improved Slam (spell 12862)** — Forever talent: "Slam no longer
     interrupts or delays your melee swing". Swing behavior is
     talent-conditional; base Slam presumably still delays the swing. Needs
     in-game verification (which START/SUCCEEDED events fire, with and without
     the talent) before any table entry — spec in IMPROVEMENT_PLAN.md §6.
   - **Maelstrom Weapon is a new-in-Forever Enhancement talent** (5 ranks; melee
     damage stacks cast-time/mana reduction on the next Lightning Bolt; a
     five-stack bolt at rank 5 is instant). The Era-routed
     `prevent_reset_swing_auras` is empty, so a 5-stack instant Lightning Bolt
     would wrongly reset the swing — and the flag mechanism itself is CLEU-based
     (dead on Forever, §4.1), so even with the buff ID the current path cannot
     set the flag; a `UnitAura`-based detection is required. The Forever buff
     spell ID is not yet identified (capture in-game with the IMPROVEMENT_PLAN
     §6 probe).
   - **No new** next-melee-style abilities, FD-class instant resets, or
     channeled noreset-class spells in the 48 new abilities: they are talents
     and trainer skills with no swing-timer interaction (cross-class "Eureka!"
     buff 1259812/1259813/1259817/1259821/1259823, hunter Strider Kick 1317257
     and Hydra Shot 1293020, warrior Spearing Strike 1310222, paladin Twist of
     Light 1310735 — instants or passives needing no table entries).
   - Engineering: new Forever bombs (if any) are unaudited; a missing
     `noreset` entry only causes a one-cycle transient that self-corrects at
     the next swing. Optional follow-up.
   - ID ranges observed for Classic+ additions: talents ~1222xxx–1223xxx and
     1310xxx; item effects ~127xxxx–130xxxx; trainer/rune spells ~1259xxx–1281xxx.
     Classic-era IDs are reused where the spell exists in classic data (Slam
     1464, Judgement of Fury 20411, Improved Distract 14084).
6. Retail 12.x: confirm the same guards behave there (the fix should be shared).
7. Pre-existing classic-era gap surfaced by the probe: the Classic `reset_swing_spells`
   table contains no paladin casts (Flash of Light `19750`, Holy Light, Judgement
   `20271`) — decide separately whether that is intended behavior or a gap; do not
   bundle into this fix.
8. ~~`PLAYER_SWING` payload secrecy mid-fight in a dungeon~~ — resolved: **plain**
   (`swing: 0, 3.40000000953674` mid-fight while `UnitAttackSpeed` was SECRET at the
   same moment). The numeric contract holds everywhere; no pass-through fallback
   required.
9. ~~`Enum.PlayerSwingType` values~~ — resolved: MainHand=0, OffHand=1, Ranged=2
   (maps 1:1 to `mainhand`/`offhand`/`ranged`).
10. `PLAYER_SWING` coverage: **ranged confirmed** (hunter Auto Shot fires with
    `swingType=2`, plain `swingDuration`); **off-hand (`swingType=1`) still
    unverified** (needs a dual-wield character — release checklist item 6).
    ~~Does `PLAYER_SWING_RANGE_UPDATE` need `EnableRangeCheck` first?~~ — answered:
    yes, and even then it only fires once, at the enable call (section 4.4).
    **PLAYER_SWING player-only isolation test also never formally run** (stand
    still, get hit, listener armed) — it underpins the target-tracking closure and
    the swing-correlation filters (parry option A/E, any target heuristic).
11. Whether the `C_SwingTimer` system also exists on retail 12.x — the built-in swing
    timer ships with Forever; if the namespace exists on retail, the native path can
    be shared.
12. ~~Parry haste detection source on Forever~~ — signal confirmed: `COMBAT_TEXT_UPDATE`
    fires with `combatTextType == "PARRY"` (live-verified while tanking; section 8.10),
    and it fires **independently of floating-combat-text settings** (verified with FCT
    disabled). Remaining sub-check before release: direction — does it also fire when
    the player's own attack is parried, and does `GetCurrentCombatTextEventInfo()`
    carry a disambiguating field (parry haste belongs to the parrying unit only).
    Run `/api dump C_CombatText` (the namespace may expose query functions beyond the
    event/structure the keyword search surfaced), capture
    `GetCurrentCombatTextEventInfo()` for one parry in each direction
    (tank a mob until you parry; then melee a mob from the front until it parries
    you), and compare the fields. If no discriminator exists, fall back to the
    conservative option in 8.10 rather than applying haste on ambiguous PARRY.
    Note: the `/api dump` command takes the system name (`CombatText`), not the
    namespace (`C_CombatText`); the keyword search already showed zero functions in
    the system, so a discriminator is unlikely to exist there.
    **Avenue closed (2026-09-25):** `/api dump` fails for both `C_CombatText` and
    `CombatText` ("No system found"), and the keyword search listing zero functions
    in the system is conclusive on its own — any `C_CombatText.*` function would have
    matched the "combattext" search. The CombatText system is event-plus-structure
    only: **no discriminator exists**. The parry direction question now hinges
    entirely on open item 13 (missed-swing cadence): if `PLAYER_SWING` fires per
    swing attempt, the swing-correlation heuristic is provably safe (option i);
    otherwise Forever ships without parry haste (option ii).
    **Final state:** item 13 resolved positively, so all options in section 8.10 are
    viable; the choice among A/B/D/E is a product decision recorded in 8.10
    (recommendation: B + D first release, A only as opt-in if real-time haste is
    wanted before Blizzard acts).
13. ~~**Does `PLAYER_SWING` fire for missed/dodged/parried swings?**~~ — resolved:
    **yes**. Live capture from the front: swing cadence holds steady (~2.4s) through
    DODGE/MISS/PARRY events, and a parried swing still fired its own `PLAYER_SWING`
    (PARRY at t=58.929, swing at t=58.996). The Forever timer never goes stale on
    misses, and the swing-correlation direction filter is validated (outgoing parries
    coincide with the player's swing anchor; incoming ones do not). Shortened gaps
    observed (~2.0s and ~0.98s on a 2.4s weapon) confirm parry haste is live in the
    engine.

14. **`GetCurrentCombatTextEventInfo()` across combat text types on Forever.**
    Verified empty for `PARRY`; the accessor historically returned payload (xCT
    reads it for `DAMAGE`; `SPELL_ACTIVE` reactive messages carried the ability —
    Revenge vs Overpower, i.e. direction data). Probe with the `CTI` macro
    (appendix): if any type populates, the Discord ask sharpens to "wire up the
    payload accessor"; a warrior `SPELL_ACTIVE` capture (Revenge/Overpower proc)
    would confirm direction data is still in the engine.
15. **CRITICAL — does the reset-on-cast rule still exist in Forever?** Observed:
    the built-in swing timer does not react to spell casts. Two readings with
    opposite library consequences: (a) the rule is live and the built-in bar is a
    simplistic event-driven UI (reset logic stays correct — the library can model
    what the built-in bar doesn't); (b) the rule was removed in Forever (the
    built-in bar is right, and the library's reset/casting-flag logic must be
    gated OFF on Forever or it will reset timers the game doesn't). Decisive test:
    cast a spell mid-swing-cycle, watch the next
    swing — later than cadence (≈ full weapon speed after cast completion) = rule
    live; on original cadence = rule gone. Second test spell: Feign Death mid-cycle
    on a hunter (FD is an instant that resets — if the next swing comes a full
    cycle after FD, the instant-reset family survives too).
    **RESOLVED (2026-09-25, clean redo): the reset-on-cast rule is LIVE on Forever.**
    Verified: swing at 15.797 (2.4s weapon); swing due at 18.197 on original cadence
    never fired (held mid-cast — the clip/hold behavior is also real); FoL cast
    completed at 18.869; next swing at 21.221 = cast completion + weapon speed
    (predicted 21.269, within 0.05s; the no-reset grid fits nowhere). Consequences:
    report 2 stands as filed; the patch's reset logic ships for Forever unchanged;
    the swing-hold-during-cast interaction confirmed live in the engine.
    First attempt earlier the same day was inconclusive (7.26s gap, lost context).
    Side findings: Judgement 20271 and SoR 20288 mid-cycle did NOT reset
    (2.40/2.44s gaps — instants behave per classic tables). The instant-with-reset
    family (Feign Death, Ghost Wolf) is **unverifiable in the level-20 beta**
    (FD is level 30+; Ghost Wolf test not practical). **Decision: ship the
    classic-table default.** Risk documented: if Forever removed instant-resets, a
    wrongly-applied reset after FD/Ghost Wolf shows a restarted bar that
    self-corrects at the next `PLAYER_SWING` — one-cycle transient, no error, no
    permanent drift. Verify on launch day when the level cap lifts (checklist 8.9
    item 9).
16. ~~**Does a mid-swing haste change rescale the in-flight swing on Forever?**~~ —
    **RESOLVED (2026-09-25, discriminating trial): NO rescale.** Swing at 90.862
    (2.4s), SotC applied at 91.179 (δ=0.317): no-rescale predicted 93.262, rescale
    predicted 92.666, observed **93.254** — within 0.008s of no-rescale. The
    in-flight swing completes on its original schedule; the new speed applies from
    the next swing. Corroborated: a late-application trial (δ=2.19) landed on the
    old schedule (ruling out restart-at-application), and reverse-direction trials
    (haste removal) lean the same. Bonus semantics: `PLAYER_SWING`'s duration field
    reports the speed at swing completion — the completing swing ran the old
    schedule but reported the new speed, which is exactly what the next cycle needs.
    **Patch change: the proportional rescale in `UNIT_ATTACK_SPEED` (`:459+`) must
    be disabled on Forever** — the handler should not rescale; `PLAYER_SWING`
    re-anchors at the new speed. Add to spec section 8.5.
17. **Two behaviors observed in the 2026-09-28 death-test capture (hunter,
    Forever):**
    - **Duplicate next-melee anchor — FIXED 2026-09-28.** Melee cycles with a
      queued ability printed `START(1.6, 12975.248)` / `STOP` /
      `START(1.6, 12975.248)` — two `SwingStart` calls at the same instant
      with identical expiry (a second duplicate in the post-res capture sits
      8.01 s after the first, matching an ability cooldown — Raptor Strike
      2973). The `UNIT_SPELLCAST_SUCCEEDED` anchor and the `PLAYER_SWING`
      anchor for the same special swing both fire — the melee analog of the
      ranged double-anchor fixed in `d044c05`. The identical expiry proves
      `PLAYER_SWING` anchors the consumed swing, so the `next_melee_spells`
      SUCCEEDED anchor is now gated off on Forever (`and not isForever` in
      `UNIT_SPELLCAST_SUCCEEDED`), mirroring the ranged gate. Confirm in the
      next session: single START per swing while using Raptor Strike, and the
      IMPROVEMENT_PLAN §6c `PS2` probe should show `SUCCEEDED 2973` arriving
      alongside the swing without producing a second anchor.
      **Post-fix capture (same day, ~7 min later): most melee cycles anchor
      once, but two identical-expiry duplicates remain (START/STOP/START at
      13454.718 and 13461.126 — same signature and roughly the same rate as
      pre-fix). Unresolved: either the capture predates the gate's build
      (`GetTime` survives `/reload`, so timestamps cannot confirm), or the
      duplicates were never (only) the next-melee anchor. Post-gate the only
      non-reset mainhand anchor is `PLAYER_SWING`, so a residual duplicate
      means either two `PLAYER_SWING` events in one frame (engine-side
      double-fire) or a reset anchor (cast completion, `isReset=true`) landing
      in the same frame as the held swing's `PLAYER_SWING` — the classic
      cast-completion/hold interaction of §9 item 15 makes the latter
      plausible. Next probe (raw events, distinguishes all three): a
      bare `PLAYER_SWING` listener printing `GetTime()` alongside the §6c
      `PS2` spellcast listener — two `PS` prints at the same instant =
      engine double-fire; one `PS` plus an `SC` = cast-coincidence; one `PS`
      alone with a lib double-print = lib-side. Run pure auto-attack first
      (no abilities), then with Raptor Strike queued; note kill blows, target
      switches and parry/dodge at the duplicate moments. The gate is retained
      either way — it is harmless and correct if `PLAYER_SWING` anchors
      special swings (the pre-fix identical-expiry pair proves it does).
      **Gate verified in live combat 2026-09-28 (probe capture, post-burst
      section): 10 consecutive swings, one `PS` raw event per swing, lib START
      expiry = event time + weapon speed exactly, single anchor per event,
      clean ~1.6 s cadence — the `2fda7e8` gate does not disturb normal
      anchoring.** Two revisions follow from the same capture:
      - **The observed "duplicates" may be OCR artifacts.** The image-attachment
        transcription garbles digits (burst-section expiry integer parts are
        off by 1–2 with sub-second parts matching `PS + speed` exactly;
        earlier captures show digit noise like `2.091000C0801086`). The
        "identical-expiry duplicate START" pairs in earlier captures are
        consistent with mis-transcribed lines and have never appeared in a
        raw screenshot. Treat item 17's duplicate as UNCONFIRMED; re-open only
        if a real duplicate appears in an unmodified screenshot.
      - **The gate's premise is now unverified and must be probed.** The gate
        is correct only if `PLAYER_SWING` fires for a swing that consumes a
        queued next-melee ability (Raptor Strike/Heroic Strike). If it does
        not, the gate DROPS the anchor for those swings on Forever — a
        regression. Decisive probe (before any release): queue Raptor Strike
        with the §6c `PS2` spellcast listener and the raw `SW` listener
        active — `SUCCEEDED 2973` at consumption with a matching `PS` event
        = gate correct, keep; `SUCCEEDED 2973` with NO `PS` = revert the
        gate (the spellcast anchor is the only one for special swings).
        Capture as an unmodified screenshot, not a transcription.
      - **Open engine question from the same capture:** five `PLAYER_SWING`
        events ~0.2 s apart (all with the player's 1.6 weapon speed, each
        anchored cleanly by the lib) — not auto-attack cadence. Unknown
        trigger (instant abilities? extra attacks? multi-mob parry haste?).
        Record what was happening when captured.
      **CLOSED 2026-09-28 (millisecond-counter probe, clean data):** the
      decisive Raptor Strike capture shows both consumptions (`SC 2973` at
      counter 592789 and 599221) each accompanied by a `PS 0` at the
      IDENTICAL counter value — `PLAYER_SWING` fires for the swing that
      consumes a queued next-melee ability, dispatched in the same frame as
      the `UNIT_SPELLCAST_SUCCEEDED`. The gate's premise is CONFIRMED;
      `2fda7e8` ships. This also confirms the original duplicate was real
      (two anchors in one frame → identical expiry); the later "residual"
      noise was transcription/OCR artifacts. Item 17 closed.
      **New finding from the same capture:** the auto-attack toggle on
      Forever fires `UNIT_SPELLCAST_SUCCEEDED 6803` (observed at attack
      start, 133 ms before the first swing) — NOT classic's 6603. The
      library's two `spell ~= 6603` guards in `UNIT_SPELLCAST_SUCCEEDED`
      therefore do not protect the toggle on Forever: toggling auto-attack
      during a cast would clear `unit.casting` prematurely and skip the
      reset on that cast's completion. **FIXED 2026-09-28:** both guards in
      `UNIT_SPELLCAST_SUCCEEDED` now use a shared
      `isAttackToggle = spell == 6603 or (isForever and spell == 6803)` —
      classic clients keep 6603 untouched, 6803 is recognized on Forever
      only. Verification item for the next session: toggle auto-attack
      during a Slam-style cast on Forever and confirm the cast completion
      still resets the swing.
      **Probe result 2026-09-28 (raw-event listener + lib listener, pure
      auto-attack, 14 swings): NO duplicates at any level.** Exactly one
      `PS 0 1.6 <t>` raw event per swing (cadence ~1.59–1.62 s, no double-fire
      at the same `GetTime()`), lib output a clean 1:1 START/STOP alternation
      with expiry = event time + duration. Conclusion: the engine does not
      double-fire `PLAYER_SWING` during plain auto-attacks, and the lib anchors
      exactly once per event. The earlier residual duplicates are therefore
      trigger-dependent (ability use or a cast completing on a swing frame) —
      the cast-completion coincidence hypothesis (§9 item 15's hold
      interaction: a held swing's `PLAYER_SWING` landing in the same frame as
      the completing cast's reset anchor) is now the leading candidate.
      Remaining reproduction: same setup WITH abilities used (Raptor Strike
      queued, any cast) and the `PS2` spellcast listener active — the raw
      prints at the duplicate moment (two `PS` = engine; one `PS` + `SC` =
      cast coincidence; one `PS` alone = lib-side) settle the mechanism and
      the fix point.
    - **Extra ranged STOPs during movement-delayed cycles — NOT A DEFECT
      (diagnosis corrected 2026-09-28).** The initial hypothesis (a fired
      timer re-triggering the cancel branch) is impossible:
      `SwingEnd` cancels its own timer, so `IsCancelled()` reads true
      afterwards and `SwingStart` cannot double-fire. The observed 2–3 STOPs
      per movement gap are the designed retry chain: each `FAILED_QUIET`
      retry schedules a predicted expiry, each missed prediction fires
      `SwingEnd`→STOP, and the UPDATE reschedules — the bar draining to zero
      and re-scheduling while moving, which is correct behavior. No action.

## 10. Appendix — probe macros (each fits the 255-char macro limit)

```lua
-- Attack speed secrecy
/run local r=UnitAttackSpeed("player") print("AS:",r,issecretvalue(r) and "SECRET" or "plain")

-- Ranged speed secrecy (equip a ranged weapon for a non-zero result)
/run local r=UnitRangedDamage("player") print("RD:",r,issecretvalue(r) and "SECRET" or "plain")

-- Cooldown secrecy predicate
/run local i=C_Secrets.ShouldCooldownsBeSecret() print("CD secret:",i)

-- Combat-log restriction state
/run print("CL restricted:",C_CombatLog.IsCombatLogRestricted())

-- CLEU registration acceptance
/run local f=CreateFrame("Frame") local ok,e=pcall(f.RegisterEvent,f,"COMBAT_LOG_EVENT_UNFILTERED") print("CLEU register:",ok,e)

-- Spellcast payload listener (prints every cast; stop with /reload)
/run SpellProbe=SpellProbe or CreateFrame("Frame") SpellProbe:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") SpellProbe:SetScript("OnEvent",function(_,_,u,g,s) print("cast:",s,issecretvalue(s) and "SECRET" or "plain") end)

-- PlayerSwingType enum values
/dump Enum.PlayerSwingType

-- PLAYER_SWING registration acceptance (12.x RegisterEvent returns a boolean)
/run local f=CreateFrame("Frame") print(f:RegisterEvent("PLAYER_SWING"))

-- PLAYER_SWING payload capture (swingDuration is a NUMBER; swingType: 0=MainHand 1=OffHand 2=Ranged)
/run SP=SP or CreateFrame("Frame") SP:RegisterEvent("PLAYER_SWING") SP:SetScript("OnEvent",function(_,_,d,t) print("swing:",t,issecretvalue(d) and "SECRET" or d) end)

-- Combat text listener (parry haste signal; prints every combat text type while fighting)
/run CT=CT or CreateFrame("Frame") CT:RegisterEvent("COMBAT_TEXT_UPDATE") CT:SetScript("OnEvent",function(_,_,t) print("CT:",t) end)

-- GetCurrentCombatTextEventInfo payload per combat text type (inspect with /dump CTI after a fight)
/run CI=CI or CreateFrame("Frame") CI:RegisterEvent("COMBAT_TEXT_UPDATE") CI:SetScript("OnEvent",function(_,_,t) CTI=CTI or {} CTI[t]={pcall(GetCurrentCombatTextEventInfo)} end)

-- UNIT_COMBAT direction capture (parry-haste signal; prints defender tokens for parries/dodges)
/run local f=CreateFrame("Frame") print("reg",f:RegisterEvent("UNIT_COMBAT")) f:SetScript("OnEvent",function(_,_,u,a) if a=="PARRY" or a=="DODGE" then print("UC",GetTime(),u,a,issecretvalue(u)) end end)

-- CombatText PARRY payload types and secrecy (values print even when secret)
/run CT2=CT2 or CreateFrame("Frame") CT2:RegisterEvent("COMBAT_TEXT_UPDATE") CT2:SetScript("OnEvent",function(_,_,t) if t=="PARRY" then local a,b,c=GetCurrentCombatTextEventInfo() print("P",a,b,c,issecretvalue(a),issecretvalue(b),issecretvalue(c)) end end)
```

## 11. Follow-up improvement plan (moved to its own document)

The improvement plan derived from external-reference analysis — the all-client
`PLAYER_DEAD` reset, `PLAYER_SWING` payload hardening, the Forever ranged-speed
source probe, the Auto Shot cooldown anchor for the classic flavors, the
rejected/deferred options table and the reference index — is maintained in
`docs/IMPROVEMENT_PLAN.md`. Kept separate because its scope (all clients plus
classic flavors) exceeds this document's Forever/Midnight investigation record.
Section references of the form §N in that document point back into this file.
