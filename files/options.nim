import std/strutils
import ./render

type CliOptions* = object
  path*: string
  showAll*: bool
  maxDepth*: int
  icons*: bool
  colorMode*: ColorMode
  theme*: ColorTheme
  sizes*: bool
  git*: bool
  defaults*: bool
  extraIgnores*: seq[string]
  showHelp*: bool
  showVersion*: bool

proc parseIntArg(a: string): int =
  try:
    result = parseInt(a)
  except ValueError:
    raise newException(ValueError, "invalid number: " & a)

proc parseArgs*(argv: seq[string], envTheme = "",
                noColorEnv = false): CliOptions =
  result.maxDepth = -1
  result.icons = true
  result.colorMode = if noColorEnv: cmNever else: cmAuto
  result.theme = ctRainbow
  result.sizes = true
  result.git = true
  result.defaults = true
  var themeExplicit = false
  var i = 0
  while i < argv.len:
    let a = argv[i]
    case a
    of "-a", "--all":
      result.showAll = true
    of "-h", "--help":
      result.showHelp = true
    of "-v", "--version":
      result.showVersion = true
    of "-t", "--sizes":
      result.sizes = true
    of "--no-sizes":
      result.sizes = false
    of "--no-icons":
      result.icons = false
    of "--no-color":
      result.colorMode = cmNever
    of "--no-git":
      result.git = false
    of "--no-defaults":
      result.defaults = false
    of "-L", "--depth":
      inc i
      if i >= argv.len:
        raise newException(ValueError, "missing value for " & a)
      result.maxDepth = parseIntArg(argv[i])
    of "-I", "--ignore":
      inc i
      if i >= argv.len:
        raise newException(ValueError, "missing value for " & a)
      result.extraIgnores.add argv[i]
    of "--color":
      inc i
      if i >= argv.len:
        raise newException(ValueError, "missing value for " & a)
      result.colorMode = parseColorMode(argv[i])
    of "--theme":
      inc i
      if i >= argv.len:
        raise newException(ValueError, "missing value for " & a)
      result.theme = parseColorTheme(argv[i])
      themeExplicit = true
    else:
      if a.startsWith("--depth="):
        result.maxDepth = parseIntArg(a[8 .. ^1])
      elif a.startsWith("--color="):
        result.colorMode = parseColorMode(a[8 .. ^1])
      elif a.startsWith("--theme="):
        result.theme = parseColorTheme(a[8 .. ^1])
        themeExplicit = true
      elif a.len > 0 and a[0] == '-' and a != "-":
        raise newException(ValueError, "unknown option: " & a)
      elif result.path.len == 0:
        result.path = a
      else:
        raise newException(ValueError, "too many arguments")
    inc i
  if not themeExplicit and not result.showHelp and not result.showVersion:
    result.theme = parseColorTheme(envTheme)
  if result.path.len == 0:
    result.path = "."
