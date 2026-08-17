import std/[strutils, math, unicode]

const AnsiReset* = "\e[0m"

proc rgb*(r, g, b: int): string =
  "\e[38;2;" & $r & ";" & $g & ";" & $b & "m"

proc hslToRgb*(h, s, l: float): (int, int, int) =
  let c = (1.0 - abs(2.0 * l - 1.0)) * s
  let hp = (h / 60.0) mod 6.0
  let x = c * (1.0 - abs(hp mod 2.0 - 1.0))
  var r1, g1, b1: float
  if hp < 1.0: (r1, g1, b1) = (c, x, 0.0)
  elif hp < 2.0: (r1, g1, b1) = (x, c, 0.0)
  elif hp < 3.0: (r1, g1, b1) = (0.0, c, x)
  elif hp < 4.0: (r1, g1, b1) = (0.0, x, c)
  elif hp < 5.0: (r1, g1, b1) = (x, 0.0, c)
  else: (r1, g1, b1) = (c, 0.0, x)
  let m = l - c / 2.0
  let rr = int((r1 + m) * 255.0)
  let gg = int((g1 + m) * 255.0)
  let bb = int((b1 + m) * 255.0)
  (max(0, min(255, rr)), max(0, min(255, gg)), max(0, min(255, bb)))

proc naturalCompare*(a, b: string): int =
  var i, j = 0
  while i < a.len and j < b.len:
    let ca = a[i]
    let cb = b[j]
    if ca.isDigit and cb.isDigit:
      var ei = i
      while ei < a.len and a[ei].isDigit: inc ei
      var ej = j
      while ej < b.len and b[ej].isDigit: inc ej
      let la = ei - i
      let lb = ej - j
      if la != lb:
        return (if la < lb: -1 else: 1)
      let c = cmp(a[i ..< ei], b[j ..< ej])
      if c != 0: return c
      i = ei
      j = ej
    else:
      let c = cmp(ca, cb)
      if c != 0: return c
      inc i
      inc j
  cmp(a.len, b.len)

proc humanSize*(n: int64): string =
  const units = ["B", "KB", "MB", "GB", "TB"]
  var u = 0
  var denom: int64 = 1
  while denom <= n div 1024 and u < units.len - 1:
    denom *= 1024
    inc u
  if u == 0:
    result = $n & " B"
  else:
    let whole = n div denom
    if whole >= 100:
      result = $whole & " " & units[u]
    else:
      let frac = (n mod denom) * 10 div denom
      result = $whole & "." & $frac & " " & units[u]

proc runeWidth*(r: Rune): int =
  let cp = int(r)
  if cp == 0: return 0
  if cp < 32 or (cp >= 0x7F and cp < 0xA0): return 0
  if cp >= 0x1100 and (cp <= 0x115F or cp == 0x2329 or cp == 0x232A or
      (cp >= 0x2E80 and cp <= 0xA4CF and cp != 0x303F) or
      (cp >= 0xAC00 and cp <= 0xD7A3) or
      (cp >= 0xF900 and cp <= 0xFAFF) or
      (cp >= 0xFE10 and cp <= 0xFE19) or
      (cp >= 0xFE30 and cp <= 0xFE6F) or
      (cp >= 0xFF00 and cp <= 0xFF60) or
      (cp >= 0xFFE0 and cp <= 0xFFE6) or
      (cp >= 0x1F300 and cp <= 0x1F64F) or
      (cp >= 0x1F900 and cp <= 0x1F9FF)):
    return 2
  result = 1

proc displayWidth*(s: string): int =
  var i = 0
  while i < s.len:
    let ch = s[i]
    if ch < '\128':
      inc result
      inc i
    else:
      let l = runeLenAt(s, i)
      if l <= 0: inc i; continue
      result += runeWidth(runeAt(s, i))
      inc i, l
