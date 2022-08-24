# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Add logic to ignore some Attack speed update. Prevent to update swing timer on UNIT_ATTACK_SPEED when Druid shapeshift.
- Add spell id for swing spell reset for Warlok, Mage and Priest Shoot ability.
- Add swing timer pause logic (Warrior Slam mechanic).

### Fixed
- Fix Aura prevent swing reset check logic. Prevent looping multiple time in unit buff and correctly check spellId on prevent_reset_swing_auras Object.
- Fix Parry haste calculation. 

## [1.0.0] - 2022-08-23

### Added
- Initial version of the lib based on [SwingTimerAPI weakaura](https://wago.io/mfxY37Jl9)
