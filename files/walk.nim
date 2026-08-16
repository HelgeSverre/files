import std/[algorithm, os, sets, strutils, tables]
import ./ignore
import ./util
when defined(macosx):
  import ./bulkread

type
  Kind* = enum kDir, kFile, kLink

  Node* = ref object
    name*: string
    kind*: Kind
    size*: int64
    exec*: bool
    linkTarget*: string
    ignored*: bool
    hidden*: bool
    status*: string
    depth*: int
    children*: seq[Node]

  WalkOptions* = object
    maxDepth*: int
    showAll*: bool
    gitignore*: IgnoreMatcher
    extra*: IgnoreMatcher
    repoRoot*: string
    statuses*: Table[string, string]

proc baseName(p: string): string =
  var p = p
  while p.len > 1 and p[^1] == '/':
    p = p[0 .. ^2]
  extractFilename(p)

proc relFromRepo(root, absPath: string): string =
  if root == "": return ""
  if not absPath.startsWith(root): return ""
  var rel = absPath.substr(root.len)
  if rel.startsWith("/"): rel = rel[1 .. ^1]
  rel

proc isExec(perms: set[FilePermission]): bool =
  fpUserExec in perms or fpGroupExec in perms or fpOthersExec in perms

proc collectNode*(dir: string, depth: int, tainted: bool,
                  giState, exState: ActiveState, opts: WalkOptions): Node

proc handleEntry(dir, name: string, isDir, isLink: bool, depth: int,
                 taint: bool, giState, exState: ActiveState, hasStatus: bool,
                 gi, ex: IgnoreMatcher, opts: WalkOptions,
                 entries: var seq[Node]) =
  if depth == 0 and name == ".git": return
  let isHidden = name.startsWith(".")
  let giLit = gi != nil and name in giState.lits
  let exLit = ex != nil and name in exState.lits
  let needFull = taint or giLit or exLit
  var isIgn: bool
  if needFull:
    isIgn = (gi != nil and gi.isIgnoredActive(giState.act, dir / name, isDir)) or
            (ex != nil and ex.isIgnoredActive(exState.act, dir / name, isDir))
  else:
    isIgn = (gi != nil and gi.entryIgnored(giState.always, name, isDir)) or
            (ex != nil and ex.entryIgnored(exState.always, name, isDir))
  if (isHidden or isIgn) and not opts.showAll:
    return
  let path = dir / name
  if isLink:
    var n = Node(name: name, kind: kLink, depth: depth + 1,
                 hidden: isHidden, ignored: isIgn)
    try:
      n.linkTarget = expandSymlink(path)
    except CatchableError:
      discard
    try:
      let fi = getFileInfo(path, followSymlink = true)
      n.size = fi.size
      n.exec = isExec(fi.permissions)
    except CatchableError:
      discard
    if hasStatus:
      let rel = relFromRepo(opts.repoRoot, path)
      if rel in opts.statuses: n.status = opts.statuses[rel]
    entries.add n
  elif isDir:
    var child = collectNode(path, depth + 1, taint or giLit or exLit,
                            giState, exState, opts)
    child.hidden = isHidden
    child.ignored = isIgn
    child.depth = depth + 1
    if hasStatus:
      let rel = relFromRepo(opts.repoRoot, path)
      if rel in opts.statuses: child.status = opts.statuses[rel]
    entries.add child
  else:
    var n = Node(name: name, kind: kFile, depth: depth + 1,
                 hidden: isHidden, ignored: isIgn)
    try:
      let li = getFileInfo(path, followSymlink = false)
      n.size = li.size
      n.exec = isExec(li.permissions)
    except CatchableError:
      discard
    if hasStatus:
      let rel = relFromRepo(opts.repoRoot, path)
      if rel in opts.statuses: n.status = opts.statuses[rel]
    entries.add n

proc walkDirEnum(dir: string, depth: int, taint: bool, giState, exState: ActiveState,
                 hasStatus: bool, gi, ex: IgnoreMatcher, opts: WalkOptions,
                 entries: var seq[Node]) =
  try:
    for kind, path in walkDir(dir):
      let name = baseName(path)
      let isDir = kind == pcDir
      let isLink = kind == pcLinkToDir or kind == pcLinkToFile
      handleEntry(dir, name, isDir, isLink, depth, taint, giState, exState,
                  hasStatus, gi, ex, opts, entries)
  except CatchableError:
    discard

proc collectNode*(dir: string, depth: int, tainted: bool,
                  giState, exState: ActiveState, opts: WalkOptions): Node =
  result = Node(name: baseName(dir), kind: kDir, depth: depth)
  let gi = opts.gitignore
  let ex = opts.extra
  if gi != nil:
    gi.loadGitignore(dir)
  if opts.maxDepth >= 0 and depth >= opts.maxDepth:
    return
  let myGi = if gi != nil:
               (if depth == 0: gi.initialState(dir) else: gi.activeForState(giState.act, dir))
             else: ActiveState()
  let myEx = if ex != nil:
               (if depth == 0: ex.initialState(dir) else: ex.activeForState(exState.act, dir))
             else: ActiveState()
  let hasStatus = opts.repoRoot != "" and opts.statuses.len > 0
  let taint = tainted or myGi.complex or myEx.complex
  var entries: seq[Node]
  when defined(macosx):
    var raw: seq[BulkEntry]
    if listDirBulk(dir, raw):
      for e in raw:
        let isDir = e.kind == okDir
        let isLink = e.kind == okLink
        handleEntry(dir, e.name, isDir, isLink, depth, taint, myGi, myEx,
                    hasStatus, gi, ex, opts, entries)
    else:
      walkDirEnum(dir, depth, taint, myGi, myEx, hasStatus, gi, ex, opts, entries)
  else:
    walkDirEnum(dir, depth, taint, myGi, myEx, hasStatus, gi, ex, opts, entries)
  proc byName(a, b: Node): int =
    let ad = a.kind == kDir
    let bd = b.kind == kDir
    if ad != bd: return (if ad: -1 else: 1)
    let ag = a.ignored or a.hidden
    let bg = b.ignored or b.hidden
    if ag != bg: return (if ag: 1 else: -1)
    naturalCompare(a.name, b.name)
  entries.sort(byName)
  result.children = entries

proc summarize*(n: Node, dirs, files: var int, bytes: var int64) =
  case n.kind
  of kDir: inc dirs
  else:
    inc files
    bytes += n.size
  for c in n.children:
    summarize(c, dirs, files, bytes)
