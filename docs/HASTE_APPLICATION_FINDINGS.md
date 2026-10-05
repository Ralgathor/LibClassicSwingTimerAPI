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
  `prevent_swing_speed_update` and rides the generic rescale. **Open
  question on Forever: does the proc fire
  `UNIT_SPELLCAST_SUCCEEDED`?** The classic-engine assumption is no (proc
  auras are not casts). An earlier revision of this section cited the
  `CastBar-`-tagged trace events (spells 8617, 647) as evidence that
  non-cast applications surface on SUCCEEDED — **retracted**: the combat
  log identifies 8617 as Skinning, a real cast with a progress bar (the
  `CastBar-` tag marks bar casts, not engine-internal applications);
  647 appears nowhere in the combat log and is unidentified. The question
  is open with no supporting evidence either way. **Closed by proxy capture
  (2026-09-30 16:47, Redoubt): NO — a talent-proc aura does not fire
  `UNIT_SPELLCAST_SUCCEEDED` on this client.** Four Redoubt applications
  (aura spell ID 20128; two `SPELL_AURA_APPLIED`, two
  `SPELL_AURA_REFRESH` on re-proc; 5 dose-charges consumed per block via
  `SPELL_AURA_REMOVED_DOSE`, expiry at 10 s) produced no SUCCEEDED event on
  any spell ID at the proc instants — the trace's SUCCEEDED channel
  demonstrably works (it recorded the session's real casts: Seal of Fury,
  Judgement, the attack toggle), and the combat log has no
  `SPELL_CAST_SUCCESS` with 20128; the spell appears only in AURA events.
  The capture also verifies the rewritten trigger live: the procs follow
  ordinary non-critical incoming WOUND events, not crits — matching the
  Forever tooltip (10% per damaging melee hit). **Flurry therefore cannot
  ride the shipped trigger and stays at next-swing correction** (bar long
  for the in-flight swing after each crit, correct for the rest of the
  proc; both hands are re-anchored by `PLAYER_SWING`). The only theoretical
  alternative remains the `UNIT_COMBAT`-crit machinery (talent detection
  plus uncorrectable 3-charge tracking), which is not recommended;
  a Blizzard API (haste-application event or unhidden aura presence)
  remains the long-term path. **Flurry is rebalanced on Forever**
  (client-read tooltips, wowforevertalents.com, build 70124):
  trigger unchanged (procs on dealing a melee critical strike, next 3
  swings) but values lowered — warrior and shaman rank 1 is +5% (Classic
  +10%), rank 5 is +25% (Classic +30%). If coverage ever becomes
  possible, `dynamic_haste_spells` entries are per-rank (factors 1.05 to
  1.25) and must be measured by capture; the Classic +30% expectation
  does not apply on this client.
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

### 7.1 Aura access — source-level analysis and the per-spell secrecy path
(2026-09-30, follow-up to "can we access aura information anyway?")

Side channels assessed against the retail UI source
(`Gethe/wow-ui-source`, `Blizzard_AuraContainer/Blizzard_AuraContainerUtil.lua`
— Forever runs this architecture):

- **Reading the stock buff frame is closed by design**: the Blizzard UI
  applies auras to its own buttons via `texture:SetTexture(secretwrap(icon))`
  and `fontString:SetText(secretwrap(name))` — icon paths and spell names
  are themselves wrapped, so scanning `BuffFrame` children for texture
  paths cannot recover identity mid-combat.
- **Aura secrecy is per-spell policy, not a blanket block**: the stock code
  calls `C_Secrets.GetSpellAuraSecrecy(auraData.spellId)` and compares
  against `Enum.SecrecyLevel.NeverSecret` — spells classified never-secret
  are readable and filterable even mid-combat (the source cites
  Exhaustion/Sated as examples). **Probed on the beta (build 70124):
  `Enum.SecrecyLevel` = { NeverSecret=0, AlwaysSecret=1,
  ContextuallySecret=2 }, and every aura probed returns
  ContextuallySecret (2): Slice and Dice (5171), Seal of the Crusader
  (20162), Redoubt (20128), Devotion Aura (10290), Retribution Aura
  (7294).** Note the paladin aura spell IDs are renumbered on Forever
  (Devotion 10290 vs Classic 465, Retribution 7294 vs 7291) —
  classic-era aura IDs do not carry over. The NeverSecret whitelist
  mechanism exists in this client but nothing probed populates it on this
  build — readable out of combat only, hidden whenever restrictions are
  active. That is the factual basis for the request below.
  **Functionally confirmed mid-combat (build 70124): with Devotion Aura
  active, `C_UnitAuras.GetPlayerAuraBySpellID(10290)` returns nil during
  combat** — the ContextuallySecret classification is behaviorally
  verified, not just reported by the classification query. **And out of
  combat the same call returns full data** — spellId 10290, applications
  0, `issecretvalue(a.duration)` false (a plain number): the entire
  presence-plus-expiry channel works whenever restrictions are not
  active. This makes the ask maximally concrete: the API path is fully
  functional on this exact build, so classifying the swing-timer auras
  NeverSecret would make them readable mid-combat with no other change.
  The aura-access investigation is closed: no aura channel exists
  mid-combat on this client, by any getter tried - by-ID nil, by-index throw, and (probed 2026-10-04, next bullet) by-name nil in combat.
- **By-name probed and closed (2026-10-04, build 70205, SwingTestLog capture; rogue, two SnD fights plus a Well Fed control)**: `C_UnitAuras.GetAuraDataBySpellName("player", "Slice and Dice", "HELPFUL")` returned nil at every in-combat probe - including the aura's application instants themselves (each CAST 5171 landed with a simultaneous UNIT_AURA fire whose by-name read was nil, while the hasted anchors 1.683->1.403 / 1.782->1.485 prove the aura active) - and the identical call on the same aura instance answered with full plain data the moment combat ended (PLAYER_REGEN_ENABLED probe: id=5171, plain 9 s duration and expirationTime, issecretvalue false, secrecy 2). The Well Fed control (1248406) read plain out of combat; no throw anywhere - the by-name gate is a silent nil, not the by-index error. UNIT_AURA fires reliably mid-combat at every application and removal instant, so the event edge exists while only the data query is gated - which sharpens the NeverSecret ask above into its strongest form (same call, same aura, plain data the instant restrictions lift). ForeverSwing's tier-1 claim is refuted in combat on this build (out of combat it does answer); its seal icon's in-combat display is its tier-3 fallback alone, as 4everSwingTimer's SPEC 10.5 triage assumed. The same capture re-verified on the new build (libMinor 37): SnD rank 1 factor 1.2 both hands, the documented one-swing expiry lag, secrecy 2 for 5171 and 1248406. Evidence: docs/evidence/SwingTestLog-forever-2026-10-04.lua (the 19:38 onward sessions).
- **Retail runs a community-request whitelist process** (12.0 planned API
  changes): Maelstrom Weapon, Skyriding spells, the GCD spell and
  combat-res spells received aura/cooldown secrecy exemptions on request;
  `SecureAuraHeaderTemplate` improvements are planned; player secondary
  resources (combo points) are being unsecreted; `C_UnitAuras` APIs are
  being replaced by duration objects as the sanctioned path.

Consequences:

1. **The durable fix is now a concrete, evidence-backed ask**: request
   NeverSecret classification (or a swing-timer carve-out) for the player's
   own haste auras on WoW: Forever — Slice and Dice, Flurry — citing the
   Maelstrom Weapon precedent and the probed classifications (all three
   swing-relevant auras currently ContextuallySecret, so mid-combat
   swing-timer addons have no aura signal at all). This slots into the
   existing Blizzard API report alongside the haste-application-event ask.
2. **Probes to run** (in addition to the secrecy-classification one-liners
   above): `GetComboPoints("player","target")` mid-combat with combo
   points up (if secondary resources are unsecreted here, SnD expiry
   becomes schedulable from the cast timestamp — duration is a known
   function of combo points, 9–21 s — closing the expiry gap with no
   aura data at all); the `COMBAT_TEXT_UPDATE` `AURA` payload
   (`GetCurrentCombatTextEventInfo()` returned nil for PARRY; AURA is a
   different message type and untested); `COMBAT_LOG_EVENT_BASIC` is
   **confirmed nonexistent** (registration throws "unknown event" —
   distinct from the silent-false refusal of restricted events).
3. Flurry's remaining non-aura path stays the outgoing-crit trigger
   (`UNIT_COMBAT` `WOUND CRITICAL` on target tokens, rank factor from
   the talent tree read out of combat) — bounded machinery, implementable
   without any new API, pending a Flurry capture at a higher level cap.
4. **The UNIT_AURA edge channel is the one aura signal that survives combat (found 2026-10-04, same capture) - a probe-gated inference lead, not a data channel.** UNIT_AURA fired at every application and removal instant mid-combat: all four SnD application edges were simultaneous with their CAST SUCCEEDED (0 ms), and the mid-combat removal edges landed +49 ms and +2 ms after the cast+9 s expectation (build 70205) - while every data read stayed dark. The edge is unidentified, but the library knows when to EXPECT an edge for a tracked dynamic aura: application at the SUCCEEDED instant, removal at cast + learned duration. Watching for an edge inside an expected-expiry window (+/-0.25 s) would fire the un-haste rescale at the actual expiry instead of waiting for the next PLAYER_SWING anchor - closing the section 6 one-swing lag without any aura data - and an outgoing crit plus a simultaneous application edge would upgrade item 3's Flurry trigger from guess to confirmed application. Measured failure mode: unattributed edges ran ~1 per 10 s in the capture's solo open-world fights (2 in 21.6 s, 1 in 20.7 s), higher in groups, so attribution needs tight windows plus two unprobed corroborators that gate the whole design: `C_UnitAuras.GetAuraCount("player","HELPFUL")` mid-combat (a plain count gives every edge a +/- direction and cuts false attribution; existence and readability unprobed - SwingTestLog now logs it on every UNIT_AURA fire, and its session CAPS line records existence) and `GetComboPoints("player","target")` mid-combat (item 2 above: a plain read makes SnD's expected expiry exact, shrinking the watch window from 9-21 s to milliseconds; SwingTestLog logs it via /stl cp). If either lands, file the edge-inference design; if both are dark, the edge channel alone is too ambiguous to act on and the NeverSecret ask stays the only path. SwingTestLog-automated probes: M1_SESSION_SCRIPT B5. **Evening session update (2026-10-04, build 70205):** `C_UnitAuras.GetAuraCount` does not exist on this client (session CAPS line count=false) - the direction corroborator is CLOSED by nonexistence. `GetComboPoints` exists (cp=true) and answered a plain number mid-combat (CP 0.000, sec=false), but that read landed 2.3 s after the SnD cast consumed the points, so the decisive positive-points read is still missing: one `/stl cp` right after a builder strike settles it. If positive points read plain, the expiry-window watch survives in weakened form for SnD (exact expected instant from CP at cast - the OOC read showed dur=12.000 for a 2-CP cast, confirming the classic 9+3(n-1) duration function on this client - no direction corroboration, ~5% misattribution per expiry at the measured churn, self-correcting at the next anchor); if they read secret, the lead is closed and the NeverSecret ask is the only path. Flurry refinement: proc auras fire no cast (Redoubt proxy), so crit-plus-simultaneous-edge is the only application confirmation for them - and the crit-instant edge simultaneity itself is uncaptured (all six 0 ms instances are cast-class applications; the cheapest capture is the Redoubt paladin proxy re-run with the current tool, the direct case a Flurry warrior at a higher cap). Under the classic rule Flurry's expiry is swing-count driven (3 hasted swings consume the charges), so unlike the SnD half it needs no combo-point read at all - the library owns the swing stream; verify the engine rule on capture. Night note: both manual `/stl cp` reads landed at 0 points (the first mid-combat 2.3 s after the SnD cast consumed them, the night one out of combat 5 s before the pull - the 20:31 fight proves the window existed: Backstab then CAST 5171 succeeded, and a successful SnD cast requires points). Manual timing is too fragile for this probe; SwingTestLog now auto-logs `CP at-snd` at every SnD cast (5171/6774) - an instant where points are guaranteed up mid-combat - so the next SnD cast in any fight settles the gate with no user timing. **RESOLVED - the gate is OPEN (2026-10-04 night session, build 70205): `CP at-snd 1.000 sec=false` and `CP at-snd 2.000 sec=false` - GetComboPoints answers plain POSITIVE values mid-combat at the cast instants.** The full inference chain is captured end to end mid-combat: cast 5837.353 (CP 1, plain) -> duration 9+3(n-1)=9 (the function is engine-verified against the OOC by-name reads: dur=12.000 for the 2-CP cast) -> expected expiry 5846.353 -> fade edge at 5846.353 EXACTLY (0 ms). The design is implementable as filed: timing-only attribution (no count corroborator exists on this client), exact expected expiry from the at-cast CP read, a +/-0.25 s edge window, the next-anchor self-correction as the fallback. Two conditions from the same capture: the CP read must be taken at the SUCCEEDED instant and degrade to the current one-swing-lag behavior when secret (restricted-content CP is unprobed), and one out-of-combat fade near a reload boundary fired late (+1.96 s, post-reload session) - irrelevant to the mid-combat watch, whose three instances land at 0/+49/+2 ms. Family addition (2026-10-04 review lead): the hunter talent proc Wowhead-Forever lists as spell 19552 "Deadly Aspects" - classic-era 19552 is Quick Shots, the Improved Aspect of the Hawk ranged-attack-speed buff - is the third edge-inference family member and the easiest: its application trigger IS the ranged swing (PLAYER_SWING type 2, which the library already logs, so the application correlate needs no new signal beyond the edge), and its duration is fixed in classic data (12 s), so the expiry watch needs only the application instant plus the learned duration - no combo-point read. Forever renumbering/renaming is documented (the paladin auras), so ID, name, duration and per-rank factor all need the standard capture (classic reference: 10 percent chance per ranged attack, haste 3/6/9/12/15 percent by talent rank, 12 s - verify per rank on this client, the SnD-rank-2 lesson); SwingTestLog captures it with no tool change (M1_SESSION_SCRIPT B6). CORRECTION (2026-10-05 review): the application half of that claim was overstated - an aura-gain edge at a swing instant is expected from ANY on-hit effect (weapon enchants, trinket and talent procs key off the same swings), so swing+edge is a candidate generator, not an identification; the false-positive rate at swing instants is structurally higher than the ambient churn because on-hit effects land there by construction. The design consequence: a candidate edge arms a tentative factor application to the in-flight shot, and the NEXT PLAYER_SWING anchor settles it - its plain speed payload confirms a real proc (hasted) or reverts a false candidate (unchanged), one shot of bounded error, self-correcting, the same error class as the expiry watch - with the expected fade edge at +duration as the temporal cross-check. Flurry's crit correlate carries the same class (on-crit procs coincide with crits); the settler is identical. The B6 capture must therefore also measure the false-candidate rate: edges at swing instants followed by an UNCHANGED anchor speed, against real proc applications (anchor speed drops). Second correction (2026-10-05, user review): Flurry is NOT in that class - its classic trigger is DETERMINISTIC (every melee crit applies or refreshes it while talented), so the crit alone is the application signal and the edge is optional corroboration; item 3's crit-trigger path stands alone with no candidate stage, and the probabilistic candidate+anchor-settler design is Deadly Aspects-only (its 10 percent chance per ranged attack is what makes the swing uninformative). Flurry's remaining unknowns are engine-rule verification on Forever (every crit triggers it? both hands? refresh-on-crit) and the per-rank factor - a warrior capture answers both; the Redoubt edge-simultaneity re-capture is demoted to nice-to-have. UNIT_ATTACK_SPEED note (2026-10-05 review): the event fires live in combat (weapon swap and SotC haste change, findings section 9 item 3) while the UnitAttackSpeed data reads behind it are secret in ALL combat - so it is unusable as a data source (the reason the classic rescale path is disabled on Forever) but usable as an anonymous attack-speed change EDGE, and a far tighter candidate generator for Deadly Aspects than the aura edge: it fires only on real attack-speed changes, so the on-hit-proc noise class does not apply (enchant/trinket procs that do not change attack speed do not fire it). Whether it fires at dynamic/proc-haste APPLICATION instants is open item 4 below (the verified fires are a weapon swap and a snapshot-family SotC change) - SwingTestLog now logs ATKSPEED lines on every fire with the secrecy flags, so any future capture answers it; the design's anchor side is unaffected either way (PLAYER_SWING swingDuration is probe-verified plain even in restricted content, and the library guards it). Layered-design conclusion (2026-10-05, on "can UNIT_ATTACK_SPEED unify the three hands"): no as a rescale source - a rescale needs the new speed value and that is exactly what is secret (the payload carries only the unit token; no hand, no value, so not even the direction of the correction is known) - but yes as a universal Layer-1 edge beneath the per-family work: on fire, mark all in-flight expiries stale and pre-arm the early-landing convergence - no factor needed, source-agnostic (covers trinket haste procs, potions, weapon procs and every source with no other signal), up to one swing earlier than the first anchor would reveal it, with the per-hand anchors still settling each hand (no hand attribution exists in the payload). Layer 2 stays the per-family factors (identified casts/crits/candidates). Unverified and now captured by the ATKSPEED lines: whether ranged-only and off-hand-only changes fire the player event at all (the verified fires are main-hand context - weapon swap and SotC), and whether it fires at proc instants (open item 4). Capture verdicts (2026-10-05 morning, build 70205, the SPEED/ATKSPEED-instrumented session): (1) The section 4.2 secrecy rule is re-verified - plain out of combat (the combat-leave read shows the ACTIVE hasted values, mh=1.403/oh=1.485 with SnD up, so plain out-of-combat reads include live haste), secret mid-combat (the at-cast read: all three returns <secret>), with a NEW boundary nuance: the combat-ENTER instant still reads plain (1.683/1.782/1.980, sec=false, at PLAYER_REGEN_DISABLED) - the restriction flip lands after the event. (2) Open item 4 RESOLVED for the dynamic-haste class: UNIT_ATTACK_SPEED fired exactly at the SnD cast instant (2456.057, simultaneous with CAST 5171, mid-combat, secret payload) AND at its expiry (2468.367, +0.30 s after the fade edge, plain), plus at the login equipment-stream completion. (3) The event DOUBLE-FIRES per change - two identical lines at every instant (a long-standing classic-era quirk); any consumer must dedupe. Consequence: the Layer-1 edge and the Deadly Aspects candidate generator are now evidence-backed for the dynamic class; the ranged-only proc case (Quick Shots) still needs the hunter capture (M1 B6). Transition-parity design (2026-10-05, user-driven convergence): UNIT_ATTACK_SPEED is the single unified trigger for the whole dynamic-haste family, with direction from a tracked per-hand state rather than from data. Application: ATKSPEED simultaneous with an identified cast (SnD - proven, 0 ms) or with an outgoing crit (Flurry, deterministic) - factor from the identification. Fade: ATKSPEED with no identified trigger in the window - un-haste immediately with progress-preserving lengthening (the +0.30 s fade fire is known from the capture), killing the one-swing expiry lag; the next anchor confirms. This SUPERSEDES the CP+duration+fade-edge-window watch as the primary SnD expiry mechanism (the validated CP chain becomes corroboration, and remains the fallback if fade-fire proves unreliable for some source) and eliminates Flurry charge-counting (the ATKSPEED fade replaces it; the charge count stays as a cross-check). Deadly Aspects gain/fade discrimination - the one the aura edges cannot give - follows from transition parity: (1) ATKSPEED fires only on actual speed transitions (PREDICTION, capture-pending: no fire on refresh, since a refresh changes no speed value - consistent with the event semantics and the verified engine refresh behavior); (2) the combat-enter instant reads PLAIN (proven 2026-10-05: the restriction flip lands after PLAYER_REGEN_DISABLED), so the handler initializes the per-hand hasted state at combat start; (3) each subsequent fire is a transition whose direction follows from the tracked state - not hasted means GAIN, hasted means FADE - with the next anchor of the changed hand confirming and correcting. Caveat: parity is binary per hand; two simultaneous sources with different factors give three speed levels and can misattribute the toggled source - the anchor settler reconciles values, but factor bookkeeping is needed once stacking is possible (single-active-source dominates at the beta level cap). Verifications: SnD recast while active (rogue, any session - expect NO fire); Flurry charge-0 fire (warrior capture); the B6 hunter transitions (~12 s apart); bracket the combat-enter plain window (/stl speed in the first seconds). Transition-parity verification, round 1 (2026-10-05, build 70205, two SnD fights with deliberate recasts): REFRESH-NO-FIRE CONFIRMED twice - recast while SnD was active (5-7 s remaining) produced NO ATKSPEED fire at either, proving transitions-only firing and making the refresh guard automatic. Fade fire confirmed twice more (3 total) with precision +93 ms and -24 ms against the CP-formula expiry - and both fades match the RECAST duration (9 s), not the original (12 s): the replace-on-recast rule confirmed, and the CP formula and the engine transition agree to tens of milliseconds. Application fire confirmed twice more (4 total, all simultaneous with the cast), double-fire at every instant, the combat-enter plain window twice more, and CP read plain mid-combat at 1.000 and 2.000. ONE GAP: every fade fire observed so far landed OUT OF COMBAT (the mobs died first) - the mid-combat fade fire, the case the design needs to kill the in-combat one-swing lag, is still unobserved; next check: a training dummy (the fight survives the expiry), cast SnD, keep attacking through it - expect ATKSPEED x2 at the expiry with a SECRET payload mid-combat. Transition-parity verification, round 2 - the design is COMPLETE for the SnD family (2026-10-05, build 70205, the training-dummy fight with the fade mid-combat): the fade fired ATKSPEED x2 at 3544.161, +412 ms after the CP-formula expiry, payload <secret>, deep in combat (the fight ran 14 more seconds), with the engine transition visible in the same log - hasted anchors (1.403/1.485) up to 3543.694, the fire, then unhasted anchors (1.683/1.782) from 3544.779; the fire landed 620 ms before the first unhasted anchor, and in the worst case that gap is a full swing - exactly the one-swing lag the un-haste-at-fire kills. A fresh SnD cast after the fade fired ATKSPEED again (unhasted-to-hasted transition), completing the parity alternation within one fight. ALL rogue-side pillars are now confirmed: transitions-only firing (refresh, no fire), application fire at the cast instant (5 instances), fade fire in combat (secret payload) and out (plain, 3 instances, -24 to +412 ms of the CP-formula expiry), the combat-enter plain state-initialization window, double-fire (dedupe), and CP corroboration. The SnD implementation is no longer capture-gated: the library can apply the factor at cast+SUCCEEDED and un-haste at a no-crit/no-cast ATKSPEED fire, with the next anchor settling and the CP chain as cross-check. Remaining unknowns live only on the warrior (Flurry charge-0 fire) and the hunter (Deadly Aspects gain/fade pair). Snapshot-family coexistence rule (2026-10-05, from the implementation-conflict review): NO conflict with the transition-parity design, PROVIDED the ATKSPEED handler classifies its triggers - because the two families need OPPOSITE actions on the same event. The snapshot family DOES fire UNIT_ATTACK_SPEED (the two originally verified fires were both snapshot-class: a weapon swap and the SotC haste change), and its rule is M0, engine-verified in both directions: the in-flight swing completes on the speed it started with; the new speed applies at the next anchor. So the handler classification: fire + SUCCEEDED of a DYNAMIC-table spell or an outgoing crit -> apply the factor, flip the tracked state; fire with no identified trigger while a dynamic source is tracked -> un-haste; fire + SUCCEEDED of a NON-dynamic spell (seals, forms) or PLAYER_EQUIPMENT_CHANGED -> NO action - no rescale, no state flip, the next anchor re-anchors (the existing M0 mechanism, untouched); fire with no identified trigger and nothing tracked -> untracked candidate, anchor settles. Paladins and druids carry no tracked dynamic source, so the un-haste rule is inert for them by construction - every fire they produce falls in the snapshot row. DESIGN CORRECTION from this review: the Layer-1 sketch (mark all in-flight expiries stale on any fire) is WRONG for snapshot fires - M0 means the in-flight expiry is NOT stale (the swing completes on its old schedule); the stale-mark applies only to UNEXPLAINED fires (trinket-class transitions). Edge case carried: a weapon swap while a tracked dynamic source is active - the fire is identified (no un-haste), and the next anchor must re-anchor on the new weapon base WITH the dynamic factor still applied (new speed = new base / factor); the weapon-swap path and the dynamic guard must compose. Implementation plan: docs/TRANSITION_PARITY_PLAN.md (2026-10-05) - Phase A (Rules 1, 3, 4 + the dedupe and classification windows) is fully evidence-backed and coded against the v2.2.0 function map; Phases B (Flurry, deterministic) and C (Deadly Aspects, parity candidates) are scaffolded and activate on their captures.

1. SnD rank 2 (6774) haste factor; other dynamic-family sources on Forever
   (haste potions, procs, Classic+ 7-digit spells). - plus the hunter Improved Aspect of the Hawk proc (Wowhead-Forever "Deadly Aspects", classic-era 19552 Quick Shots): a ranged proc-class member with a fixed classic duration (12 s) whose application correlates with PLAYER_SWING type 2, the easiest full-cycle family member (capture: M1_SESSION_SCRIPT B6).
2. ~~Flurry surfacing question~~ — **resolved 2026-09-30 by the Redoubt
   proxy capture: proc auras do NOT fire
   `UNIT_SPELLCAST_SUCCEEDED`** (section 3.2). Flurry stays at
   next-swing correction; revisit only if Blizzard exposes a
   haste-application event or unhidden aura presence. If a Flurry capture
   ever runs at a higher level cap, it would still be recorded for the
   taxonomy (family confirmation + per-rank factors 1.05-1.25).
3. The 4453 expiry overshoot (+0.085 over full new speed, single occurrence).
4. `UNIT_ATTACK_SPEED` fire behavior on Forever (does the event fire at all SwingTestLog now logs every fire (ATKSPEED lines with the secrecy flags): any future capture answers the dynamic/proc-haste application case - the verified fires so far are a weapon swap and a snapshot-family SotC change, and the event is also the tight-semantics candidate generator for the Deadly Aspects design (section 7.1 item 4). **RESOLVED for the dynamic-haste class (2026-10-05, build 70205):** fires at the SnD application instant (simultaneous with the cast, mid-combat, secret payload) and at the expiry (+0.30 s after the fade edge, plain), double-fires per change (dedupe), and fires at the login equipment-stream. The ranged-only and proc-class cases still need the B6 hunter capture.
   when speeds change?).
5. Player `SUCCEEDED` spell-ID secrecy in restricted instanced content
   (open-world combat verified plain by the SnD capture).
6. Re-examine the §8.5 dungeon "weapon swap 2.428 → 3.400" reading against
   the SotC-hasted hypothesis (2.428 = 3.4/1.4); the 2026-09-25 capture is
   not archived.
