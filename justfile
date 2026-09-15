version := `cat VERSION`
bin := "bin/files"

# List recipes.
[private]
default:
    @just --list

# Ensure the Nim toolchain is available.
[private]
_nim:
    @command -v nim >/dev/null 2>&1 || { echo "files: nim not found — install it from https://nim-lang.org/install.html" >&2; exit 1; }
    @command -v nimble >/dev/null 2>&1 || { echo "files: nimble not found — it ships with Nim, check your PATH" >&2; exit 1; }

# Build the optimized binary at bin/files.
[group('build')]
build: _nim
    nimble build -d:release --opt:speed

# Build and run files in the current directory.
[group('run')]
run: build
    ./{{bin}} .

# Remove build output.
[group('build')]
clean:
    rm -rf bin nimcache

# Run all unit and integration test suites.
[group('test')]
test: _nim
    nimble test

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

# Uninstall then install.
[unix]
[group('install')]
reinstall dest="~/.local/bin": (uninstall dest) (install dest)
    @echo "Removed {{dest}}/files"

# Bump major/minor/patch and cut a release. Usage: `just bump patch` (default)
[group('release')]
bump level="patch":
    #!/usr/bin/env bash
    set -euo pipefail
    current="{{version}}"
    IFS=. read -r major minor patch <<< "$current"
    case "{{level}}" in
      major) major=$((major + 1)); minor=0; patch=0 ;;
      minor) minor=$((minor + 1)); patch=0 ;;
      patch) patch=$((patch + 1)) ;;
      *) echo "✗ unknown level '{{level}}' (expected major, minor, or patch)" >&2; exit 1 ;;
    esac
    new="$major.$minor.$patch"
    echo "bumped $current -> $new"
    just release "$new"

# Cut a release: write VERSION, commit, tag, and push. CI builds the
# platform binaries and publishes the GitHub Release. Usage: `just release 0.3.0`
[group('release')]
release version:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! git diff-index --quiet HEAD --; then echo "✗ working tree is dirty, commit or stash first" >&2; exit 1; fi
    if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then echo "✗ not on main branch" >&2; exit 1; fi
    if git rev-parse -q --verify "refs/tags/v{{version}}" >/dev/null; then echo "✗ tag v{{version}} already exists" >&2; exit 1; fi
    echo "{{version}}" > VERSION
    if git diff --quiet -- VERSION; then
      echo "VERSION already {{version}}, tagging HEAD"
    else
      git add VERSION
      git commit -m "Bump version to {{version}}"
    fi
    git tag -a "v{{version}}" -m "files v{{version}}"
    git push origin main
    git push origin "v{{version}}"
    echo "→ tagged v{{version}}. watch CI: https://github.com/HelgeSverre/files/actions"
