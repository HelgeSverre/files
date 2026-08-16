version := "0.2.0"
bin := "bin/files"

# List recipes.
[private]
default:
    @just --list

# Ensure the Nim compiler is available.
[private]
_nim:
    @command -v nim >/dev/null 2>&1 || { echo "files: nim not found — install it from https://nim-lang.org/install.html" >&2; exit 1; }

# Build the optimized binary at bin/files.
[group('build')]
build: _nim
    mkdir -p bin
    nim c -d:release --opt:speed -o:{{bin}} files.nim

# Build and run files in the current directory.
[group('run')]
run: build
    ./{{bin}} .

# Remove build output.
[group('build')]
clean:
    rm -rf bin nimcache

# Run the ignore-matcher test suite.
[group('test')]
test: _nim
    nim c -r --hints:off --path:. tests/test_ignore.nim

# Build and install files to a directory on your PATH.
[unix]
[group('install')]
install dest="~/.local/bin": build
    mkdir -p {{dest}}
    install -m 0755 {{bin}} {{dest}}/files
    @echo "Installed files to {{dest}}/files"
    @echo "Ensure {{dest}} is on your PATH."

# Remove the installed binary.
[unix]
[group('install')]
uninstall dest="~/.local/bin":
    rm -f {{dest}}/files
    @echo "Removed {{dest}}/files"

# Cut a release: bump the embedded version, tag, and push. CI builds the
# platform binaries and publishes the GitHub Release. Usage: `just release 0.3.0`
[group('release')]
release version:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! git diff-index --quiet HEAD --; then echo "✗ working tree is dirty, commit or stash first" >&2; exit 1; fi
    if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then echo "✗ not on main branch" >&2; exit 1; fi
    # Bump the embedded version string so `files --version` matches the tag.
    perl -pi -e 's/const VersionStr = "files [0-9.]+/const VersionStr = "files {{version}}/' files.nim
    git add files.nim
    git commit -m "Bump version to {{version}}"
    git tag -a "v{{version}}" -m "files v{{version}}"
    git push origin main
    git push origin "v{{version}}"
    echo "→ tagged v{{version}}. watch CI: https://github.com/HelgeSverre/files/actions"
