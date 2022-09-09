# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added Rune Strike on the list of next_melee_spells.

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
