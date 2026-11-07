# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-11-07

### Added
- Environment defaults via `FILES_DEPTH`, `FILES_ICONS`, `FILES_SIZES`,
  `FILES_GIT`, `FILES_ALL`, `FILES_DEFAULTS`, and `FILES_COLOR`, alongside
  existing `FILES_COMPACT` and `FILES_COLOR_THEME` settings
- `--icons`, `--git`, `--defaults`, and `--no-all` to override environment
  preferences in either direction; all boolean settings use the same values
- Environment help and README reference, with CLI and `NO_COLOR` precedence

### Fixed
- Help, version, and completions remain available with invalid environment
  preferences; overridden preferences do not trigger validation errors
- Depth values below `-1` are rejected rather than silently treated as unlimited

## [0.3.1] - 2026-11-07

### Fixed
- Move release builds to macOS 15 after GitHub retired macOS 14 runners

## [0.3.0] - 2026-11-07

### Added
- Optional folder-chain compaction via `--compact` and `FILES_COMPACT`, with
  `--no-compact` to override it; every folder segment retains its depth color
- Rendering, CLI, environment, completion, and filesystem integration tests
  for directory compaction

## [0.2.6]

### Added
- `--root` flag: alias for `--depth=1 --no-git`
- `--completions <shell>` (alias `--completion`): generate shell completion
  scripts for zsh, bash, fish, and nu

### Changed
- Readability refactor: `WalkContext`/`DirWalk` context objects (entry handling
  dropped from 13 args to 4), clarified matcher naming, `main()` split into
  named phases, and doc comments on the walk recursion contract

### Performance
- Dropped the dead `ATTR_FILE_TOTALSIZE` request from bulk directory
  enumeration (~25% faster on large directories) and removed the unused size
  parsing

### Fixed
- Staged and unstaged rename/copy badges now attach to the destination path,
  and Git status queries are scoped to the inspected subtree instead of the
  entire repository
- Walking a directory that is itself ignored by an ancestor `.gitignore` now
  treats that directory as a visibility boundary, while still honoring its own
  and nested ignore files; this prevents ignored scratch/workspace directories
  from rendering as an empty tree
- `isIgnored` (test reference matcher) now delegates to the production
  `isIgnoredActive` so the two can't diverge again (they disagreed on Windows
  path separators)
- Fallback enumeration skips a single bad entry instead of dropping the rest
  of its directory; bulk errors fall back to `walkDir` instead of silently
  returning a partial directory
- Path component matching now handles up to 256 components (was silently
  truncating deeper paths); `humanSize` no longer overflows on absurd file
  sizes
- Footer change count is scoped to the walked subtree (matches the badges
  shown) instead of reporting the whole repository's changes

### Added
- Named structural color themes (`blue`, `purple`, `green`, `red`, `orange`,
  `yellow`, and the existing `rainbow`) via `--theme` or `FILES_COLOR_THEME`;
  each theme chooses the starting hue for the depth-based color rotation
- Standard color control via `--color=auto|always|never` and `NO_COLOR`, with
  `--no-color` retained as an alias
- Regression suites for CLI configuration, rendering, and Git status parsing
- Per-platform `.tar.gz` archives attached to every release (for Homebrew and
  other package managers)
- MIT license, README screenshot
- `scripts/render-formula.sh` and automatic Homebrew formula publishing to
  `HelgeSverre/homebrew-tap` on every tagged release

## [0.2.1] - 2026-08-16

### Fixed
- macOS `x86_64` release asset was actually an `arm64` binary — `--cpu:amd64`
  does not cross-link on arm64 macOS; added `-arch x86_64` pass flags so the
  shipped binary is genuinely `x86_64`
- Replaced deprecated `std/threadpool` (whose arch-specific inline asm broke the
  macOS cross-build) with portable `std/typedthreads`

### Changed
- Git status is fetched on a background thread overlapping the tree walk, roughly
  halving run time on small repositories
- `Makefile` replaced with a fedit-style `justfile`
  (`just build` / `just test` / `just install` / `just release`)

## [0.2.0] - 2026-08-16

### Added
- Windows support: no-op interrupt handling on Windows, dual `/` and `\` path
  separator matching for gitignore rules, and a Windows CI build job
  (`files-windows-x86_64.exe` release asset)
- `install.sh` extended to Windows (Git Bash)
- CI installs Nim from official tarballs (linux-arm64 previously failed because
  `choosenim` does not support it)

## [0.1.0] - 2026-08-16

### Added
- Initial release: a fast, git-aware directory tree
- Gitignore-aware by default — native matching for negation, anchored paths,
  directory rules, `**`, wildcards, and nested `.gitignore` files; works outside
  a git checkout
- Git status badges (staged / modified / untracked / conflict) and branch in the
  footer
- Depth-gradient box-drawing connectors, Nerd Font icons, right-aligned sizes,
  natural sorting, and terminal-width truncation
- Clean SIGINT / SIGTERM handling
- Built-in junk-directory ignores (`node_modules`, `target`, …) with
  `--no-defaults` to disable
- Batch directory enumeration via `getattrlistbulk` on macOS for large trees
- Release CI building binaries for macOS (arm64 + x86_64) and Linux
  (arm64 + x86_64), plus an install script

[Unreleased]: https://github.com/HelgeSverre/files/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/HelgeSverre/files/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/HelgeSverre/files/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/HelgeSverre/files/compare/v0.2.6...v0.3.0
[0.2.6]: https://github.com/HelgeSverre/files/compare/v0.2.1...v0.2.6
[0.2.1]: https://github.com/HelgeSverre/files/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/HelgeSverre/files/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/HelgeSverre/files/releases/tag/v0.1.0
