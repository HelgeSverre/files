import std/[os, strutils]
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

  EnvOptions* = object
    ## Raw environment values are validated only when no CLI flag overrides them.
    theme*, compact*, depth*, icons*, sizes*, git*, all*, defaults*, color*: string
    noColor*: bool

  Setting = enum
    sAll, sDepth, sIcons, sSizes, sGit, sDefaults, sCompact, sColor, sTheme

  CliOptions* = object
    path*: string
    showAll*: bool
    maxDepth*: int
    icons*: bool
    colorMode*: ColorMode
    theme*: ColorTheme
    compact*: bool
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
  OptionSpec(longName: "--no-all", description: "hide hidden and ignored entries (default)", argKind: akNone),
  OptionSpec(shortName: "-L", longName: "--depth", description: "limit recursion depth", argKind: akInt, argName: "n"),
  OptionSpec(shortName: "", longName: "--root", description: "alias for --depth=1 --no-git", argKind: akNone),
  OptionSpec(shortName: "-I", longName: "--ignore", description: "extra ignore pattern (repeatable)", argKind: akString, argName: "glob", repeatable: true),
  OptionSpec(shortName: "-t", longName: "--sizes", description: "show file sizes (default)", argKind: akNone),
  OptionSpec(shortName: "", longName: "--no-sizes", description: "hide file sizes", argKind: akNone),
  OptionSpec(longName: "--compact", description: "combine single-child folder chains into one path", argKind: akNone),
  OptionSpec(longName: "--no-compact", description: "show each folder on its own row (default)", argKind: akNone),
  OptionSpec(longName: "--icons", description: "enable nerd-font file icons (default)", argKind: akNone),
  OptionSpec(shortName: "", longName: "--no-icons", description: "disable nerd-font file icons", argKind: akNone),
  OptionSpec(shortName: "", longName: "--color", description: "colorize: auto, always, or never", argKind: akChoice, argName: "when", choices: ColorChoices),
  OptionSpec(shortName: "", longName: "--no-color", description: "alias for --color=never", argKind: akNone),
  OptionSpec(shortName: "", longName: "--theme", description: "blue, purple, green, red, orange, yellow, or rainbow", argKind: akChoice, argName: "name", choices: ThemeChoices),
  OptionSpec(longName: "--git", description: "query git status (default)", argKind: akNone),
  OptionSpec(shortName: "", longName: "--no-git", description: "do not query git status", argKind: akNone),
  OptionSpec(longName: "--defaults", description: "enable built-in junk ignores (default)", argKind: akNone),
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
  result.add "\nEnvironment (CLI flags override these defaults):\n" &
    "  FILES_ALL          show hidden/ignored entries (false)\n" &
    "  FILES_DEPTH        recursion depth; -1 means unlimited (-1)\n" &
    "  FILES_COMPACT      fold single-child folder chains (false)\n" &
    "  FILES_ICONS        show nerd-font icons (true)\n" &
    "  FILES_SIZES        show file sizes (true)\n" &
    "  FILES_GIT          query git status (true)\n" &
    "  FILES_DEFAULTS     enable built-in ignores (true)\n" &
    "  FILES_COLOR        auto, always, or never (auto)\n" &
    "  FILES_COLOR_THEME  starting color theme (rainbow)\n" &
    "  NO_COLOR           any nonempty value disables color\n\n" &
    "Booleans accept 1/0, true/false, yes/no, or on/off (case insensitive).\n" &
    "Empty values use defaults. Color precedence: CLI > NO_COLOR > FILES_COLOR.\n"

proc readEnv*(): EnvOptions =
  EnvOptions(theme: getEnv("FILES_COLOR_THEME"), compact: getEnv("FILES_COMPACT"),
    depth: getEnv("FILES_DEPTH"), icons: getEnv("FILES_ICONS"),
    sizes: getEnv("FILES_SIZES"), git: getEnv("FILES_GIT"),
    all: getEnv("FILES_ALL"), defaults: getEnv("FILES_DEFAULTS"),
    color: getEnv("FILES_COLOR"), noColor: getEnv("NO_COLOR").len > 0)

proc parseDepth(value, source: string): int =
  try:
    result = parseInt(value)
  except ValueError:
    raise newException(ValueError, "invalid " & source & ": " & value &
      " (expected an integer >= -1; -1 means unlimited)")
  if result < -1:
    raise newException(ValueError, "invalid " & source & ": " & value &
      " (expected an integer >= -1; -1 means unlimited)")

proc envBool(value, name: string, fallback: bool): bool =
  case value.toLowerAscii()
  of "": fallback
  of "0", "false", "no", "off": false
  of "1", "true", "yes", "on": true
  else:
    raise newException(ValueError, "invalid " & name & ": " & value &
      " (expected 1, 0, true, false, yes, no, on, or off)")

proc applyEnv(opts: var CliOptions, env: EnvOptions, explicit: set[Setting]) =
  if sAll notin explicit:
    opts.showAll = envBool(env.all, "FILES_ALL", opts.showAll)
  if sIcons notin explicit:
    opts.icons = envBool(env.icons, "FILES_ICONS", opts.icons)
  if sSizes notin explicit:
    opts.sizes = envBool(env.sizes, "FILES_SIZES", opts.sizes)
  if sGit notin explicit:
    opts.git = envBool(env.git, "FILES_GIT", opts.git)
  if sDefaults notin explicit:
    opts.defaults = envBool(env.defaults, "FILES_DEFAULTS", opts.defaults)
  if sCompact notin explicit:
    opts.compact = envBool(env.compact, "FILES_COMPACT", opts.compact)
  if sDepth notin explicit and env.depth.len > 0:
    opts.maxDepth = parseDepth(env.depth, "FILES_DEPTH")
  if sColor notin explicit:
    if env.noColor:
      opts.colorMode = cmNever
    elif env.color.len > 0:
      try:
        opts.colorMode = parseColorMode(env.color)
      except ValueError:
        raise newException(ValueError, "invalid FILES_COLOR: " & env.color &
          " (expected auto, always, or never)")
  if sTheme notin explicit:
    try:
      opts.theme = parseColorTheme(env.theme)
    except ValueError:
      raise newException(ValueError, "invalid FILES_COLOR_THEME: " & env.theme &
        " (expected blue, purple, green, red, orange, yellow, or rainbow)")

proc parseShell*(s: string): string =
  case s.toLowerAscii()
  of "zsh", "bash", "fish":
    result = s.toLowerAscii()
  of "nu", "nushell":
    result = "nu"
  else:
    raise newException(ValueError, "unsupported shell '" & s & "' (expected zsh, bash, fish, or nu)")

proc parseArgs*(argv: seq[string], env = EnvOptions()): CliOptions =
  result.maxDepth = -1
  result.icons = true
  result.colorMode = cmAuto
  result.theme = ctRainbow
  result.sizes = true
  result.git = true
  result.defaults = true
  var explicit: set[Setting]
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
        explicit.incl sAll
      of "--no-all":
        result.showAll = false
        explicit.incl sAll
      of "--icons":
        result.icons = true
        explicit.incl sIcons
      of "--git":
        result.git = true
        explicit.incl sGit
      of "--defaults":
        result.defaults = true
        explicit.incl sDefaults
      of "--help":
        result.showHelp = true
      of "--version":
        result.showVersion = true
      of "--sizes":
        result.sizes = true
        explicit.incl sSizes
      of "--no-sizes":
        result.sizes = false
        explicit.incl sSizes
      of "--compact":
        result.compact = true
        explicit.incl sCompact
      of "--no-compact":
        result.compact = false
        explicit.incl sCompact
      of "--no-icons":
        result.icons = false
        explicit.incl sIcons
      of "--color":
        result.colorMode = parseColorMode(argVal)
        explicit.incl sColor
      of "--no-color":
        result.colorMode = cmNever
        explicit.incl sColor
      of "--theme":
        result.theme = parseColorTheme(argVal)
        explicit.incl sTheme
      of "--no-git":
        result.git = false
        explicit.incl sGit
      of "--no-defaults":
        result.defaults = false
        explicit.incl sDefaults
      of "--depth":
        result.maxDepth = parseDepth(argVal, "--depth")
        explicit.incl sDepth
      of "--root":
        result.maxDepth = 1
        result.git = false
        explicit.incl sDepth
        explicit.incl sGit
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

  # Informational commands work even when persistent preferences are invalid.
  if not result.showHelp and not result.showVersion and result.completionShell.len == 0:
    applyEnv(result, env, explicit)
  if result.path.len == 0:
    result.path = "."
