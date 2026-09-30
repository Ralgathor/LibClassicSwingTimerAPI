# Haste application timing on WoW: Forever — investigation findings

Status: **unverified hypothesis, pending in-game capture.** No code changes made.
Source: user report (2026-09-30) that Slice and Dice appears to apply *during*
the current swing on the Forever beta, not from the next swing.

## 1. The report and the conflict

**Report:** on the Forever beta, a rogue's Slice and Dice seems to shorten the
in-flight swing (mid-swing haste application).

**Existing finding it conflicts with** (`FOREVER_API_FINDINGS.md` §8.9,
2026-09-25): "SotC mid-swing verified: in-flight swing completed on the old
schedule, NO mid-swing UPDATE (rescale gate works), completing swing reported
the new speed 1.714, new cadence from the next swing." This observation is
the entire basis for the shipped Forever rescale gate
(`LibClassicSwingTimerAPI.lua` lines 621/636/655: `and not isForever` —
in-flight swings are never rescaled on Forever).

## 2. The reconciliation: classic engines have two haste families, and the
SotC test only sampled the snapshot family

The library itself already encodes a two-family haste taxonomy on the classic
path (in the CLEU `SPELL_AURA_APPLIED/REMOVED` branch):

- `prevent_swing_speed_update` (Lua line 1077 block): Cat/Bear/Dire Bear Form
  and **all six Seal of the Crusader ranks (21082, 20162, 20305-20308)** —
  aura gained/removed mid-swing → `skipNextAttackSpeedUpdate = 2`: the next
  `UNIT_ATTACK_SPEED` rescale is suppressed, the in-flight swing completes on
  its old schedule, and the new speed applies from the next swing.
- Everything else — Slice and Dice, Heroism, haste potions and procs,
  Divine Shield — has no entry: the generic rescale path (line 621) runs
  mid-swing and rescales the remaining time proportionally
  (`timeLeft = remaining * newSpeed / oldSpeed`).

This is not library invention; it is the community-documented engine taxonomy.
WeakAuras2 issue #3205 ("Weapon Swing Timer incorrect behavior with haste
buffs", TBC, Jul 2021) records exactly this split, contested and confirmed in
the thread:

- TheSorm: "Devine Shield for example will be breaking the swing timer
  completly now since it changes the attack speed mid swing when its applied
  and when its taken off. On the other hand we have Seal of crusader which is
  snapshotted in both ways. When you apply SoC mid swing, the attack speed
  effect will only be applied after the next swing. When taking it off mid
  swing, the attack speed bonus stays on until the next swing." (Trinkets
  like Abacus: dynamic, no snapshot.)
- tasosgretsistas: "most haste effects in TBC ... are not snapshotted at the
  start of a swing but instead update remaining swing duration dynamically
  when they are applied / removed mid-swing ... You would need to specifically
  add the IDs of auras that do not snapshot."
- WeakAuras initially shipped a blanket "attack speed is snapshotted on TBC"
  change (commit 91bc69f) — the same over-generalization our Forever gate
  makes — and was argued out of it in the thread.

**Conclusion of the review:** the 2026-09-25 Forever observation is fully
consistent with Forever preserving the classic two-family taxonomy. SotC is
the one haste aura the classic engine itself snapshots at swing boundaries,
so that test could not have detected mid-swing rescaling. The
`and not isForever` gate turned a snapshot-family result into a Forever-wide
rule. The new SnD report matches the dynamic family and, if confirmed,
means the gate makes the library's bar lag the engine for up to one full
swing after every dynamic haste gain (the bar runs long; the engine's swing
lands early; `PLAYER_SWING` re-anchors at the next swing).

Supporting plausibility from the shipped parry work: the Forever engine
already demonstrably reschedules an in-flight swing mid-swing (parry haste
cuts the remainder with a 20% floor, verified millisecond-accurate on two
weapon speeds, `docs/evidence/README.md`) — an engine that can shorten an
in-flight swing for parries can do it for haste auras too.

## 3. What the archive can and cannot settle

The archived captures (2026-09-30, `docs/evidence/`) contain **no usable
haste-transition data**: all 1,193 `PLAYER_SWING` anchors run at constant
speed (929 at 2.4 s, 264 at 3.4 s), and the only self-applied auras in the
combat log are Light's Fury, Consecration, Seal of Fury, Seal of
Righteousness, Divine Protection, Forbearance and Blessings — none change
attack speed. (Divine Protection is absorbed, not attack speed.) The
question needs a new capture.

## 4. Candidate engine rules to discriminate

Weapon speed `S`, SnD cast at offset `t` into the swing (`0 < t < S`), hasted
speed `H` (classic SnD: `H = S / 1.3`; **do not assume** — read `H` from the
first fully-hasted period in the capture, Classic+ may have changed values).

Let `P` = period from the `PLAYER_SWING` before the cast to the one after
(single-channel gap — the parry work established these gaps are
millisecond-clean; the ~0.45 s pre-resolution lag is common to both anchors
and cancels out).

| Model | Rule | P at t=0.6 / 1.2 / 1.8, S=2.4, H=1.846 |
|---|---|---|
| M0 — snapshot (gate's current assumption) | in-flight swing unaffected | 2.400 / 2.400 / 2.400 |
| M2 — proportional-remaining (library classic model) | `P = t + (S - t) * H / S` | 1.985 / 2.123 / 2.262 |
| M3 — progress-preserving | `P = H` if `t < H` | 1.846 / 1.846 / 1.846 |

M0/M2/M3 are pairwise distinct at every offset; the three offsets
(25%/50%/75%) are enough to separate all three and to detect any floor or
clamping behavior. Also capture the **expiry direction**: SnD falling off
mid-swing — does the in-flight swing lengthen (dynamic removal), or complete
hasted (snapshot-on-expiry, the original WA #3205 report)? The classic
library model rescales in both directions; TheSorm claims both directions
are dynamic for the non-SoC family; the WA reporter observed the opposite
for expiry. Unknown for Forever — measure it.

## 5. Capture protocol (4everSwingTimer trace rig, single-channel analysis)

Client: WoW: Forever beta, `/console loglevel 2` + BugSack. Trace on:
`/4everswingtimer trace` (same rig as the parry evidence — records
`PLAYER_SWING <GetTime> <duration> <type>`,
`UNIT_SPELLCAST_SUCCEEDED <GetTime> player <castGUID> <spellID>`, and the
library's own UPDATE/START/STOP). `/combatlog` alongside is optional; the
decisive analysis needs only the trace (single clock, single channel — the
lesson from the parry join work).

Char: rogue, one combo-point SnD (1 CP = 9 s duration; enough for 3-5 hasted
swings). Weapon: the 2.4 s one if available; repeat on 3.4 s for the
two-speed rule check.

1. **Baseline:** auto-attack a dummy 10+ cycles; confirm the period matches
   the last-anchor cadence within ±20 ms (also confirms Sinister Strike used
   to build the combo point does not disturb the cadence — classic model
   says it must not; worth having in evidence).
2. **Gain, three offsets:** mid-swing, cast SnD at roughly 25%, 50%, and 75%
   of the period (aim by eye; the actual `t` is computed in analysis as
   `castTime - previous PLAYER_SWING time` from the trace — aim precision
   is not required). At least 2-3 repetitions per offset band.
3. **Expiry:** with SnD running, stop re-casting and let it fall off
   mid-swing; repeat 3+ times at different offsets.
4. **Control (SotC, expected M0):** same three offsets with Seal of the
   Crusader on the paladin — if SnD measures M2/M3 while SotC measures M0,
   the two-family taxonomy is confirmed on Forever verbatim.
5. **Secrecy probe (design-blocking — run before the melee captures):**
   mid-fight, with the rig's listener, record the SnD
   `UNIT_SPELLCAST_SUCCEEDED` spell ID and check `issecretvalue(id)`;
   also `/dump UnitAttackSpeed("player")` mid-fight to re-confirm SECRET,
   and probe whether `UNIT_ATTACK_SPEED` fires at all on SnD application
   (`/run UAS=UAS or CreateFrame("Frame") UAS:RegisterUnitEvent("UNIT_ATTACK_SPEED","player") UAS:SetScript("OnEvent",function() print("UAS",GetTime()) end)`).
6. **Dual-wield note:** SnD affects both hands. Filter `swingType 0`
   (mainhand) for the rule analysis; offhand periods are a free second
   dataset if the rogue is dual-wielding.

Expected library trace during the test: with the current gate, the rig should
log **no** `LIB_UNIT_SWING_TIMER_UPDATE` mid-swing on SnD application — the
engine (if M2/M3) landing early is then visible as a period shorter than the
rig's bar predicted. Any mid-swing UPDATE in the log means the gate leaked —
investigate before trusting the run.

## 6. Library implications if confirmed (design notes, nothing implemented)

- The gate at lines 621/636/655 is over-broad. The classic two-family model
  is the correct target: **dynamic family → rescale mid-swing (M2);
  snapshot family (SotC, druid forms) → no rescale, new speed at the next
  swing.** The snapshot exception on Forever cannot ride the CLEU
  `SPELL_AURA_APPLIED` path (dead there); it would need a
  `UNIT_SPELLCAST_SUCCEEDED`-driven skip keyed on the SotC rank IDs.
- **The real blocker is detection, not the rule:** mid-fight,
  `UnitAttackSpeed` returns secret values, so `ResolveSecret` falls back to
  the cache and the rescale condition
  (`mainSpeedNew ~= unit.mainSpeed`) can never go true in combat — the
  classic rescale path is inoperable on Forever even without the gate.
  Candidate plain-channel signals for the new speed at application time:
  - `UNIT_SPELLCAST_SUCCEEDED` spell ID (verified plain in the §4.3 session,
    but that predates the 4.3 correction; the START-on-target secrecy makes
    re-verification mandatory — hence the probe in step 5) + a per-spell
    haste table (SnD 30%, Blazewind, haste potions, procs...). Stacking
    behavior and Classic+ values would need their own probes.
  - Aura inspection (`UnitAura`/`C_UnitAuras`) — secrecy on Forever
    unverified for auras; the M1 script B2 probe uses it out of combat only.
  - Expire-direction mirroring additionally needs aura-removal detection,
    which has no plain verified channel today (step 3's capture should note
    what fires when SnD falls off: `UNIT_AURA`? `UNIT_COMBAT`? nothing?).
- Until detection is solvable, the gate's behavior (bar correct at every
  swing, imprecise for at most one swing after a haste change) is the safe
  degraded mode; the fix should land together with a speed signal that
  works in restricted content, not as a bare gate removal.

## 7. Open questions

- Which family do Classic+ haste effects belong to (7-digit IDs, e.g. the
  paladin Classic+ seals seen in the join captures)? Unknown until probed.
- Does the engine treat the *expiry* of a dynamic-family haste as dynamic
  (M2 lengthen) or snapshot (complete hasted)? Contradictory community
  evidence; measure (step 3).
- Does `PLAYER_SWING`'s `swingDuration` during SnD read the hasted speed
  (H)? The §8.9 SotC capture read the new speed at the completing swing —
  the SnD capture should confirm the same for the dynamic family.
- Is there a floor on mid-swing haste shortening (a parry-haste-style
  20%-remaining floor)? The 25% offset trials will show it if it exists.
