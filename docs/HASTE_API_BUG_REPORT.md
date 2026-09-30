# Bug report draft: attack-speed changes during a swing are invisible to every swing-timer API on WoW: Forever — including the built-in swing timer

Status: draft, 2026-09-30. Companion to `PARRY_HASTE_BUG_REPORT.md` (same
beta, same rig; that report covers event pipeline timing, this one covers
the missing speed-change signal). Evidence:
`HASTE_APPLICATION_FINDINGS.md` and `docs/evidence/` (verbatim captures).

Filed in two forms: the in-game beta reporter (character-limited) and the
full forum / WoW UI Discord version below.

## In-game short form (254 characters — the reporter caps at 255; self-contained)

```
b70124: mid-swing haste shortens the in-flight swing (verified, lands early) but no API surfaces it: no PLAYER_SWING speed-change signal, UNIT_ATTACK_SPEED secret in combat, auras blocked. Built-in swing timer runs long too. Ask: event or aura whitelist.
```

## Full version (forum / dev thread)

Title: Mid-swing attack-speed changes are invisible to every swing-timer
API on WoW: Forever — including the built-in swing timer — leaving every
swing bar wrong for up to a full swing after each haste gain and each haste
expiry

Build: WoW: Forever beta, 1.60.1 (build 70124), Interface 16001.

Method: verbatim SavedVariables event traces (PLAYER_SWING with its
duration payload, UNIT_COMBAT, UNIT_SPELLCAST_SUCCEEDED, ms timestamps)
plus the client's own advanced combat log; a rogue Slice and Dice session
(19 casts, 13 clean mid-swing windows), a paladin Seal of the Crusader
control session (7 windows), a paladin Redoubt proc capture, and in-client
secrecy probes. The built-in timer claim is read straight from
`Blizzard_SwingTimer.lua`.

Finding 1 — the engine rescales the in-flight swing, both directions. When
Slice and Dice (5171) is applied mid-swing, the running swing is shortened
proportionally: a cast at offset t into a swing of speed S lands at
t + (S − t)/1.2 — 13 measured windows at 25–82% offsets, predictions
matching actual landings within event jitter (0.002–0.089 s). Expiry
lengthens the in-flight swing the same way (measured). A control shows the
engine distinguishes two families: Seal of the Crusader (20162) applies
from the next swing only, in both directions (7 windows, snapshot
behavior). So the engine changes swing timing mid-swing, differently per
aura family — and no API tells an addon either happened.

Finding 2 — no API surfaces the change.
- `PLAYER_SWING` fires once per swing with the duration the swing started
  with; there is no update/speed-change event (`PLAYER_SWING_UPDATE` does
  not exist).
- `UNIT_ATTACK_SPEED` fires, but its values are secret on this client
  whenever combat restrictions are active — an addon can store but not
  compare or compute with them, so the rescale classic addons do is
  impossible here.
- The combat log is refused for addons (CLEU registration silently fails).
- Player `UNIT_SPELLCAST_SUCCEEDED` is plain and carries cast-driven haste
  (that is how our library mirrors Slice and Dice today), but proc auras
  fire no cast success — verified with a Redoubt capture: four
  applications, zero SUCCEEDED events on any spell ID.
- Aura data is blocked mid-combat for every aura probed: Slice and Dice
  (5171), Seal of the Crusader (20162), Redoubt (20128), Devotion Aura
  (10290), Retribution Aura (7294) all return ContextuallySecret from
  `C_Secrets.GetSpellAuraSecrecy`; `C_UnitAuras.GetPlayerAuraBySpellID`
  returns nil mid-combat with the aura active, while the same call out of
  combat returns full data including a plain duration — the channel is
  complete and switched off only by the classification.

Finding 3 — the built-in swing timer has the same hole. In
`Blizzard_SwingTimer.lua`, PLAYER_SWING calls
`ResetSwingTimer(duration)` → `swingEndTime = GetTime() + duration`, and
the UNIT_ATTACK_SPEED handler only updates range-check registration and
shown state — it never rescales the running bar. Consequences, all
reproducible on a training dummy: after a mid-swing Slice and Dice cast
the built-in bar runs long and the swing lands early (the bar is still
draining when the attack fires); when a dynamic haste expires mid-swing
the bar reaches zero and clears while the swing is still resolving.
Every addon swing timer that uses the public API is wrong the same way,
for up to one full swing per haste change, in both directions.

Asks — any one of these closes the gap:

1. A speed-change event for swing timers (e.g. the nonexistent
   `PLAYER_SWING_UPDATE`, or a mid-swing PLAYER_SWING re-fire) carrying
   the new duration and the change instant; or
2. NeverSecret aura classification for the player's own self-haste auras
   (Slice and Dice, Flurry ranks): the secrecy mechanism is live on this
   build (`Enum.SecrecyLevel.NeverSecret`, per-spell via
   `C_Secrets.GetSpellAuraSecrecy`), the aura API path is fully functional
   whenever the classification permits it (verified out of combat:
   spell ID, applications, plain duration), and retail already populates
   this whitelist by community request (Maelstrom Weapon). Classifying
   these auras would let addons read presence and expiry timing directly,
   with no other client change.

Repro for the triager (1 minute): rogue on a training dummy, enable the
built-in swing timer (Edit Mode if hidden), auto-attack, cast Slice and
Dice mid-swing — the bar does not move while the swing lands early; let
Slice and Dice expire mid-swing — the bar clears before the swing fires.
