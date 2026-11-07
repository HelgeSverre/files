import std/[os, osproc, strutils, tempfiles, unittest]

suite "compact CLI integration":
  test "filtering, depth, environment, and statistics use real filesystem paths":
    let root = createTempDir("files-compact-", "")
    defer: removeDir(root)
    createDir(root / "src" / "main" / "kotlin")
    writeFile(root / "src" / "main" / "kotlin" / "Model.kt", "hello")
    writeFile(root / "src" / "main" / "notes.txt", "side file")
    let binary = getCurrentDir() / "bin" / "files"
    if not fileExists(binary):
      let (buildOutput, buildCode) = execCmdEx(
        "nim c -d:release --opt:speed -o:" & quoteShell(binary) & " files.nim")
      doAssert buildCode == 0, buildOutput
    let cmd = quoteShell(binary) & " --no-git --no-icons --no-color --no-sizes " & quoteShell(root)
    let previous = getEnv("FILES_COMPACT")
    let existed = existsEnv("FILES_COMPACT")
    defer:
      if existed: putEnv("FILES_COMPACT", previous)
      else: delEnv("FILES_COMPACT")
    putEnv("FILES_COMPACT", "1")
    let (normal, code) = execCmdEx(cmd)
    check code == 0
    check "└── src/main/\n" in normal
    check "4 dirs · 2 files" in normal
    let (filtered, filteredCode) = execCmdEx(cmd & " --ignore=notes.txt")
    check filteredCode == 0
    check "└── src/main/kotlin/\n    └── Model.kt" in filtered
    check "4 dirs · 1 files" in filtered
    let (limited, limitedCode) = execCmdEx(cmd & " --depth=2")
    check limitedCode == 0
    check "└── src/main/\n" in limited
    check "kotlin" notin limited
    check "3 dirs · 0 files" in limited
    let (expanded, expandedCode) = execCmdEx(cmd & " --no-compact")
    check expandedCode == 0
    check "└── src/\n    └── main/" in expanded
    putEnv("FILES_COMPACT", "0")
    let (explicit, explicitCode) = execCmdEx(cmd & " --compact")
    check explicitCode == 0
    check explicit == normal
