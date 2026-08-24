import std/[os, osproc, tables, tempfiles, unittest]
import files/gitstatus

suite "porcelain status parsing":
  test "staged rename is attached to destination":
    let statuses = parsePorcelainStatuses("R  new name.txt\0old name.txt\0")
    check statuses.getOrDefault("new name.txt") == "R "
    check "old name.txt" notin statuses

  test "unstaged rename is attached to destination":
    let statuses = parsePorcelainStatuses(" R new.txt\0old.txt\0")
    check statuses.getOrDefault("new.txt") == " R"
    check "old.txt" notin statuses

  test "records after rename are retained":
    let statuses = parsePorcelainStatuses("R  new.txt\0old.txt\0?? other.txt\0")
    check statuses.getOrDefault("new.txt") == "R "
    check statuses.getOrDefault("other.txt") == "??"

suite "scoped status query":
  test "only returns files beneath requested directory":
    let repo = createTempDir("files-status-", "")
    defer: removeDir(repo)
    createDir(repo / "inside")
    createDir(repo / "outside")
    writeFile(repo / "inside" / "shown.txt", "shown")
    writeFile(repo / "outside" / "hidden.txt", "hidden")
    let (_, initCode) = execCmdEx("git init -q " & quoteShell(repo))
    check initCode == 0

    let statuses = fetchStatuses(repo, repo / "inside")
    check statuses.getOrDefault("inside/shown.txt") == "??"
    check "outside/hidden.txt" notin statuses
