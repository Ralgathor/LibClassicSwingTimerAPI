# Haste application timing on WoW: Forever — investigation findings

Status: **VERIFIED by capture** (rogue Slice and Dice session, 2026-09-30
15:41, build 70124). Evidence: `docs/evidence/4everSwingTimer-2026-09-30-snd.lua`
(verbatim SavedVariables copy) and `docs/evidence/WoWCombatLog-093026_154137.txt`.
No code changes made yet; the fix design is in section 6.

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

## 3. The two-family taxonomy on Forever

The classic library path already encodes the split: `prevent_swing_speed_update`
(druid forms + SotC ranks 21082, 20162, 20305–20308) suppresses the mid-swing
rescale — the snapshot family; everything else rescales (line 621). The
community record (WeakAuras2 issue #3205, TBC) documents the same split and
SotC as "snapshotted in both ways". On Forever:

- **Dynamic family**: SnD confirmed mid-swing, both directions (this capture).
- **Snapshot family**: SotC observed next-swing-only (§8.9, 2026-09-25).
  No same-session control was run in this capture; the taxonomy claim rests
  on those two independent observations.

The §8.9 SotC test was therefore never evidence about the dynamic family —
the `not isForever` gate over-generalized a snapshot-family result, exactly
as WeakAuras did with commit 91bc69f before being argued out of it.

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

## 5. What this means for the rescale gate

The gate at lines 621/636/655 is wrong for the dynamic family: the engine
rescales, the library does not, and every haste gain leaves the bar long for
up to one full swing. But removing the gate alone fixes nothing: mid-combat
`UnitAttackSpeed` is secret (§4.2), so `mainSpeedNew ~= unit.mainSpeed` can
never go true in combat — the classic rescale path has no speed source on
Forever regardless of the gate.

## 6. Fix design (proposed, not implemented)

- Rescale on Forever only when a **plain signal identifies the new speed**:
  on `UNIT_SPELLCAST_SUCCEEDED` of a known dynamic-haste spell, apply the
  spell's haste factor to the cached speed and rescale the remaining time
  proportionally (both hands). SnD rank 1 (5171): x1/1.2, verified by this
  capture. Rank 2 (6774) percentage needs a probe (classic-era +30%).
  Unknown spell IDs: keep current behavior (re-anchor at the next
  `PLAYER_SWING`).
- Snapshot family (SotC ranks, druid forms): no rescale — matching both the
  classic path's `prevent_swing_speed_update` and the §8.9 Forever
  observation. The skip must be SUCCEEDED-driven on Forever (no CLEU).
- Expiry: no plain removal signal verified (`UNIT_AURA` secrecy unprobed),
  so expiry lengthening cannot be mirrored yet — accept one-swing lag on
  expiry, self-corrected at the next `PLAYER_SWING` anchor. Documented.
- Stacking haste (SnD + proc auras) is unprobed; the factor table should
  start with verified spells only and grow by capture.

## 7. Open items

1. SotC control run in the same style as this capture (expected M0) — closes
   the taxonomy as same-session evidence.
2. SnD rank 2 (6774) haste factor; other dynamic-family sources on Forever
   (haste potions, procs, Classic+ 7-digit spells).
3. The 4453 expiry overshoot (+0.085 over full new speed, single occurrence).
4. `UNIT_ATTACK_SPEED` fire behavior on Forever (does the event fire at all
   when speeds change?).
5. Player `SUCCEEDED` spell-ID secrecy in restricted instanced content
   (open-world combat verified plain by this capture).
