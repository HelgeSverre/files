import std/[os, osproc, strtabs, strutils, tempfiles, unittest]

const preferenceNames = ["FILES_DEPTH", "FILES_ICONS", "FILES_SIZES", "FILES_GIT",
  "FILES_ALL", "FILES_DEFAULTS", "FILES_COLOR", "FILES_COLOR_THEME", "FILES_COMPACT", "NO_COLOR"]

proc runFiles(root: string, values: openArray[(string, string)], args = ""): (string, int) =
  # Each child gets its own environment, independent of the developer's settings.
  when defined(windows):
    let env = newStringTable(modeCaseInsensitive)
  else:
    let env = newStringTable(modeCaseSensitive)
  for name, value in envPairs(): env[name] = value
  for name in preferenceNames: env[name] = ""
  for (name, value) in values: env[name] = value
  let binary = getCurrentDir() / "bin" / "files"
  execCmdEx(quoteShell(binary) & " " & quoteShell(root) & " " & args, env = env)

suite "environment CLI integration":
  setup:
    let binary = getCurrentDir() / "bin" / "files"
    if not fileExists(binary):
      let (buildOutput, buildCode) = execCmdEx(
        "nim c -d:release --opt:speed -o:" & quoteShell(binary) & " files.nim")
      doAssert buildCode == 0, buildOutput
    let root = createTempDir("files-env-", "")
    createDir(root / "src" / "main" / "kotlin")
    createDir(root / "build")
    createDir(root / "ignored")
    writeFile(root / "src" / "main" / "kotlin" / "Model.kt", "hello")
    writeFile(root / "README.md", "readme")
    writeFile(root / ".hidden", "hidden")
    writeFile(root / ".gitignore", "ignored/\n")
    writeFile(root / "build" / "output.txt", "build output")
    writeFile(root / "ignored" / "secret.txt", "ignored output")
  teardown:
    removeDir(root)

  test "environment controls depth, icons, sizes, and color in the actual CLI":
    let (output, code) = runFiles(root, [("FILES_DEPTH", "1"), ("FILES_ICONS", "0"),
      ("FILES_SIZES", "0"), ("FILES_GIT", "0"), ("FILES_COLOR", "never")])
    check code == 0
    check "├── src/" in output
    check "Model.kt" notin output
    check "\u{F07B}" notin output
    check " B" notin output
    check "\e[" notin output
    let (overrideOutput, overrideCode) = runFiles(root, [("FILES_DEPTH", "1"),
      ("FILES_ICONS", "0"), ("FILES_SIZES", "0"), ("FILES_GIT", "0"),
      ("FILES_COLOR", "never")], "-L 4 --icons --sizes --color=always")
    check overrideCode == 0
    check "Model.kt" in overrideOutput
    check "\u{F07B}" in overrideOutput
    check " B" in overrideOutput
    check "\e[" in overrideOutput

  test "visibility and default ignores can be configured and overridden":
    let (allOutput, allCode) = runFiles(root, [("FILES_ALL", "1"), ("FILES_GIT", "0")])
    check allCode == 0
    check ".hidden" in allOutput
    check "secret.txt" in allOutput
    let (visibleOutput, visibleCode) = runFiles(root, [("FILES_ALL", "1"),
      ("FILES_DEFAULTS", "0"), ("FILES_GIT", "0")], "--no-all")
    check visibleCode == 0
    check ".hidden" notin visibleOutput
    check "secret.txt" notin visibleOutput
    check "output.txt" in visibleOutput
    let (defaultOutput, defaultCode) = runFiles(root, [("FILES_DEFAULTS", "0"),
      ("FILES_GIT", "0")], "--defaults")
    check defaultCode == 0
    check "output.txt" notin defaultOutput

  test "NO_COLOR and CLI precedence operate across process environment":
    let values = [("FILES_COLOR", "always"), ("NO_COLOR", "1"),
      ("FILES_COLOR_THEME", "purple"), ("FILES_GIT", "0")]
    let (plain, plainCode) = runFiles(root, values)
    check plainCode == 0
    check "\e[" notin plain
    let (colored, coloredCode) = runFiles(root, values, "--color=always")
    check coloredCode == 0
    check "\e[" in colored
    let (expectedTheme, themeCode) = runFiles(root, [("FILES_GIT", "0")],
      "--theme=purple --color=always")
    check themeCode == 0
    check colored == expectedTheme

  test "invalid preferences fail with actionable errors; help and overrides work":
    let (output, code) = runFiles(root, [("FILES_DEPTH", "not-a-number")])
    check code == 1
    check "invalid FILES_DEPTH" in output
    let (help, helpCode) = runFiles(root, [("FILES_DEPTH", "bad"),
      ("FILES_COLOR_THEME", "bad"), ("FILES_GIT", "bad")], "--help")
    check helpCode == 0
    check "Usage:" in help
    let (overridden, overrideCode) = runFiles(root, [("FILES_DEPTH", "bad"),
      ("FILES_GIT", "bad")], "--root")
    check overrideCode == 0
    check "Model.kt" notin overridden

  test "git preference is read and the positive flag restores branch information":
    if findExe("git").len > 0:
      let (_, initCode) = execCmdEx("git init -q -b env-test " & quoteShell(root))
      check initCode == 0
      let (disabled, disabledCode) = runFiles(root, [("FILES_GIT", "0")])
      check disabledCode == 0
      check " · env-test" notin disabled
      let (enabled, enabledCode) = runFiles(root, [("FILES_GIT", "0")], "--git")
      check enabledCode == 0
      check " · env-test" in enabled
