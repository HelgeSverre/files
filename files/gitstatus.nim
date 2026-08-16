import std/[os, osproc, tables, strutils]

proc findRepoRoot*(start: string): string =
  var d = absolutePath(start)
  while true:
    if dirExists(d / ".git") or fileExists(d / ".git"):
      return d
    let parent = d.parentDir
    if parent == d: return ""
    d = parent

proc fetchStatuses*(repoRoot: string): Table[string, string] =
  result = initTable[string, string]()
  if repoRoot == "": return
  let cmd = "git -C " & quoteShell(repoRoot) &
            " status --porcelain=v1 -z --untracked-files=all"
  let (outp, code) = execCmdEx(cmd)
  if code != 0: return
  let parts = outp.split('\0')
  var i = 0
  while i < parts.len:
    let rec = parts[i]
    if rec.len < 3: inc i; continue
    let x = rec[0]
    let xy = rec[0 .. 1]
    let rel = rec[3 .. ^1]
    if x in {'R', 'C'}:
      inc i
      if i < parts.len:
        result[parts[i]] = xy
    else:
      result[rel] = xy
    inc i

type GitInfo* = object
  repoRoot*: string
  statuses*: Table[string, string]
  branch*: string

proc fetchGit*(start: string): GitInfo =
  ## Discover the repo root and query status + branch in one shot. Cheap enough
  ## to run on a background thread while the tree walk happens.
  result.repoRoot = findRepoRoot(start)
  if result.repoRoot == "": return
  result.statuses = fetchStatuses(result.repoRoot)
  let (b, code) = execCmdEx("git -C " & quoteShell(result.repoRoot) &
                            " branch --show-current")
  if code == 0: result.branch = b.strip()
