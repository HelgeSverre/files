import std/strutils
import ./render

type
  ArgKind* = enum
    akNone,
    akInt,
    akString,
    akChoice

  OptionSpec* = object
    shortName*: string
    longName*: string
    aliases*: seq[string]
    description*: string
    argKind*: ArgKind
    argName*: string
    choices*: seq[string]
    repeatable*: bool

  CliOptions* = object
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
    completionShell*: string

const ColorChoices* = @["auto", "always", "never"]
const ThemeChoices* = @["blue", "purple", "green", "red", "orange", "yellow", "rainbow"]
const ShellChoices* = @["zsh", "bash", "fish", "nu"]

const OptionSpecs*: seq[OptionSpec] = @[
  OptionSpec(shortName: "-a", longName: "--all", description: "show hidden files and gitignored entries (ghosted)", argKind: akNone),
  OptionSpec(shortName: "-L", longName: "--depth", description: "limit recursion depth", argKind: akInt, argName: "n"),
  OptionSpec(shortName: "", longName: "--root", description: "alias for --depth=1 --no-git", argKind: akNone),
  OptionSpec(shortName: "-I", longName: "--ignore", description: "extra ignore pattern (repeatable)", argKind: akString, argName: "glob", repeatable: true),
  OptionSpec(shortName: "-t", longName: "--sizes", description: "show file sizes (default)", argKind: akNone),
  OptionSpec(shortName: "", longName: "--no-sizes", description: "hide file sizes", argKind: akNone),
  OptionSpec(shortName: "", longName: "--no-icons", description: "disable nerd-font file icons", argKind: akNone),
  OptionSpec(shortName: "", longName: "--color", description: "colorize: auto, always, or never", argKind: akChoice, argName: "when", choices: ColorChoices),
  OptionSpec(shortName: "", longName: "--no-color", description: "alias for --color=never", argKind: akNone),
  OptionSpec(shortName: "", longName: "--theme", description: "blue, purple, green, red, orange, yellow, or rainbow", argKind: akChoice, argName: "name", choices: ThemeChoices),
  OptionSpec(shortName: "", longName: "--no-git", description: "do not query git status", argKind: akNone),
  OptionSpec(shortName: "", longName: "--no-defaults", description: "disable built-in junk ignores (node_modules, target, ...)", argKind: akNone),
  OptionSpec(shortName: "", longName: "--completions", aliases: @["--completion"], description: "generate shell completion script (zsh, bash, fish, nu)", argKind: akChoice, argName: "shell", choices: ShellChoices),
  OptionSpec(shortName: "-h", longName: "--help", description: "show this help", argKind: akNone),
  OptionSpec(shortName: "-v", longName: "--version", description: "print version", argKind: akNone)
]

proc findSpec*(name: string): (bool, OptionSpec) =
  for s in OptionSpecs:
    if s.longName == name or (s.shortName.len > 0 and s.shortName == name):
      return (true, s)
    for a in s.aliases:
      if a == name:
        return (true, s)
  return (false, OptionSpec())

proc formatOption*(spec: OptionSpec): string =
  var flagPart = "  "
  if spec.shortName.len > 0:
    flagPart.add spec.shortName & ", " & spec.longName
  else:
    flagPart.add "    " & spec.longName
  if spec.argName.len > 0:
    flagPart.add " <" & spec.argName & ">"
  if flagPart.len < 23:
    flagPart.add repeat(' ', 23 - flagPart.len)
  else:
    flagPart.add "  "
  result = flagPart & spec.description

proc formatUsage*(): string =
  result = "files — a git-aware, pretty directory tree.\n\n" &
           "Usage:\n" &
           "  files [options] [path]\n\n" &
           "Options:\n"
  for spec in OptionSpecs:
    result.add formatOption(spec) & "\n"

proc parseIntArg(a: string): int =
  try:
    result = parseInt(a)
  except ValueError:
    raise newException(ValueError, "invalid number: " & a)

proc parseShell*(s: string): string =
  case s.toLowerAscii()
  of "zsh", "bash", "fish":
    result = s.toLowerAscii()
  of "nu", "nushell":
    result = "nu"
  else:
    raise newException(ValueError, "unsupported shell '" & s & "' (expected zsh, bash, fish, or nu)")

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
    if a.len > 0 and a[0] == '-' and a != "-":
      var flag = a
      var val = ""
      var hasVal = false
      if a.startsWith("--"):
        let eqIdx = a.find('=')
        if eqIdx >= 0:
          flag = a[0 ..< eqIdx]
          val = a[eqIdx + 1 .. ^1]
          hasVal = true

      let (found, spec) = findSpec(flag)
      if not found:
        raise newException(ValueError, "unknown option: " & a)

      var argVal = ""
      if spec.argKind == akNone:
        if hasVal:
          raise newException(ValueError, "unknown option: " & a)
      else:
        if hasVal:
          argVal = val
        else:
          inc i
          if i >= argv.len:
            raise newException(ValueError, "missing value for " & flag)
          argVal = argv[i]

      case spec.longName
      of "--all":
        result.showAll = true
      of "--help":
        result.showHelp = true
      of "--version":
        result.showVersion = true
      of "--sizes":
        result.sizes = true
      of "--no-sizes":
        result.sizes = false
      of "--no-icons":
        result.icons = false
      of "--color":
        result.colorMode = parseColorMode(argVal)
      of "--no-color":
        result.colorMode = cmNever
      of "--theme":
        result.theme = parseColorTheme(argVal)
        themeExplicit = true
      of "--no-git":
        result.git = false
      of "--no-defaults":
        result.defaults = false
      of "--depth":
        result.maxDepth = parseIntArg(argVal)
      of "--root":
        result.maxDepth = 1
        result.git = false
      of "--ignore":
        result.extraIgnores.add argVal
      of "--completions":
        result.completionShell = parseShell(argVal)
      else:
        discard
    elif result.path.len == 0:
      result.path = a
    else:
      raise newException(ValueError, "too many arguments")
    inc i

  if not themeExplicit and not result.showHelp and not result.showVersion:
    result.theme = parseColorTheme(envTheme)
  if result.path.len == 0:
    result.path = "."
