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

  WalkContext* = object
    ## Invariants shared by every node in a walk.
    opts: WalkOptions
    gi: IgnoreMatcher
    ex: IgnoreMatcher

  DirWalk = object
    ## Per-directory state threaded through entry handling.
    ctx: WalkContext
    dir: string
    depth: int
    fullCheck: bool
    giState: ActiveState
    exState: ActiveState
    entries: seq[Node]

proc baseName(p: string): string =
  var p = p
  while p.len > 1 and (p[^1] == '/' or p[^1] == '\\'):
    p = p[0 .. ^2]
  extractFilename(p)

proc relFromRepo(root, absPath: string): string =
  if root == "": return ""
  if not absPath.startsWith(root): return ""
  var rel = absPath.substr(root.len)
  if rel.len > 0 and (rel[0] == '/' or rel[0] == '\\'): rel = rel[1 .. ^1]
  rel

proc isExec(perms: set[FilePermission]): bool =
  fpUserExec in perms or fpGroupExec in perms or fpOthersExec in perms

proc newWalkContext*(opts: WalkOptions, gi, ex: IgnoreMatcher): WalkContext =
  WalkContext(opts: opts, gi: gi, ex: ex)

proc collectNode*(ctx: WalkContext, parentGi, parentEx: ActiveState,
                  dir: string, depth: int, fullCheck: bool): Node

proc handleEntry(w: var DirWalk, name: string, isDir, isLink: bool) =
  ## Inspect one directory entry: decide if it is hidden/ignored, build its
  ## node, and recurse into subdirectories.
  let ctx = w.ctx
  let gi = ctx.gi
  let ex = ctx.ex
  if w.depth == 0 and name == ".git": return
  let isHidden = name.startsWith(".")
  let giHit = gi != nil and name in w.giState.literals
  let exHit = ex != nil and name in w.exState.literals
  let needFull = w.fullCheck or giHit or exHit
  var isIgn: bool
  if needFull:
    isIgn = (gi != nil and gi.isIgnoredActive(w.giState.active, w.dir / name, isDir)) or
            (ex != nil and ex.isIgnoredActive(w.exState.active, w.dir / name, isDir))
  else:
    isIgn = (gi != nil and gi.entryIgnored(w.giState.alwaysRules, name, isDir)) or
            (ex != nil and ex.entryIgnored(w.exState.alwaysRules, name, isDir))
  if (isHidden or isIgn) and not ctx.opts.showAll:
    return
  let path = w.dir / name
  if isLink:
    var n = Node(name: name, kind: kLink, depth: w.depth + 1,
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
    w.entries.add n
  elif isDir:
    var child = collectNode(ctx, w.giState, w.exState, path, w.depth + 1,
                            w.fullCheck or giHit or exHit)
    child.hidden = isHidden
    child.ignored = isIgn
    child.depth = w.depth + 1
    w.entries.add child
  else:
    var n = Node(name: name, kind: kFile, depth: w.depth + 1,
                 hidden: isHidden, ignored: isIgn)
    try:
      let li = getFileInfo(path, followSymlink = false)
      n.size = li.size
      n.exec = isExec(li.permissions)
    except CatchableError:
      discard
    w.entries.add n

proc walkDirEnum(w: var DirWalk) =
  ## Portable fallback enumeration for platforms without getattrlistbulk.
  try:
    for kind, path in walkDir(w.dir):
      let name = baseName(path)
      let isDir = kind == pcDir
      let isLink = kind == pcLinkToDir or kind == pcLinkToFile
      try:
        handleEntry(w, name, isDir, isLink)
      except CatchableError:
        # Skip a single problematic entry rather than dropping the rest of the
        # directory (walkDir can raise mid-iteration on Windows).
        discard
  except CatchableError:
    discard

proc finishDir(w: var DirWalk, result: Node) =
  ## Sort a directory's children (dirs first, natural name order) and attach
  ## them to the result node.
  proc byName(a, b: Node): int =
    let ad = a.kind == kDir
    let bd = b.kind == kDir
    if ad != bd: return (if ad: -1 else: 1)
    let ag = a.ignored or a.hidden
    let bg = b.ignored or b.hidden
    if ag != bg: return (if ag: 1 else: -1)
    naturalCompare(a.name, b.name)
  w.entries.sort(byName)
  result.children = w.entries

proc collectNode*(ctx: WalkContext, parentGi, parentEx: ActiveState,
                  dir: string, depth: int, fullCheck: bool): Node =
  ## Recursively collect `dir` into a Node tree, honoring .gitignore rules.
  ## `parentGi`/`parentEx` are the active rules for the parent directory; the
  ## child's rules extend them. `fullCheck` marks subtrees that need
  ## full-precision matching (an ancestor was a rule literal, or a complex
  ## rule applies).
  result = Node(name: baseName(dir), kind: kDir, depth: depth)
  let gi = ctx.gi
  let ex = ctx.ex
  if gi != nil:
    gi.loadGitignore(dir)
  if ctx.opts.maxDepth >= 0 and depth >= ctx.opts.maxDepth:
    return
  var w = DirWalk(ctx: ctx, dir: dir, depth: depth)
  w.giState = if gi != nil:
                (if depth == 0: gi.initialState(dir)
                 else: gi.activeForState(parentGi.active, dir))
              else: ActiveState()
  w.exState = if ex != nil:
                (if depth == 0: ex.initialState(dir)
                 else: ex.activeForState(parentEx.active, dir))
              else: ActiveState()
  w.fullCheck = fullCheck or w.giState.complex or w.exState.complex
  when defined(macosx):
    var raw: seq[BulkEntry]
    if listDirBulk(dir, raw):
      for e in raw:
        handleEntry(w, e.name, e.kind == okDir, e.kind == okLink)
      finishDir(w, result)
      return
  walkDirEnum(w)
  finishDir(w, result)

proc assignStatuses*(root: Node, repoRoot, absRoot: string,
                     statuses: Table[string, string]): int =
  ## Stamp git status badges onto the tree after the walk, once git has
  ## finished on its background thread. Tree nodes don't carry their paths, so
  ## reconstruct them as we descend. Returns how many nodes were stamped, which
  ## scopes the footer's change count to the walked subtree.
  if statuses.len == 0: return 0
  var stamped = 0
  proc go(n: Node, path: string) =
    if n.kind != kDir:
      let rel = relFromRepo(repoRoot, path)
      if rel in statuses:
        n.status = statuses[rel]
        inc stamped
    for c in n.children:
      go(c, path / c.name)
  go(root, absRoot)
  stamped

proc summarize*(n: Node, dirs, files: var int, bytes: var int64) =
  case n.kind
  of kDir: inc dirs
  else:
    inc files
    bytes += n.size
  for c in n.children:
    summarize(c, dirs, files, bytes)
