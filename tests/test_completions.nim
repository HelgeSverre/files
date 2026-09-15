import std/[os, osproc, strutils, unittest]
import files/[completions, options]

suite "parseShellKind":
  test "valid shells (case-insensitive)":
    check parseShellKind("zsh") == skZsh
    check parseShellKind("Zsh") == skZsh
    check parseShellKind("ZSH") == skZsh

    check parseShellKind("bash") == skBash
    check parseShellKind("Bash") == skBash
    check parseShellKind("BASH") == skBash

    check parseShellKind("fish") == skFish
    check parseShellKind("Fish") == skFish
    check parseShellKind("FISH") == skFish

    check parseShellKind("nu") == skNu
    check parseShellKind("Nu") == skNu
    check parseShellKind("NU") == skNu
    check parseShellKind("nushell") == skNu
    check parseShellKind("Nushell") == skNu

  test "unsupported shells raise ValueError":
    try:
      discard parseShellKind("powershell")
      check false
    except ValueError as e:
      check e.msg == "unsupported shell 'powershell' (expected zsh, bash, fish, or nu)"

    try:
      discard parseShellKind("tcsh")
      check false
    except ValueError as e:
      check "unsupported shell 'tcsh'" in e.msg

    try:
      discard parseShellKind("")
      check false
    except ValueError as e:
      check "unsupported shell ''" in e.msg

suite "zsh completion generation":
  test "structure and compdef":
    let script = generateZsh()
    check script.startsWith("#compdef files\n")
    check "_files_cli() {" in script
    check "_arguments -s -S" in script
    check "compdef _files_cli files 2>/dev/null || true" in script
    check "if [ \"$funcstack[1]\" = \"_files_cli\" ]; then" in script

  test "flags, exclusion groups, and descriptions":
    let script = generateZsh()
    # Mutual exclusion pairs for flags with short and long names
    check "(-a --all)-a[show hidden files and gitignored entries (ghosted)]" in script
    check "(-a --all)--all[show hidden files and gitignored entries (ghosted)]" in script
    check "(-h --help)-h[show this help]" in script
    check "(-h --help)--help[show this help]" in script
    check "(-v --version)-v[print version]" in script
    check "(-v --version)--version[print version]" in script

    # Repeatable flags marked with * (no mutual exclusion so they can be repeated)
    check "*-I[extra ignore pattern (repeatable)]:glob:" in script
    check "*--ignore[extra ignore pattern (repeatable)]:glob:" in script

    # Single-form flags
    check "--no-sizes[hide file sizes]" in script
    check "--no-icons[disable nerd-font file icons]" in script
    check "--no-git[do not query git status]" in script
    check "--no-defaults[disable built-in junk ignores (node_modules, target, ...)]" in script

    # Aliases included
    check "--completion[generate shell completion script (zsh, bash, fish, nu)]:shell:(zsh bash fish nu)" in script

  test "choices and directory completion":
    let script = generateZsh()
    # Choices properly formatted: :argName:(c1 c2 ...)
    check ":name:(blue purple green red orange yellow rainbow)" in script
    check ":when:(auto always never)" in script
    check ":shell:(zsh bash fish nu)" in script

    # Directory completion
    check "'*:directory:_files -/'" in script

suite "bash completion generation":
  test "structure and registration":
    let script = generateBash()
    check "_files_cli() {" in script
    check "complete -F _files_cli files" in script
    check "local cur prev" in script
    check "COMPREPLY=()" in script

  test "options list contains all flags and aliases":
    let script = generateBash()
    check "local opts=\"" in script
    for spec in OptionSpecs:
      if spec.shortName.len > 0:
        check spec.shortName in script
      if spec.longName.len > 0:
        check spec.longName in script
      for a in spec.aliases:
        check a in script

  test "choice completion in separate and equals forms":
    let script = generateBash()
    # Case branches for choices
    check "blue purple green red orange yellow rainbow" in script
    check "auto always never" in script
    check "zsh bash fish nu" in script

    # Equals handling
    check "if [[ \"$cur\" == *=* ]]; then" in script
    check "prev=\"${cur%%=*}\"" in script
    check "cur=\"${cur#*=}\"" in script

    # Flag completion
    check "COMPREPLY=( $(compgen -W \"$opts\" -- \"$cur\") )" in script

  test "directory fallback completion":
    let script = generateBash()
    check "if type _filedir >/dev/null 2>&1; then" in script
    check "_filedir -d" in script
    check "COMPREPLY=( $(compgen -d -- \"$cur\") )" in script

suite "fish completion generation":
  test "structure and options":
    let script = generateFish()
    check "# fish completion for files" in script
    check "complete -c files -f\n" in script

    # All flags present with -s and/or -l
    check "complete -c files -s a -l all -d \"show hidden files and gitignored entries (ghosted)\"" in script
    check "complete -c files -s L -l depth -r -d \"limit recursion depth\"" in script
    check "complete -c files -s I -l ignore -r -d \"extra ignore pattern (repeatable)\"" in script
    check "complete -c files -s t -l sizes -d \"show file sizes (default)\"" in script
    check "complete -c files -l no-sizes -d \"hide file sizes\"" in script
    check "complete -c files -l no-icons -d \"disable nerd-font file icons\"" in script
    check "complete -c files -l no-git -d \"do not query git status\"" in script
    check "complete -c files -l no-defaults -d \"disable built-in junk ignores (node_modules, target, ...)\"" in script
    check "complete -c files -s h -l help -d \"show this help\"" in script
    check "complete -c files -s v -l version -d \"print version\"" in script

    # Aliases combined on the same line
    check "complete -c files -l completions -l completion -x -a \"zsh bash fish nu\"" in script

  test "choices and directory completion":
    let script = generateFish()
    check "complete -c files -l color -x -a \"auto always never\"" in script
    check "complete -c files -l theme -x -a \"blue purple green red orange yellow rainbow\"" in script
    check "complete -c files -l completions -l completion -x -a \"zsh bash fish nu\"" in script
    check "complete -c files -a \"(__fish_complete_directories)\" -d \"Directory\"" in script

suite "nushell completion generation":
  test "structure and custom completers":
    let script = generateNu()
    check "# nushell completion for files" in script
    check "def \"nu-complete files-color\" [] {" in script
    check "[ \"auto\" \"always\" \"never\" ]" in script

    check "def \"nu-complete files-theme\" [] {" in script
    check "[ \"blue\" \"purple\" \"green\" \"red\" \"orange\" \"yellow\" \"rainbow\" ]" in script

    check "def \"nu-complete files-completions\" [] {" in script
    check "[ \"zsh\" \"bash\" \"fish\" \"nu\" ]" in script

  test "extern signature with typed flags and directory argument":
    let script = generateNu()
    check "export extern \"files\" [" in script
    check "--all(-a)" in script
    check "--depth(-L): int" in script
    check "--ignore(-I): string" in script
    check "--sizes(-t)" in script
    check "--no-sizes" in script
    check "--no-icons" in script
    check "--color: string@\"nu-complete files-color\"" in script
    check "--no-color" in script
    check "--theme: string@\"nu-complete files-theme\"" in script
    check "--no-git" in script
    check "--no-defaults" in script
    check "--completions: string@\"nu-complete files-completions\"" in script
    check "--completion: string@\"nu-complete files-completions\"" in script
    check "--help(-h)" in script
    check "--version(-v)" in script
    check "path?: directory" in script

suite "generateCompletion dispatch":
  test "dispatches to specific shell generator":
    check generateCompletion(skZsh) == generateZsh()
    check generateCompletion(skBash) == generateBash()
    check generateCompletion(skFish) == generateFish()
    check generateCompletion(skNu) == generateNu()

suite "shell syntax verification":
  test "generated bash script is syntactically valid":
    let bashExe = findExe("bash")
    if bashExe.len > 0:
      let tmpFile = getTempDir() / "files_test_comp.bash"
      writeFile(tmpFile, generateBash())
      let (outp, exitCode) = execCmdEx(bashExe & " -n " & quoteShell(tmpFile))
      removeFile(tmpFile)
      check exitCode == 0
      check outp.len == 0

  test "generated zsh script is syntactically valid":
    let zshExe = findExe("zsh")
    if zshExe.len > 0:
      let tmpFile = getTempDir() / "files_test_comp.zsh"
      writeFile(tmpFile, generateZsh())
      let (outp, exitCode) = execCmdEx(zshExe & " -n " & quoteShell(tmpFile))
      removeFile(tmpFile)
      check exitCode == 0
      check outp.len == 0

  test "generated fish script is syntactically valid":
    let fishExe = findExe("fish")
    if fishExe.len > 0:
      let tmpFile = getTempDir() / "files_test_comp.fish"
      writeFile(tmpFile, generateFish())
      let (outp, exitCode) = execCmdEx(fishExe & " -n " & quoteShell(tmpFile))
      removeFile(tmpFile)
      check exitCode == 0
      check outp.len == 0

  test "generated nu script is syntactically valid":
    let nuExe = findExe("nu")
    if nuExe.len > 0:
      let tmpFile = getTempDir() / "files_test_comp.nu"
      writeFile(tmpFile, generateNu())
      let (outp, exitCode) = execCmdEx(nuExe & " -c " & quoteShell("source " & tmpFile))
      removeFile(tmpFile)
      check exitCode == 0
      check outp.strip().len == 0

suite "CLI integration":
  test "end-to-end completion generation and isolation":
    let filesBin = getCurrentDir() / "bin" / "files"
    if not fileExists(filesBin):
      let (bOut, bCode) = execCmdEx("nim c -d:release --opt:speed -o:" & quoteShell(filesBin) & " files.nim")
      check bCode == 0

    # Zsh completion via CLI
    let (zOut, zCode) = execCmdEx(quoteShell(filesBin) & " --completions zsh")
    check zCode == 0
    check zOut == generateZsh()
    check "dirs · " notin zOut  # no tree walker footer
    check "├──" notin zOut       # no tree output

    # Bash completion via CLI
    let (bOut, bCode) = execCmdEx(quoteShell(filesBin) & " --completions bash")
    check bCode == 0
    check bOut == generateBash()

    # Fish completion via CLI (using equals and alias)
    let (fOut, fCode) = execCmdEx(quoteShell(filesBin) & " --completion=fish")
    check fCode == 0
    check fOut == generateFish()

    # Nu completion via CLI (using alias)
    let (nOut, nCode) = execCmdEx(quoteShell(filesBin) & " --completion nu")
    check nCode == 0
    check nOut == generateNu()

    # Case-insensitive shell name
    let (ciOut, ciCode) = execCmdEx(quoteShell(filesBin) & " --completions=ZSH")
    check ciCode == 0
    check ciOut == generateZsh()

    # Unsupported shell exits with 1 and writes to stderr
    let (errOut, errCode) = execCmdEx(quoteShell(filesBin) & " --completions powershell")
    check errCode == 1
    check "files: unsupported shell 'powershell' (expected zsh, bash, fish, or nu)" in errOut

    # Missing shell argument exits with 1 and writes to stderr
    let (missOut, missCode) = execCmdEx(quoteShell(filesBin) & " --completions")
    check missCode == 1
    check "files: missing value for --completions" in missOut
