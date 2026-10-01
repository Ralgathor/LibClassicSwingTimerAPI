# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

## [2.2.0-beta3] - 2026-10-01

Known unverified in this build: a live in-game run of the Forever parry-haste back-date and dynamic-haste rescale, a direct outgoing-parry capture, and the Classic Era regression pass.

### Added

* Real-time parry haste on WoW: Forever. `UNIT_COMBAT` is live on that client, fires with plain unitIDs mid-combat, and discriminates direction: a defensive parry by the player fires the `player` token. The library now registers it on WoW: Forever and shortens the in-flight main-hand swing on `player` + `PARRY`, via an `ApplyParryHaste` helper shared with the classic CLEU handler (classic behavior unchanged).

* Real-time dynamic-haste application on WoW: Forever. Captures (build 70124) show Forever keeps the classic two-family haste taxonomy: dynamic auras (Slice and Dice) rescale the in-flight swing immediately, while snapshot auras (Seal of the Crusader) apply at the next swing. On a successful cast of a dynamic-family spell, the library now rescales the in-flight main-hand and off-hand swings - with guards against recasts while the aura is already up and against double-applying at a swing boundary; unknown haste spells keep the next-swing behavior, and classic flavors are untouched. Measurement details: `docs/HASTE_APPLICATION_FINDINGS.md`.

### Fixed

* Fix the parry-haste formula (all clients) to the documented classic rule: a parry with more than 60% of the swing remaining cuts the remainder by 40% of weapon speed, 20-60% reduces the swing to 20% remaining, under 20% does nothing. Earlier Forever readings suggesting engine deviations were artifacts of event-stream dispatch delays; `ApplyParryHaste` now back-dates the parry by 0.65 s on WoW: Forever before applying the rule (the classic CLEU path is unchanged). Evidence: `docs/PARRY_HASTE_BUG_REPORT.md`.

* Fix a hard Lua error in `getUnit` in restricted content on WoW: Forever and 12.x clients: a mid-combat `UnitGUID("target")` returns a secret string that `PLAYER_TARGET_CHANGED` cached, so every subsequent GUID comparison errored. Secret GUIDs now degrade to matching by unit id only.

* Fix a hard Lua error in the `UNIT_SPELLCAST_*` handlers in restricted content on WoW: Forever and 12.x clients: a secret spell ID in the event payload cannot index the spell-ID tables. Secret IDs now degrade to "unknown spell" - cast-state flags still update (so the cast-based swing reset still fires), while spell-ID lookups and spell-specific special cases are skipped.

### Changed

- Internal cleanup, no behavior change: a shared ReadAttackSpeeds helper for the
  secret-guarded UnitAttackSpeed read, a shared Unit:ResetTransientState for the
  identical state clears on PLAYER_ENTERING_WORLD / PLAYER_TARGET_CHANGED, the dead
  `and unit` condition removed from the CLEU SPELL_CAST_START branch, the identical
  main-hand reset hoisted out of the retail split in UNIT_SPELLCAST_CHANNEL_STOP, and
  the Forever/classic event registration folded into one if/else.


## [2.2.0-beta2] - 2026-09-28

Known unverified in this beta: off-hand anchoring on WoW: Forever (dual-wield `PLAYER_SWING`) and the Classic Era regression pass - feedback welcome.

### Added

* WoW: Forever support — detected via the interface build range (`WOW_PROJECT_ID` is unreliable there), routed to the Classic-era spell tables and swing behavior. Swing detection uses the native `PLAYER_SWING` event (payload verified readable in restricted content, where `UnitAttackSpeed` returns secret values); CLEU is not registered because the client refuses it. Target swing tracking has no Forever data source and is unsupported; parry haste is reflected at the next swing rather than mid-swing, pending a dedicated API (request filed with Blizzard).

### Changed

* Bump TOC interface builds: Retail 12.1.0 and 12.1.5 (120100, 120105), Classic Era 1.15.9 (11509).
* On WoW: Forever, ranged weapon speed is now read from the third `UnitAttackSpeed` return (probe-verified: equal to `UnitRangedDamage` and the `PLAYER_SWING` payload where readable) with `UnitRangedDamage` as fallback, matching the source Blizzard's own swing timer uses. Classic clients keep `UnitRangedDamage` unchanged.
* Harden the WoW: Forever `PLAYER_SWING` payload check: reject non-number, NaN, non-positive and infinite swing durations in addition to secret values, so a malformed payload cannot be cached as a weapon speed.
* Guarded all weapon-speed reads with `issecretvalue()` (12.x restriction system): when values are secret mid-combat, the library keeps the last cached speed instead of erroring. On WoW: Forever, `UNIT_ATTACK_SPEED` changes never rescale an in-flight swing (the engine applies new speeds at the next swing), so the rescale is skipped there.
* Feign Death watcher now uses a `GetSpellCooldown` / `C_Spell.GetSpellCooldown` compatibility shim (the old global was removed in retail 11.0) and anchors to `GetTime()` when the cooldown start is a secret value. Fixes a hard Lua error on first Feign Death cast on retail 11.x+ and WoW: Forever.
* The `UNIT_SPELLCAST_FAILED_QUIET` ranged handling now also runs on WoW: Forever (verified event and spell IDs), and the `channeling` flag is cleared on interrupts, fails and combat enter as hardening (movement-cancelled channels can end silently on 12.x clients).
* Collapse the duplicate retail/classic clip branches in `SwingEnd` (no behavior change) and document the intended retail main-hand-only clip behavior (in-game verified).
* Remove the tautological expansion check from Mists of Pandaria detection.
* Spell tables now default to empty tables, so unknown future client flavors degrade gracefully instead of raising nil-index errors.
* Internal cleanup, no behavior change: drop the unused `tonumber`/`GetSpellInfo` upvalues and the dead `GetSpellInfo` call in `UNIT_SPELLCAST_START`, remove redundant `and unit` guards after the early return in the combat-log handler, hoist the duplicated ranged-swing start out of the `SWING_DAMAGE` branches, and remove duplicate Mists spell entries.

### Fixed

* Fix the auto-attack toggle guard on WoW: Forever: the client fires the toggle as spell 6803 instead of classic's 6603, so the cast-state guards did not protect it — toggling auto-attack during a cast cleared the casting flag prematurely and skipped that cast's swing reset. Both toggle IDs are now recognized, with 6803 only on WoW: Forever.
* Fix duplicate melee swing anchor on WoW: Forever: a consumed next-melee ability (Heroic Strike, Cleave, Raptor Strike, Maul) fired the swing-timer START twice — once from the spellcast event and once from the native `PLAYER_SWING` anchor of the same swing. The spellcast anchor is now skipped on WoW: Forever, mirroring the ranged Auto Shot fix.
* Swing timers now stop on player death: `PLAYER_DEAD` cancels each active hand timer, fires `UNIT_SWING_TIMER_STOP` for it and clears cast/channel/attack state, on every client. Previously the bars sat stale after an in-place resurrection, which does not fire `PLAYER_ENTERING_WORLD`.
* Fix target unit lookup in `getUnit`: the second branch compared against the player id instead of the target id, so `UnitSwingTimerInfo("target", ...)` never returned data. `getUnit` is also guarded against being called before the units exist at load time.
* Fix parry haste handling: the PARRY combat-log branch was unreachable, so a defender never had its swing accelerated after a parry. The branch now runs before the source lookup, applies to both player and target, and only modifies an in-flight main-hand swing timer.
* Fix off-hand speed of player targets: `PLAYER_TARGET_CHANGED` checked a never-assigned `lib.isPlayer` instead of `target.isPlayer`, mirroring the main-hand speed onto the off-hand for every target.
* Fix off-hand expiration initialization in `PLAYER_ENTERING_WORLD`: it was computed from the main-hand swing and speed.
* Fix off-hand pause check in `UNIT_SPELLCAST_START`: it compared the main-hand expiration instead of the off-hand expiration.
* Fix ranged speed reads in `SwingStart` and `UNIT_ATTACK_SPEED`: `UnitRangedDamage` was hardcoded to the player, corrupting the target unit's ranged timer.
* Fix orphaned ranged timer in the classic `SPELL_CAST_START` handler: the previous timer was not cancelled and could end the fresh timer early.
* Fix Feign Death watcher ticker: a previous ticker is now cancelled before creating a new one, the ticker is cancelled when its unit is reset, and it gives up after 10 seconds if the cooldown is never observed.
* Fix `skipNextAttackSpeedUpdateCount` decrementing past zero (`tonumber(0)` is truthy in Lua).
* `WeakAuras.ScanEvents` now forwards the full event payload instead of only the unit id.

## [2.1.6] - 2026-09-24

### Changed

* Bump build version support of Retails.
* Bump build version support of Classic.
* Bump build version support of Burning Crusade Classic.
* Bump build version support of Wraith.
* Bump build version support of Mists of Pandaria.

### Fixed

* Fix TBC Steady Shot spell id (34120) in the no-reset swing spell list. Steady Shot no longer resets the melee swing timer on Burning Crusade Classic. Fixes #54.
* Fix undeclared global in UNIT_ATTACK_SPEED. A non-player target's offhand attack speed now correctly mirrors its mainhand. Fixes #56.

## [2.1.5] - 2025-07-07

### Changed

* Removed Heroic Throw from list of reset_swing_spells for Mists of Pandaria.
 
## [2.1.4] - 2025-07-07

### Added
* Add version support for Mists of Pandaria.

### Changed

* Bump build version support of Retails.
* Bump build version support of Classic.
* Bump build version support of Cataclysm.

## [2.1.3] - 2024-09-04

### Changed
* Improve first autoshot swing calculation.
* Maelstrom Weapon in SoD P4 prevents swingtimer reset.
* Bump build version support of Classic.

## [2.1.2] - 2024-05-18

### Fixed
* Fix auto shot cast time calculation. 

## [2.1.1] - 2024-05-17

### Changed
* Improve ranged swing timer accuracy for Classic version. Implemented cast time and retry logic of auto shot.

### Fixed
* Added missing UNIT_ATTACK_SPEED update for ranged.
* Fix Autto Attack/Auto Shot interaction for Cataclysm version.

## [2.1.0] - 2024-05-15

### Added
* Add WeakAuras EVENTS handler. Fire the lib events in Weakaura if the addon is loaded.

## [2.0.10] - 2024-05-14

### Fixed
* Add Feral Spirit to the reset_swing_spells list for Cataclysm version.

## [2.0.9] - 2024-05-14

### Fixed
* Add Lava Burst to the reset_swing_spells list for Cataclysm version.

## [2.0.8] - 2024-05-13

### Fixed
* Fixed attack speed update logic for Paladin in Classic version.

## [2.0.7] - 2024-05-13

### Fixed
* Fixed extra attacks logic. Extra attacks gain always reset swing timer. Removed skip next attack event logic to reflect current in game behavior.

## [2.0.6] - 2024-05-13

### Added
* Add version support for Cataclysm.

### Changed
* Bump build version support of Retails.
* Bump build version support of Classic.

## [2.0.5] - 2023-11-20

### Changed
* Bump build version support of Retails.
* Bump build version support of Classic.

## [2.0.4] - 2023-10-11

### Added
* Add Heroic Throw to the list of spells that reset swing timer.

### Changed
* Bump build version support of Retails.
* Bump build version support of Classic.
* Bump build version support of Wraith.

## [2.0.3] - 2023-07-13

### Added
* Add Shattering Throw to the list of spells that reset swing timer.

### Changed
* Bump tocversion support of Retails.
* Bump classicversion support of Wraith.

## [2.0.2] - 2023-03-31

### Changed
* Update tocversion support of Retails.

### Fixed
- Fix lib:UNIT_ATTACK_SPEED function unitGUID param.
- Fix Druid specific UNIT_ATTACK_SPEED handler. Spells that remove a druid form and reset the swing now correctly update the swing information. 
- Fix lib:ADDON_LOADED function. Allows lib:ADDON_LOADED to correctly initialize when another addon embeds the library.

## [2.0.1] - 2023-01-18

### Fixed
- Fix LUA error on SwingEnd method call.

## [2.0.0] - 2023-01-13

### Added
- Added support for target swing timer info.
- Added API EVENTS that reflect both player and target support with following format UNIT_SWING_TIMER_.
- Backward compatibility of previous API EVENTS with SWING_TIMER_ format for player unit.
- New api method UnitSwingTimerInfo to get swing informations for a specific unit.
- Added Backward compatibility for SWING_TIMER_INFO_INITIALIZED event

### Changed
* Update support of Retails to Dragonflight.
* Bump Wraith version to Ulduar patch.

## [1.4.2] - 2022-11-02

### Fixed
- Added timer nil check for SwingEnd method. Prevent nil value error.

## [1.4.1] - 2022-10-07

### Fixed
- Druid attack speeds are no longer snapshotted when the druid's form changes when the swing timer is full
- Druid attack speed changes following mid-swing form changes are now correctly reported when the swing ends.
- Fix Slam pause. Prevent LUA error when Slam is casting without autoattack toggled on or if auto attack is toggle of during the cast.
- Fix main and off hand timer cancellation on UNIT_ATTACK_SPEED event. Prevent timer to be cancelled when the UNIT_ATTACK_SPEED is not modify.

## [1.4.0] - 2022-09-26

### Added
- Added a callback event that gets fired once the library has been properly initialised, to let addons know they can start using the library's SwingTimerInfo method.

### Fixed
- Fix consistency of SWING_TIMER_STOP event fire logic.

## [1.3.2] - 2022-09-10

### Changed
- Update spells data.

### Fixed
- Removed Auto Shot from the reset_swing_spells for Retails. Auto Shot reset is managed with the ranged_swing list for this game version.

## [1.3.1] - 2022-09-07

### Changed
- Setup lib variables on PLAYER_ENTERING_WORLD instead of ADDON_LOADED.

### Fixed
- Fix Paladin Seal of the Crusader snapshot logic for Classic version. Prevent UNIT_ATTACK_SPEED update when aura is gained or removed.
- Fix Ranged swing reset logic for Classic version compatibility.

## [1.3.0] - 2022-09-05

### Added
- Added support for all active game version.
- Added Retails swing reset specificity.
- Added game version ranged swing reset specificity.
- Added swing reset on channeled spell stop.
- Project now supports BigWigs packager and now no longer contains source of other embeds

### Fixed
- Fix preventSwingReset flag. Prevent flag from being stuck to true after channeling a spell.
- Fix to version detection logic
- Attack speeds are now repolled 3s after addon init to resolve UnitAttackSpeed wrongly returning zero on first load of the game.

## [1.2.0] - 2022-08-30

### Added
- Add Feign Death ranged swing reset.

## [1.1.1] - 2022-08-29

### Canged
- Changed the logic to set prevent_reset_swing_auras flag. Set the value on SPELL_AURA_APPLIED and SPELL_AURA_REMOVED instead of setting the value on UNIT_SPELLCAST_START.

### Fixed
- Fix auto attack speed change offhand.

## [1.1.0] - 2022-08-27

### Added
- Added logic to ignore some Attack speed update. Prevent to update swing timer on UNIT_ATTACK_SPEED when Druid shapeshift.
- Added spell id for swing spell reset for Warlok, Mage and Priest Shoot ability.
- Added swing timer pause logic (Warrior Slam mechanic).
- Added LibStub version managment.
- Added channelled spell interaction logic.
- Added auto shot timer reset on Hunter Volley damage.

### Changed
- Init the Lib variable after ADDON_LOADED event.

### Fixed
- Fix Aura prevent swing reset check logic. Prevent looping multiple time in unit buff and correctly check spellId on prevent_reset_swing_auras Object.
- Fix Parry haste calculation.
- Fix target unit event handle as player unit event. Add unit value test that insure to only handle player events.
- Fix auto attack spell cast reseting casting flag.
- Fix ranged speed value. Remove multiplier logic as UnitRangedDamage API method now return the correct ranged speed value.

## [1.0.0] - 2022-08-23

### Added
- Initial version of the lib based on [SwingTimerAPI weakaura](https://wago.io/mfxY37Jl9)
