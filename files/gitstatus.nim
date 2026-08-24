import std/[os, osproc, tables, strutils]

proc findRepoRoot*(start: string): string =
  var d = absolutePath(start)
  while true:
    if dirExists(d / ".git") or fileExists(d / ".git"):
      return d
    let parent = d.parentDir
    if parent == d: return ""
    d = parent

proc parsePorcelainStatuses*(outp: string): Table[string, string] =
  result = initTable[string, string]()
  let parts = outp.split('\0')
  var i = 0
  while i < parts.len:
    let rec = parts[i]
    if rec.len < 3: inc i; continue
    let x = rec[0]
    let y = rec[1]
    let xy = rec[0 .. 1]
    let rel = rec[3 .. ^1]
    result[rel] = xy
    if x in {'R', 'C'} or y in {'R', 'C'}:
      # In porcelain v1 -z output, the destination is in `rec`; the following
      # NUL-delimited field is the source path and carries no separate status.
      inc i
    inc i

proc fetchStatuses*(repoRoot: string, scope = ""): Table[string, string] =
  result = initTable[string, string]()
  if repoRoot == "": return
  var cmd = "git -C " & quoteShell(repoRoot) &
            " status --porcelain=v1 -z --untracked-files=all"
  if scope.len > 0:
    let relScope = relativePath(scope, repoRoot).replace('\\', '/')
    if relScope != "." and not relScope.startsWith(".."):
      cmd.add " -- " & quoteShell(relScope)
  let (outp, code) = execCmdEx(cmd)
  if code == 0:
    result = parsePorcelainStatuses(outp)

type GitInfo* = object
  repoRoot*: string
  statuses*: Table[string, string]
  branch*: string

proc fetchGit*(start: string): GitInfo =
  ## Discover the repo root and query status + branch in one shot. Cheap enough
  ## to run on a background thread while the tree walk happens.
  result.repoRoot = findRepoRoot(start)
  if result.repoRoot == "": return
  result.statuses = fetchStatuses(result.repoRoot, start)
  let (b, code) = execCmdEx("git -C " & quoteShell(result.repoRoot) &
                            " branch --show-current")
  if code == 0: result.branch = b.strip()
