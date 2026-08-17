# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Readability refactor: `WalkContext`/`DirWalk` context objects (entry handling
  dropped from 13 args to 4), clarified matcher naming, `main()` split into
  named phases, and doc comments on the walk recursion contract

### Performance
- Dropped the dead `ATTR_FILE_TOTALSIZE` request from bulk directory
  enumeration (~25% faster on large directories) and removed the unused size
  parsing

### Fixed
- `isIgnored` (test reference matcher) now delegates to the production
  `isIgnoredActive` so the two can't diverge again (they disagreed on Windows
  path separators)
- Fallback enumeration skips a single bad entry instead of dropping the rest
  of its directory; bulk errors fall back to `walkDir` instead of silently
  returning a partial directory

### Added
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

[Unreleased]: https://github.com/HelgeSverre/files/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/HelgeSverre/files/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/HelgeSverre/files/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/HelgeSverre/files/releases/tag/v0.1.0
