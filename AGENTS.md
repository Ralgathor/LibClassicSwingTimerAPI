# AGENTS.md

Guidance for AI coding agents working in this repository.

These rules apply to every task unless explicitly overridden by the user. Bias: caution over speed on non-trivial work; use judgment on trivial tasks.

## Working rules for agents

1. **Think before coding.** State assumptions explicitly. If uncertain, ask rather than guess — especially for spell IDs and expansion-specific behavior, where a wrong guess ships a broken release to every downstream addon.
2. **Simplicity first.** Minimum code that solves the problem. Nothing speculative. This is an embedded library: extra surface area is public API forever.
3. **Surgical changes.** Touch only what you must. Don't "improve" adjacent code, comments, or formatting. Don't refactor what isn't broken. Match existing style.
4. **Goal-driven execution.** Define success criteria before starting (e.g. "event fires on both hands in Era and Wrath, no Lua errors, README updated") and work toward them. Don't stop at "the edit landed".
5. **Use deterministic checks, not judgment, for deterministic work.** Syntax validation is `luac -p`, not a careful read. Counting, diffing, and searching are shell work. Reserve reasoning for design and ambiguity.
6. **Surface conflicts, don't average them.** If two spell lists or code paths contradict each other, pick the more recent/tested one, explain why, and flag the other for cleanup. Don't blend conflicting patterns.
7. **Read before you write.** Before editing a spell list or event handler, grep for every place the spell/event is referenced — the same spell name may appear in several expansion lists or in both `UNIT_` and legacy event paths. "Looks orthogonal" is dangerous.
8. **Checkpoint after every significant step.** Be able to state what was done, what is verified, and what is left. If you can't describe the current state, stop and restate it.
9. **Match the codebase's conventions, even if you disagree.** Conformance over taste. If a convention seems harmful, surface it rather than forking silently.
10. **Fail loud.** "Completed" is wrong if anything was skipped. Since there is no test suite, nothing is "verified" until the in-game check described below has run — say so plainly when it hasn't.

## Project overview

LibClassicSwingTimerAPI is a World of Warcraft addon **library** (not a standalone addon) that reconstructs melee/ranged swing-timer state and exposes it via LibStub as custom events. Consumers are other addons and WeakAuras. Public API compatibility is critical: many downstream addons embed this library, so breaking changes are effectively forbidden.

## Repository layout

- `LibClassicSwingTimerAPI.lua` — the entire implementation. All code changes happen here.
- `LibClassicSwingTimerAPI.toc` — addon manifest with per-expansion `## Interface-*` build numbers and the `## Version`.
- `LibClassicSwingTimerAPI.xml` — frame/template XML.
- `README.md` — full API documentation (events, methods, WeakAuras examples). Update it when the public API changes.
- `CHANGELOG.md` — Keep a Changelog format, SemVer.
- `.pkgmeta` — BigWigs packager config. External libs (LibStub, CallbackHandler-1.0) are pulled at package time.
- `.github/workflows/package_and_release.yml` — release pipeline (BigWigsMods/packager@v2), triggered by pushing a tag. Publishes to CurseForge, Wago, and GitHub releases.
- `chaman-aura.txt` — reference data, not code. Do not treat as build input.

Do not commit `Libs/` or `.release/` — they are generated and gitignored.

## Key conventions

### Multi-expansion support

The library runs on Retail, Classic Era, BCC, Wrath, Cata, and Mists, detected via `WOW_PROJECT_ID` / `LE_EXPANSION_LEVEL_CURRENT` flags near the top of the Lua file. Behavior differs per expansion:

- Expansion-specific spell lists (`reset_swing_spells`, `noreset_swing_spells`, `pause_swing_spells`, etc.) are populated per flavor. Spell IDs differ between expansions — verify IDs against the correct expansion (e.g. Steady Shot is 34120 in TBC but not the retail id).
- When adding or changing spell handling, check every expansion's list, not just one.
- When Blizzard bumps build numbers, update all `## Interface-*` lines in the `.toc`.

### Versioning

A release touches three places, in this order:

1. `local MAJOR, MINOR = "LibClassicSwingTimerAPI", N` in the Lua file — the LibStub minor version. Bump `N` for **any** change to the library file, or LibStub will not reload it for addons that embed it.
2. `## Version: x.y.z` in the `.toc`.
3. `CHANGELOG.md` entries with `### Changed` / `### Fixed` / `### Added`.

**Changelog convention:** new entries go only under a `## [Unreleased]` section at the top of `CHANGELOG.md`. Do not append changes to an existing versioned release block (e.g. `## [2.1.5] - 2025-07-07`). Moving `[Unreleased]` entries into a versioned block (renaming the section, adding the version and date, and creating a fresh empty `[Unreleased]`) is a deliberate release action, not part of routine fix or feature work. Pre-existing versioned sections predate this convention — leave them as they are.

### Backward compatibility

The library fires both `UNIT_SWING_TIMER_*` events (with unitId, for player and target) and the older `SWING_TIMER_*` events (player only). Both sets must keep firing. Do not remove or rename public events or the `SwingTimerInfo` / `UnitSwingTimerInfo` methods.

### Lua style

- Tabs for indentation; files use CRLF line endings.
- WoW API functions are localized into upvalues at the top of the file (`local GetSpellInfo, GetTime, ...`). Follow this pattern for any new API calls in hot paths.
- Event handlers are `function lib:EVENT_NAME(...)` methods on the library table.
- Declare every variable `local` — the WoW environment is shared, and stray globals have caused real bugs here (e.g. issue #56).

## Building and testing

There is no build step, test suite, or linter configured. Verification options:

- Syntax check: `luac -p LibClassicSwingTimerAPI.lua` (or `luajit -bl`), if a Lua 5.1 interpreter is available. Note the file uses WoW-only globals, so it cannot be executed outside the game.
- Real verification is manual: log into each applicable WoW flavor with `/console loglevel 2` and watch for Lua errors (`BugSack`/`!BugGrabber` help), and confirm the swing timer events fire with a test consumer.

The game client cannot be launched from the shell; do not attempt to run servers or watchers.

## Release process

Releases are cut by pushing a git tag matching the `.toc` version (e.g. `2.1.6`). The GitHub Actions workflow packages via the BigWigs packager (`.pkgmeta`) and publishes to CurseForge and Wago using repo secrets. Agents must not push tags or releases without explicit instruction — pushing a tag triggers a public release to three platforms.
