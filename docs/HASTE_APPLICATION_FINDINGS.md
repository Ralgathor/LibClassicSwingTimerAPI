# Haste application timing on WoW: Forever — investigation findings

Status: **VERIFIED by capture** (rogue Slice and Dice session, 2026-09-30
15:41 + paladin Seal of the Crusader control session, 15:55, build 70124).
Evidence: `docs/evidence/4everSwingTimer-2026-09-30.lua` (verbatim
SavedVariables copy, both sessions) and
`docs/evidence/WoWCombatLog-093026_154137.txt` (both sessions, append-mode).
**Implemented** on `feature/forever-support` (2026-09-30) — the
dynamic-haste table and rescale described in section 6 — pending the in-game
verification checklist (section 6.1).

## 1. The report

On the Forever beta, a rogue's Slice and Dice appeared to shorten the in-flight
swing (mid-swing haste application). This contradicted the shipped Forever
rescale gate (`LibClassicSwingTimerAPI.lua` lines 621/636/655:
`and not isForever`), which never rescales in-flight swings on Forever and was
justified by a single SotC observation (`FOREVER_API_FINDINGS.md` §8.9,
2026-09-25: "in-flight swing completed on the old schedule, new cadence from
the next swing").

**The report is correct.** The engine applies dynamic-family haste mid-swing.

## 2. Verified engine rule

Test session: rogue `Rolhgar` (GUID `Player-4620-011E60D2`), dual-wield,
mainhand base speed **1.683**, offhand base **1.782**. SnD rank 1 (spell 5171)
measured at **+20% haste** (1.683 → 1.403; 1.683/1.403 = 1.1997; offhand
1.782 → 1.485, same ratio — both hands affected). 19 SnD casts, 20 Sinister
Strikes, ~228 mainhand swings. All measurements below are anchor-to-anchor
`PLAYER_SWING` (type 0) periods from the trace — a single channel, so the
~0.45 s pre-resolution lag cancels; the parry work established this method as
millisecond-clean.

### 2.1 Gain direction: proportional-remaining rescale (model M2)

For a cast at offset `t` into a swing of speed `S`, with hasted speed `H`,
the measured period `P` follows `P = t + (S - t) * H / S` — the classic
library model (`timeLeft = remaining * newSpeed / oldSpeed`). 13 clean gain
windows:

| offset into swing | measured P | M0 (snapshot) resid | M2 resid | M3 (progress-keep) resid |
|---|---|---|---|---|
| 25% | 1.507 | -0.176 | +0.035 | +0.104 |
| 30% | 1.493 | -0.190 | +0.007 | +0.090 |
| 33% | 1.537 | -0.146 | +0.042 | +0.134 |
| 37% | 1.538 | -0.145 | +0.032 | +0.135 |
| 57% | 1.621 | -0.062 | +0.060 | +0.218 |
| 61% | 1.573 | -0.110 | -0.002 | +0.170 |
| 62% | 1.587 | -0.096 | +0.009 | +0.184 |
| 66% | 1.604 | -0.079 | +0.015 | +0.201 |
| 69% | 1.653 | -0.030 | +0.056 | +0.250 |
| 69% | 1.588 | -0.095 | -0.009 | +0.185 |
| 78% | 1.653 | -0.030 | +0.031 | +0.250 |
| 79% | 1.638 | -0.045 | +0.013 | +0.235 |
| 82% | 1.624 | -0.059 | -0.009 | +0.221 |

M0 (the current gate's assumption) and M3 are rejected everywhere; M2 holds
within event jitter. One further window (SnD SUCCEEDED at the exact instant
of the next anchor, 4.5% of the swing remaining) is a resolution-boundary
case and is excluded from the table. The M2 residual mean is **+0.024**,
consistent with event-dispatch skew (the SUCCEEDED event and the anchors
lead/lag the engine's instants by ~0.1–0.15 s — the same two-cluster skew
family documented for `UNIT_COMBAT` in the parry evidence; the engine rule
itself is M2, not M2+0.024). The combat log corroborates the application
instant: `SPELL_AURA_APPLIED` and `SPELL_CAST_SUCCESS` for the same SnD are
4 ms apart in that channel.

### 2.2 Expiry direction: dynamic lengthening, not snapshot

Five expiry windows (speed 1.403 → 1.683 at the next anchor). Four measured
periods land between the hasted and base speeds (1.494, 1.464, 1.535, 1.585),
as proportional-remaining lengthening predicts; snapshot-on-removal
(P ≈ 1.403) is rejected by +0.06 to +0.18 — far beyond the ±0.03 jitter.
One window overshoots even the new full speed: SnD applied 4444.763 with
1 combo point (9.0 s), so expiry fell 0.086 s into the following swing, yet
the measured period was 1.768 (+0.085 over the full new speed). Single
occurrence, unexplained, recorded as an open anomaly — same status as the
parry dispatch-skew outliers were before the join work resolved them.

### 2.3 Library behavior during the capture

The rescale gate held: zero mainhand mid-swing
`LIB_UNIT_SWING_TIMER_UPDATE` events in the session (the 17 offhand UPDATEs
are combat-start half-speed anchors). So during the whole capture the rig's
bar ran long for the remainder of the first swing after every SnD cast —
the engine's swing landed early and `PLAYER_SWING` re-anchored. That is the
visual anomaly the user reported.

## 3. The two-family taxonomy on Forever — both families captured same-day

The classic library path already encodes the split: `prevent_swing_speed_update`
(druid forms + SotC ranks 21082, 20162, 20305–20308) suppresses the mid-swing
rescale — the snapshot family; everything else rescales (line 621). The
community record (WeakAuras2 issue #3205, TBC) documents the same split and
SotC as "snapshotted in both ways". On Forever:

- **Dynamic family**: SnD confirmed mid-swing, both directions (section 2).
- **Snapshot family**: SotC confirmed next-swing-only, both directions — the
  §8.9 observation (2026-09-25), now re-verified as a same-day control on
  the same rig and build as the SnD capture.

### 3.1 SotC control capture (2026-09-30 15:55)

Paladin `Ralgathor` (GUID `Player-4620-0095BF89`), one 3.4 two-hander
(the combat log confirms a single weapon: one continuous 37–815 damage
profile across both speed windows, 12 LANDED + 1 MISSED = 13 = the trace's
13 mainhand anchors). Seal of the Crusader rank 2 (spell 20162) hasted the
weapon 3.400 → **2.428** (x1.4003 — matching the §8.9 observation's
2.4 → 1.714, x1.4002: SotC rank 2 is ~+40% with the same small non-integer
deviation in both captures, engine-internal haste arithmetic). SotC was
applied by casting the seal and removed mid-swing by casting Seal of
Righteousness (seals replace each other; confirmed in the combat log's
`SPELL_AURA_REMOVED` timeline). Seven transition windows, all M0:

| direction | offset | measured P | M0 resid | M2 resid |
|---|---|---|---|---|
| gain (SotC cast) | 19% | 3.408 | +0.008 | +0.792 |
| gain (SotC cast) | 26% | 3.409 | +0.009 | +0.733 |
| gain (SotC cast) | 30% | 3.433 | +0.033 | +0.718 |
| gain (SotC cast) | 59% | 3.396 | -0.004 | +0.391 |
| removal (SoR replaces) | 33% | 2.442 | +0.014 | -0.637 |
| removal (SoR replaces) | 52% | 2.424 | -0.004 | -0.468 |
| removal (SoR replaces) | 55% | 2.441 | +0.013 | -0.425 |

- **Gain**: the in-flight swing always completed on the old (unhasted)
  schedule; the hasted speed appears from the next swing. M2 is off by
  0.39–0.79 s.
- **Removal**: the in-flight swing always completed on its hasted schedule
  even though the aura was gone — "the attack speed bonus stays on until
  the next swing" (TheSorm's verbatim claim for classic-era SotC).

Same client build (70124), same rig, same day as the SnD capture: SnD is M2
in both directions, SotC is M0 in both directions. The classic-era two-family
taxonomy carries to Forever verbatim, and the classic library path's design
(rescale at line 621 + `prevent_swing_speed_update` skip) is the correct
target model.

Retroactive flag: the §8.5 dungeon notes record a "weapon swap
(speed 2.428 → 3.400)". 2.428 is exactly the SotC-hasted value of a 3.4
weapon, so those transitions may have been seal transitions misread as
weapon swaps. That capture (2026-09-25) is not in the archive; flagged for
re-examination, not asserted.

The §8.9 SotC test was therefore never evidence about the dynamic family —
the `not isForever` gate over-generalized a snapshot-family result, exactly
as WeakAuras did with commit 91bc69f before being argued out of it.

### 3.2 Additional family classifications (reported 2026-09-30, pending capture)

Two further classifications were reported from gameplay, both consistent
with the classic taxonomy the library encodes:

- **Flurry (warrior and shaman talent proc): dynamic family.** Consistent
  with the classic path, where Flurry is absent from
  `prevent_swing_speed_update` and rides the generic rescale. **Design gap
  on Forever**: Flurry is a crit-proc aura — its application fires no
  `UNIT_SPELLCAST_SUCCEEDED`, so the shipped cast-success trigger cannot
  cover it. An aura-presence trigger (the natural fit, which would also
  have covered Flurry's charge expiry and SnD expiry) was probed and is
  **ruled out**: aura data is blocked mid-combat on this client (section
  4). Flurry applications currently self-correct at the next
  `PLAYER_SWING` anchor (bar long for the in-flight swing after each crit,
  correct for the rest of the proc). The only remaining candidate signal
  is `UNIT_COMBAT` `CRITICAL` flags on the player's outgoing melee — which
  would additionally require talent detection and full 3-charge tracking
  with no aura ground truth to correct against. Left at next-swing
  correction unless a capture shows the crit signal is reliable enough to
  justify that machinery.
- **Druid form switches (Cat/Bear/Dire Bear): snapshot family.** Confirms
  the existing classification. No change needed on either path: the forms
  are in `prevent_swing_speed_update` on classic, and on Forever absence
  from the dynamic table gives exactly the engine's next-swing behavior
  (the same mechanism the SotC control verified).

## 4. Secrecy findings from this capture

Player `UNIT_SPELLCAST_SUCCEEDED` spell IDs read **plain mid-combat** (open
world) throughout the session: all 19 SnD casts were recorded with readable
IDs (5171) by the rig while fighting. This answers protocol step 5 partially:
the per-spell haste-table approach has a usable gain-direction signal.
(The earlier secret case — §4.3 correction — was target
`UNIT_SPELLCAST_START` mid-fight in a dungeon; player `SUCCEEDED` in open-world
combat is a different event/unit pair and stayed plain here.)

Still unprobed: whether player `SUCCEEDED` stays plain in restricted instanced
content, and whether `UNIT_ATTACK_SPEED` fires at all on Forever (its payload
is secret mid-combat either way, so it cannot drive the rescale).

**Aura APIs are blocked mid-combat (probe 2026-09-30, follow-up to the
dynamic-haste work):** with SnD actively hasting the swings, open-world
combat, `C_UnitAuras.GetPlayerAuraBySpellID(5171)` returns nil, and
`C_UnitAuras.GetAuraDataByIndex("player", "HELPFUL", i)` raises
"GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted
by '*** ForceTaint_Strong ***'". `UNIT_AURA` itself fires fine (probe
listener confirmed) and `C_UnitAuras.GetPlayerAuraBySpellID` exists — the
data behind them is what is hidden. This is the aura-secrecy branch of the
Midnight restriction system (`C_Secrets.ShouldUnitAuraInstanceBeSecret`
exists on the client) enforced in ordinary open-world combat on the beta,
not just in restricted content. Consequences: aura presence cannot drive
any mid-combat logic on this client, `UNIT_SPELLCAST_SUCCEEDED` remains
the only plain dynamic-haste signal, and the M1 script B2 aura probe
(`UnitAura` with Maelstrom stacks up) will error mid-combat on Forever —
run it out of combat.

## 5. What this means for the rescale gate

The gate at lines 621/636/655 is wrong for the dynamic family: the engine
rescales, the library does not, and every haste gain leaves the bar long for
up to one full swing. But removing the gate alone fixes nothing: mid-combat
`UnitAttackSpeed` is secret (§4.2), so `mainSpeedNew ~= unit.mainSpeed` can
never go true in combat — the classic rescale path has no speed source on
Forever regardless of the gate.

## 6. Fix design (IMPLEMENTED 2026-09-30, pending in-game verification)

- Rescale on Forever only when a **plain signal identifies the new speed**:
  on `UNIT_SPELLCAST_SUCCEEDED` of a spell in `dynamic_haste_spells`, apply
  the spell's haste factor to the cached speed and rescale the remaining
  time proportionally (`lib:ApplyDynamicHaste`, both hands). Slice and Dice
  rank 1 (5171): factor 1.2, verified by capture. Rank 2 (6774) percentage
  needs a probe (classic-era +30%) and stays out of the table until then.
  Unknown spell IDs keep current behavior (re-anchor at the next
  `PLAYER_SWING`).
- **Refresh guard**: a recast while the aura is already up must not rescale
  again — the engine does not (verified in the capture: refresh casts
  produce no anchor speed change). Implemented as `unit.dynamicHasteActive`
  (set on the first application, cleared by the first `PLAYER_SWING` anchor
  that reports a speed back above the hasted cache — the anchor payload is
  the expiry signal). Known corner: an expiry followed by a recast before
  any anchor reports gives one swing of bar error, self-correcting.
- **Young-swing guard** (added after the first smoke test): a cast landing
  at a swing boundary arrives after the `PLAYER_SWING` anchor has already
  re-anchored with the hasted payload (the engine applies the aura before
  the anchor fires — observed in the capture's 4637.832 window), so
  rescaling a swing younger than 50 ms would double-apply the factor.
  `ApplyDynamicHaste` skips swings that started less than 50 ms ago,
  per hand.
- Snapshot family (SotC ranks, druid forms): **no special handling** —
  the SotC control shows the library's next-swing re-anchoring is exactly
  right for this family in both directions, so absence from the table is
  the whole mechanism.
- Expiry: **no removal signal exists** — aura data is blocked mid-combat
  (section 4), so expiry lengthening cannot be mirrored; accept one-swing
  lag on expiry, self-corrected at the next `PLAYER_SWING` anchor.
  Documented. (A Blizzard API ask remains the long-term path: expose
  haste-application events or unhide aura presence for the player.)
- Stacking haste (SnD + proc auras) is unprobed; the table starts with
  verified spells only and grows by capture. Two simultaneous dynamic auras
  would share the single guard flag — rework to per-spell flags before
  adding a second dynamic spell.
- Classic flavors: zero behavior change (the table is populated and
  consulted on WoW: Forever only; `luajit -bl` clean).

### 6.1 In-game verification checklist (blocking for release)

**Smoke test 2026-09-30 16:15 (traced, rogue on a dummy) — items 1-3 pass:**
six SnD casts; the five fresh applications all fired `UNIT_SWING_TIMER_UPDATE`
for both hands at the cast instant with new speed 1.4025 (= 1.683/1.2) and
expiry = cast + remaining/1.2, matching the subsequent `PLAYER_SWING`
anchors within 0.002-0.089 s (the dispatch-skew scatter seen in the
capture); the one no-op cast was a refresh while SnD was active (engine-
matched, correct); the expire -> re-cast chain re-armed the rescale
correctly (the first post-expiry anchor reported 1.683, cleared the guard
flag, and the next fresh cast rescaled); the expiry one-swing lag is visible
as designed (one hasted swing landed 0.065 s after the library's
prediction). No parries occurred in the segment and no cast landed on a
swing boundary, so the parry interplay and the young-swing guard are not
yet exercised in-game.

1. **Forever rogue, SnD mid-swing**: with the rig's listener, cast SnD
   mid-swing — expect `UNIT_SWING_TIMER_UPDATE` for mainhand (and offhand
   if dual-wielding) at the cast instant with expiry ≈ cast +
   remaining/1.2, and the bar matching the engine's early landing.
   *Passed (traced, 2026-09-30 16:15).*
2. **Refresh**: recast SnD while it is active — expect NO further UPDATE
   (no double-hasten). *Passed (traced, 2026-09-30 16:15).*
3. **Expiry**: let SnD fall off mid-swing — expect no UPDATE (documented
   one-swing lag; the bar parks briefly and re-anchors at the next
   `PLAYER_SWING`). *Passed (traced, 2026-09-30 16:15).*
4. **Dungeon mid-fight**: no Lua errors; note whether the rescale still
   fires there (answers the player-`SUCCEEDED` secrecy question for
   restricted content empirically).
5. **Classic Era regression**: SnD on a rogue (or any haste aura) —
   identical behavior to 2.1.x (the classic rescale path is untouched).
6. **SotC sanity**: seal-juggle on the paladin — no UPDATE on SotC
   application or replacement, cadence tracking as before.
7. **Boundary cast**: cast SnD deliberately at the moment a swing lands —
   the young-swing guard must prevent a double-hasten (bar must not drop
   below the hasted speed).
8. **Parry interplay**: get parried while SnD is up — parry cut and haste
   rescale both apply to the same in-flight swing without conflict.

## 7. Open items

1. SnD rank 2 (6774) haste factor; other dynamic-family sources on Forever
   (haste potions, procs, Classic+ 7-digit spells).
2. Flurry coverage decision: aura presence is ruled out (section 4); the
   only remaining signal is `UNIT_COMBAT` `CRITICAL` on outgoing melee,
   which would need talent detection and uncorrectable 3-charge tracking.
   Default: leave Flurry at next-swing correction. A warrior/shaman capture
   (M2 confirmation + factor, classic +30%) is still worth having for the
   findings record regardless of the implementation decision.
3. The 4453 expiry overshoot (+0.085 over full new speed, single occurrence).
4. `UNIT_ATTACK_SPEED` fire behavior on Forever (does the event fire at all
   when speeds change?).
5. Player `SUCCEEDED` spell-ID secrecy in restricted instanced content
   (open-world combat verified plain by the SnD capture).
6. Re-examine the §8.5 dungeon "weapon swap 2.428 → 3.400" reading against
   the SotC-hasted hypothesis (2.428 = 3.4/1.4); the 2026-09-25 capture is
   not archived.
