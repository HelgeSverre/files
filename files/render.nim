import std/[os, strutils, unicode]
import ./util
import ./walk

type
  Chunk = object
    txt: string
    fg: string
    dim: bool
    bold: bool
    w: int

  Line* = object
    chunks: seq[Chunk]
    contentLen: int
    size: int64
    hasSize: bool

  RenderOptions* = object
    color*: bool
    icons*: bool
    sizes*: bool
    termWidth*: int

const
  DimGray* = "\e[38;2;110;115;125m"
  Green* = "\e[38;2;85;200;120m"
  Cyan* = "\e[38;2;96;188;202m"
  Red* = "\e[38;2;255;100;95m"
  Amber* = "\e[38;2;255;180;80m"
  Magenta* = "\e[38;2;230;130;210m"

proc connectorColor(depth: int): string =
  let d = min(depth, 12)
  let (r, g, b) = hslToRgb(float((215 + d * 32) mod 360), 0.55, 0.62)
  rgb(r, g, b)

proc dirColor(depth: int): string =
  let d = min(depth, 12)
  let (r, g, b) = hslToRgb(float((215 + d * 32) mod 360), 0.5, 0.72)
  rgb(r, g, b)

proc addChunk(l: var Line, txt: string, fg = "", dim = false, bold = false) =
  if txt.len == 0: return
  l.chunks.add Chunk(txt: txt, fg: fg, dim: dim, bold: bold, w: displayWidth(txt))
  l.contentLen += l.chunks[^1].w

proc truncateRun(s: string, maxW: int): (string, int) =
  if maxW <= 0: return ("", 0)
  var w = 0
  var i = 0
  while i < s.len:
    let l = runeLenAt(s, i)
    if l <= 0: inc i; continue
    let cw = runeWidth(runeAt(s, i))
    if w + cw > maxW:
      if w > 0:
        let cut = s[0 ..< i]
        if w + 1 <= maxW: return (cut & "…", w + 1)
        return (cut, w)
      return ("…", 1)
    inc w, cw
    inc i, l
  (s, w)

proc iconFor(n: Node): string =
  case n.kind
  of kDir: return "\u{F07B}"
  of kLink: return "\u{F0C1}"
  of kFile: discard
  let name = n.name
  let upper = name.toUpperAscii
  if upper.startsWith("README"): return "\u{F02D}"
  if upper == "MAKEFILE": return "\u{F013}"
  if upper == "DOCKERFILE": return "\u{F0B0}"
  if name.startsWith(".") and name.len > 1: return "\u{F023}"
  let ext = name.splitFile.ext.toLowerAscii
  case ext
  of ".fs", ".fsx", ".fsi", ".nim", ".rs", ".go", ".c", ".h", ".cpp", ".hpp",
     ".cc", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".py", ".pyw", ".rb",
     ".php", ".java", ".kt", ".scala", ".clj", ".lua", ".hs", ".erl", ".ex",
     ".exs", ".pl", ".sh", ".bash", ".zsh", ".fish", ".ps1", ".sql", ".zig",
     ".odin", ".v", ".vue", ".svelte", ".elm", ".dart", ".swift", ".ml",
     ".asm", ".s", ".nix": return "\u{F1C8}"
  of ".md", ".markdown", ".rst", ".txt", ".log", ".adoc": return "\u{F15C}"
  of ".json", ".yaml", ".yml", ".toml", ".ini", ".conf", ".cfg",
     ".env", ".properties": return "\u{F1C8}"
  of ".html", ".htm", ".css", ".scss", ".sass", ".less", ".xml": return "\u{F13B}"
  of ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".ico", ".bmp",
     ".tiff": return "\u{F1C4}"
  of ".mp3", ".wav", ".flac", ".ogg", ".aac", ".m4a": return "\u{F1C7}"
  of ".mp4", ".mkv", ".mov", ".avi", ".webm", ".flv": return "\u{F1C6}"
  of ".zip", ".tar", ".gz", ".tgz", ".bz2", ".xz", ".7z", ".rar", ".zst":
    return "\u{F1C5}"
  of ".pdf": return "\u{F1C9}"
  of ".doc", ".docx", ".odt", ".rtf": return "\u{F1C1}"
  of ".xls", ".xlsx", ".csv", ".ods": return "\u{F1C2}"
  of ".ppt", ".pptx", ".odp": return "\u{F1C3}"
  of ".db", ".sqlite", ".sqlite3", ".mdb": return "\u{F1C0}"
  of ".lock": return "\u{F023}"
  of ".app", ".dmg", ".exe", ".deb", ".rpm": return "\u{F085}"
  else: return "\u{F016}"

proc badge(xy: string): (string, string) =
  if xy.len < 2: return ("", "")
  let x = xy[0]
  let y = xy[1]
  if x == '?' and y == '?': return ("??", Amber)
  if x == 'U' or y == 'U' or (x == 'D' and y == 'D') or (x == 'A' and y == 'A'):
    return ("!", Magenta)
  if x in {'M', 'A', 'R', 'C'} and y == ' ':
    return ($x, Green)
  if x == ' ' and y in {'M', 'A', 'D', 'R', 'C'}:
    return ($y, Red)
  if x in {'M', 'A', 'R', 'C', 'D'} and y in {'M', 'A', 'R', 'C', 'D'}:
    return ($x & $y, Red)
  ("", "")

proc emitNode(n: Node, prefix: seq[Chunk], isLast: bool, opts: RenderOptions,
              lines: var seq[Line], budget: int) =
  var line = Line()
  for ch in prefix:
    line.chunks.add ch
    line.contentLen += ch.w
  let depth = n.depth
  addChunk(line, if isLast: "└── " else: "├── ", connectorColor(depth))
  let isGhost = n.ignored or n.hidden
  let nameCol = if n.kind == kDir: dirColor(depth) else: ""
  if opts.icons:
    addChunk(line, iconFor(n), nameCol, dim = isGhost, bold = n.kind == kDir)
    addChunk(line, " ", nameCol)
  var name = n.name
  if n.kind == kDir: name.add "/"
  let remaining = budget - line.contentLen
  let (tn, _) = truncateRun(name, remaining)
  addChunk(line, tn, nameCol, dim = isGhost, bold = n.kind == kDir)
  if n.kind == kLink and n.linkTarget.len > 0:
    addChunk(line, " → " & n.linkTarget, Cyan, dim = isGhost)
  if n.kind == kFile and n.exec:
    addChunk(line, "*", Green, bold = true)
  if n.status.len > 0:
    let (b, col) = badge(n.status)
    if b.len > 0:
      addChunk(line, " [" & b & "]", col, bold = true)
  if opts.sizes and n.kind == kFile:
    line.size = n.size
    line.hasSize = true
  lines.add line
  if n.kind == kDir and n.children.len > 0:
    var cp: seq[Chunk]
    if depth == 0:
      cp = @[]
    else:
      cp = prefix
      if isLast:
        cp.add Chunk(txt: "    ", w: 4)
      else:
        cp.add Chunk(txt: "│   ", fg: connectorColor(depth), w: 4)
    for i, c in n.children:
      emitNode(c, cp, i == n.children.len - 1, opts, lines, budget)

proc renderTree*(root: Node, opts: RenderOptions, lines: var seq[Line]) =
  let reserved = if opts.sizes: 14 else: 0
  let budget = max(opts.termWidth - reserved, 8)
  var line = Line()
  let rootCol = dirColor(0)
  if opts.icons:
    addChunk(line, "\u{F07B}", rootCol, bold = true)
    addChunk(line, " ", rootCol)
  let (rn, _) = truncateRun(root.name, budget)
  addChunk(line, rn, rootCol, bold = true)
  addChunk(line, "/", rootCol, bold = true)
  lines.add line
  for i, c in root.children:
    emitNode(c, @[], i == root.children.len - 1, opts, lines, budget)

proc flatten(chunks: seq[Chunk], color: bool): string =
  for c in chunks:
    let styled = color and (c.fg.len > 0 or c.bold or c.dim)
    if styled:
      if c.fg.len > 0: result.add c.fg
      if c.bold: result.add "\e[1m"
      if c.dim: result.add "\e[2m"
    result.add c.txt
    if styled: result.add AnsiReset

proc renderOutput*(lines: seq[Line], opts: RenderOptions): string =
  var contentMax = 0
  for l in lines:
    if l.contentLen > contentMax: contentMax = l.contentLen
  let sizeCol = if opts.sizes: contentMax + 4 else: 0
  for l in lines:
    result.add flatten(l.chunks, opts.color)
    if opts.sizes and l.hasSize:
      let sizeStr = humanSize(l.size)
      let pad = sizeCol - l.contentLen
      if pad > 0: result.add spaces(pad)
      if opts.color:
        result.add "\e[2m" & sizeStr & AnsiReset
      else:
        result.add sizeStr
    result.add "\n"
