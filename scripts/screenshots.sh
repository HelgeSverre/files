#!/usr/bin/env bash
# Capture actual CLI output. Requires VHS and JetBrainsMono Nerd Font.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
demo_dir="$(mktemp -d)"
trap 'rm -rf "$demo_dir"' EXIT
mkdir -p "$demo_dir/demo/core/src/main/kotlin/no/helge/fieldscan/core" \
  "$demo_dir/demo/core/src/test/kotlin/no/helge/fieldscan/core" \
  "$demo_dir/demo/docs" "$demo_dir/demo/build"
cd "$demo_dir/demo"
printf '# Demo\n' > README.md
printf 'build/\n' > .gitignore
printf 'TOKEN=example\n' > .env.example
printf 'Example usage\n' > docs/usage.md
printf 'plugins {}\n' > core/build.gradle.kts
printf 'class AdParser\n' > core/src/main/kotlin/no/helge/fieldscan/core/AdParser.kt
printf 'data class Model(val name: String)\n' > core/src/main/kotlin/no/helge/fieldscan/core/Model.kt
printf 'class CoreTest\n' > core/src/test/kotlin/no/helge/fieldscan/core/CoreTest.kt
printf 'generated output\n' > build/output.txt
git init -q -b main
git add .
git -c user.name=Demo -c user.email=demo@example.com commit -qm 'Demo fixture'
printf 'More usage notes\n' >> docs/usage.md
printf 'Dependency notes\n' > docs/dependencies.md
git add docs/dependencies.md
printf 'Release notes\n' > NOTES.md
export PATH="$repo_dir/bin:$PATH"
export FILES_COMPACT=0 FILES_COLOR_THEME=rainbow
unset NO_COLOR
capture() {
  local name="$1" height="$2" command_text="$3"
  cat > "$demo_dir/$name.tape" <<TAPE
Set Shell "bash"
Set FontFamily "JetBrainsMono Nerd Font"
Set FontSize 22
Set Width 1200
Set Height $height
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 0ms
Hide
Type "export PS1='$ '; cd '$demo_dir/demo'; clear"
Enter
Sleep 500ms
Show
Type "$command_text"
Enter
Sleep 1s
Screenshot "$repo_dir/assets/screenshots/$name.png"
Sleep 1s
TAPE
  vhs "$demo_dir/$name.tape"
}
capture overview 480 'files -L 3'
capture depth 330 'files --root'
capture all 540 'files -a -L 2'
capture expanded 720 'files core'
capture compact 390 'files --compact core'
capture theme 390 'files --compact --theme purple core'
capture plain 450 'files -L 2 --no-icons --no-sizes --no-color --no-git'
