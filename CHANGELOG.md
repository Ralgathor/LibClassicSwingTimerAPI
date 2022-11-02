# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
