import std/[os, sets, strutils, tables]

type
  TokKind = enum tkLit, tkStar, tkQuest, tkClass, tkDStar

  GlobTok = object
    kind: TokKind
    lit: char
    cls: string
    neg: bool

  Pattern* = object
    negate*: bool
    dirOnly*: bool
    anchored*: bool
    segs*: seq[seq[GlobTok]]

  Rule = object
    base: string
    baseComponentCount: int
    pat: Pattern

  IgnoreMatcher* = ref object
    rules*: seq[Rule]
    loaded*: HashSet[string]
    ruleLiteral: seq[string]
    literalSegs: HashSet[string]
    alwaysRules: seq[int]
    complexRules: seq[int]
    byBase: Table[string, seq[int]]

proc newIgnoreMatcher*(): IgnoreMatcher =
  new(result)
  result.loaded = initHashSet[string]()
  result.literalSegs = initHashSet[string]()
  result.byBase = initTable[string, seq[int]]()

# --- matching primitives (operate on a path via (start, len) component spans) ---

proc isSep(ch: char): bool = ch == '/' or ch == '\\'

const MaxPathComponents = 256
type SpanBuf = array[MaxPathComponents, (int, int)]

proc componentSpans(s: string, spans: var SpanBuf): int =
  var start = 0
  var n = 0
  let L = s.len
  var i = 0
  while i <= L:
    if i == L or isSep(s[i]):
      let len = i - start
      if len > 0 and n < MaxPathComponents:
        spans[n] = (start, len)
        inc n
      start = i + 1
    inc i
  result = n

proc classMatches(cls: string, neg: bool, ch: char): bool =
  var inSet = false
  var i = 0
  while i < cls.len:
    if i + 2 < cls.len and cls[i + 1] == '-' and cls[i + 2] != ']':
      let lo = cls[i]
      let hi = cls[i + 2]
      if ch >= lo and ch <= hi: inSet = true
      inc i, 3
    else:
      if ch == cls[i]: inSet = true
      inc i
  if neg: return not inSet
  inSet

proc segMatch(toks: seq[GlobTok], s: string, cs: int, cl: int): bool =
  proc inner(ti, si: int): bool =
    if ti == toks.len: return si == cl
    let t = toks[ti]
    case t.kind
    of tkStar:
      for k in si .. cl:
        if inner(ti + 1, k): return true
      return false
    of tkQuest:
      if si < cl: return inner(ti + 1, si + 1)
      return false
    of tkClass:
      if si < cl and classMatches(t.cls, t.neg, s[cs + si]):
        return inner(ti + 1, si + 1)
      return false
    of tkLit:
      if si < cl and s[cs + si] == t.lit: return inner(ti + 1, si + 1)
      return false
    of tkDStar:
      # Unreachable: `**` is handled at the segment level, never inside one.
      return false
  inner(0, 0)

proc segListMatch(pat: seq[seq[GlobTok]], s: string, spans: SpanBuf,
                  ps: int, pc: int): bool =
  proc inner(pi, si: int): bool =
    if pi == pat.len: return si == pc
    let seg = pat[pi]
    if seg.len == 1 and seg[0].kind == tkDStar:
      let isLast = pi == pat.len - 1
      let minConsume = if isLast and pat.len > 1: 1 else: 0
      for k in (si + minConsume) .. pc:
        if inner(pi + 1, k): return true
      return false
    else:
      if si < pc:
        let (cs, cl) = spans[ps + si]
        if segMatch(seg, s, cs, cl):
          return inner(pi + 1, si + 1)
      return false
  inner(0, 0)

proc ruleMatchesPath(pat: Pattern, s: string, spans: SpanBuf,
                     ps: int, pc: int, isDir: bool): bool =
  if pc == 0: return false
  var minLen = 0
  for seg in pat.segs:
    if not (seg.len == 1 and seg[0].kind == tkDStar):
      inc minLen
  if pat.anchored:
    for i in max(minLen, 1) .. pc:
      let targetIsDir = i < pc or isDir
      if pat.dirOnly and not targetIsDir: continue
      if segListMatch(pat.segs, s, spans, ps, i): return true
    return false
  else:
    for i in max(minLen, 1) .. pc:
      let targetIsDir = i < pc or isDir
      if pat.dirOnly and not targetIsDir: continue
      for st in 0 .. (i - minLen):
        if segListMatch(pat.segs, s, spans, ps + st, i - st): return true
    return false

proc containsComponent(s, sub: string): bool =
  var start = 0
  while true:
    let idx = s.find(sub, start)
    if idx < 0: return false
    let before = idx == 0 or isSep(s[idx - 1])
    let after = idx + sub.len == s.len or isSep(s[idx + sub.len])
    if before and after: return true
    start = idx + sub.len

# --- parsing ---

proc parseSeg(seg: string): seq[GlobTok] =
  var i = 0
  while i < seg.len:
    let ch = seg[i]
    if ch == '\\':
      if i + 1 < seg.len:
        result.add GlobTok(kind: tkLit, lit: seg[i + 1])
        inc i
      else:
        result.add GlobTok(kind: tkLit, lit: '\\')
    elif ch == '*':
      result.add GlobTok(kind: tkStar)
    elif ch == '?':
      result.add GlobTok(kind: tkQuest)
    elif ch == '[':
      var j = i + 1
      var neg = false
      if j < seg.len and (seg[j] == '!' or seg[j] == '^'):
        neg = true
        inc j
      var cls = ""
      var closed = false
      while j < seg.len:
        if seg[j] == ']':
          closed = true
          break
        cls.add seg[j]
        inc j
      if closed:
        result.add GlobTok(kind: tkClass, cls: cls, neg: neg)
        i = j
      else:
        result.add GlobTok(kind: tkLit, lit: '[')
    else:
      result.add GlobTok(kind: tkLit, lit: ch)
    inc i

proc parsePattern(line: string): Pattern =
  var s = line.strip()
  if s.len == 0: return
  if s[0] == '!':
    result.negate = true
    s = s[1 .. ^1].strip()
  if s.len == 0: return
  if s[^1] == '/':
    result.dirOnly = true
    s = s[0 .. ^2]
  if s.len == 0: return
  if s[0] == '/':
    result.anchored = true
    s = s[1 .. ^1]
  if s.len == 0: return
  s = s.strip()
  if s.len == 0: return
  let rawSegs = s.split('/')
  if not result.anchored and s.contains('/') and not s.startsWith("**/"):
    result.anchored = true
  for seg in rawSegs:
    if seg == "**":
      result.segs.add @[GlobTok(kind: tkDStar)]
    elif seg.len > 0:
      result.segs.add parseSeg(seg)
    else:
      result.segs.add @[]

proc firstLiteralSeg(pat: Pattern): string =
  for seg in pat.segs:
    var allLit = true
    var s = ""
    for t in seg:
      if t.kind != tkLit:
        allLit = false
        break
      s.add t.lit
    if allLit and s.len > 0:
      return s
  ""

# --- rule ingestion ---

proc pushRule(m: IgnoreMatcher, base: string, p: Pattern) =
  var spans: SpanBuf
  let baseComps = componentSpans(base, spans)
  m.rules.add Rule(base: base, baseComponentCount: baseComps, pat: p)
  let lit = firstLiteralSeg(p)
  m.ruleLiteral.add lit
  if lit.len > 0:
    m.literalSegs.incl lit
  else:
    let idx = m.rules.len - 1
    if p.anchored or p.segs.len != 1:
      m.complexRules.add idx
    else:
      m.alwaysRules.add idx
  m.byBase.mgetOrPut(base, @[]).add m.rules.len - 1

proc addRule*(m: IgnoreMatcher, base: string, line: string) =
  let t = line.strip()
  if t.len == 0 or t[0] == '#': return
  var p = parsePattern(t)
  if p.segs.len == 0: return
  m.pushRule(base, p)

proc addRuleExtra*(m: IgnoreMatcher, base: string, line: string) =
  let t = line.strip()
  if t.len == 0 or t[0] == '#': return
  var p = parsePattern(t)
  p.negate = false
  if p.segs.len == 0: return
  m.pushRule(base, p)

proc loadGitignore*(m: IgnoreMatcher, dir: string) =
  let p = dir / ".gitignore"
  if p in m.loaded: return
  m.loaded.incl p
  if fileExists(p):
    try:
      for line in readFile(p).splitLines():
        m.addRule(dir, line)
    except CatchableError:
      discard

proc preload*(m: IgnoreMatcher, fromDir, upTo: string) =
  var d = fromDir
  while true:
    m.loadGitignore(d)
    if d == upTo: break
    let parent = d.parentDir
    if parent == d: break
    d = parent

# --- matching ---

proc isIgnoredActive*(m: IgnoreMatcher, act: seq[int], absPath: string,
                      isDir: bool): bool

proc isIgnored*(m: IgnoreMatcher, absPath: string, isDir: bool): bool =
  ## Full matcher over all rules — the reference implementation. Production
  ## callers use `isIgnoredActive` with a base-scoped rule set.
  var allIdx: seq[int]
  for i in 0 ..< m.rules.len: allIdx.add i
  m.isIgnoredActive(allIdx, absPath, isDir)

proc baseCovers(base, dir: string): bool =
  if base.len == 0: return true
  if dir == base: return true
  dir.len > base.len and dir.startsWith(base) and isSep(dir[base.len])

proc initialActive*(m: IgnoreMatcher, absRoot: string): seq[int] =
  ## Rule indices that apply at the walk root (rules whose base is an ancestor
  ## of, or equal to, `absRoot`, e.g. preloaded parent .gitignore files).
  for idx in 0 ..< m.rules.len:
    if baseCovers(m.rules[idx].base, absRoot):
      result.add idx

proc activeFor*(m: IgnoreMatcher, parentAct: seq[int], dir: string): seq[int] =
  ## Active rule indices for a directory: inherited from the parent plus the
  ## rules whose base is exactly this directory (loaded when we entered it).
  result = parentAct
  for idx in m.byBase.getOrDefault(dir, @[]):
    result.add idx

proc ruleIsComplex*(m: IgnoreMatcher, idx: int): bool =
  let r = m.rules[idx]
  r.pat.anchored or r.pat.segs.len != 1

proc ruleLiteral*(m: IgnoreMatcher, idx: int): string = m.ruleLiteral[idx]

proc isIgnoredActive*(m: IgnoreMatcher, act: seq[int], absPath: string,
                      isDir: bool): bool =
  ## Full matcher restricted to a set of rule indices (already base-scoped).
  var spans: SpanBuf
  let total = componentSpans(absPath, spans)
  if total == 0: return false
  var last = false
  for i in act:
    let r = m.rules[i]
    let base = r.base
    if base.len > 0:
      if absPath.len < base.len: continue
      if not absPath.startsWith(base): continue
      if absPath.len > base.len and not isSep(absPath[base.len]): continue
    let lit = m.ruleLiteral[i]
    if lit.len > 0 and not containsComponent(absPath, lit): continue
    if r.baseComponentCount >= total: continue
    if ruleMatchesPath(r.pat, absPath, spans, r.baseComponentCount, total - r.baseComponentCount, isDir):
      last = not r.pat.negate
  last

type ActiveState* = object
  active*: seq[int]
  literals*: HashSet[string]
  alwaysRules*: seq[int]
  complex*: bool

proc stateFrom(active: seq[int], m: IgnoreMatcher): ActiveState =
  result.active = active
  result.literals = initHashSet[string]()
  for idx in active:
    let lit = m.ruleLiteral[idx]
    if lit.len > 0:
      result.literals.incl lit
    elif not m.ruleIsComplex(idx):
      result.alwaysRules.add idx
    else:
      result.complex = true

proc initialState*(m: IgnoreMatcher, absRoot: string): ActiveState =
  stateFrom(m.initialActive(absRoot), m)

proc activeForState*(m: IgnoreMatcher, parentAct: seq[int], dir: string): ActiveState =
  stateFrom(m.activeFor(parentAct, dir), m)

proc entryIgnored*(m: IgnoreMatcher, active: seq[int], name: string, isDir: bool): bool =
  ## Fast basename check against the active simple-always rules. Callers only
  ## invoke this when `name` is not in the active literals and the subtree does
  ## not require full-precision matching.
  var last = false
  for idx in active:
    let r = m.rules[idx]
    if r.pat.dirOnly and not isDir: continue
    let seg = r.pat.segs[0]
    if seg.len == 1 and seg[0].kind == tkDStar:
      last = not r.pat.negate
    elif segMatch(seg, name, 0, name.len):
      last = not r.pat.negate
  last
