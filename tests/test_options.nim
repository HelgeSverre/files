import std/[strutils, unittest]
import files/[options, render]

suite "CLI options":
  test "environment selects theme":
    let opts = parseArgs(@[], env = EnvOptions(theme: "green"))
    check opts.path == "."
    check opts.theme == ctGreen
    check opts.colorMode == cmAuto

  test "CLI overrides theme and NO_COLOR":
    let opts = parseArgs(@["--theme=orange", "--color", "always"],
                         env = EnvOptions(theme: "ultraviolet", noColor: true))
    check opts.theme == ctOrange
    check opts.colorMode == cmAlways

  test "help remains available with invalid environment theme":
    let opts = parseArgs(@["--help"], env = EnvOptions(theme: "ultraviolet"))
    check opts.showHelp
    check opts.theme == ctRainbow

  test "no-color remains a compatibility alias":
    check parseArgs(@["--no-color"]).colorMode == cmNever

  test "separate and equals forms parse":
    let opts = parseArgs(@["--theme", "blue", "--color=never", "-L", "3",
                           "project"])
    check opts.theme == ctBlue
    check opts.colorMode == cmNever
    check opts.maxDepth == 3
    check opts.path == "project"

  test "invalid theme is rejected":
    expect ValueError:
      discard parseArgs(@[], env = EnvOptions(theme: "ultraviolet"))

  test "invalid color mode is rejected":
    expect ValueError:
      discard parseArgs(@["--color=sometimes"])

  test "flag toggles and repeatable ignores":
    let opts = parseArgs(@["-a", "--no-git", "--no-defaults", "--no-sizes",
                           "-I", "*.nim", "--ignore=*.c", "-t"])
    check opts.showAll
    check not opts.git
    check not opts.defaults
    check opts.sizes  # -t after --no-sizes re-enables it
    check opts.extraIgnores == @["*.nim", "*.c"]

  test "root is an alias for depth=1 and no-git":
    let opts = parseArgs(@["--root"])
    check opts.maxDepth == 1
    check not opts.git

  test "completion options parse":
    let opts1 = parseArgs(@["--completions", "zsh"])
    check opts1.completionShell == "zsh"

    let opts2 = parseArgs(@["--completions=bash"])
    check opts2.completionShell == "bash"

    let opts3 = parseArgs(@["--completion", "fish"])
    check opts3.completionShell == "fish"

    let opts4 = parseArgs(@["--completion=nu"])
    check opts4.completionShell == "nu"

    # Case-insensitive shell parsing
    check parseArgs(@["--completions=ZSH"]).completionShell == "zsh"
    check parseArgs(@["--completion", "Fish"]).completionShell == "fish"
    check parseArgs(@["--completions=NuShell"]).completionShell == "nu"

    # Completion flag with positional path
    let opts5 = parseArgs(@["--completions", "zsh", "src"])
    check opts5.completionShell == "zsh"
    check opts5.path == "src"

  test "missing value errors":
    expect ValueError:
      discard parseArgs(@["-L"])
    expect ValueError:
      discard parseArgs(@["--depth"])
    expect ValueError:
      discard parseArgs(@["--color"])
    expect ValueError:
      discard parseArgs(@["--theme"])
    expect ValueError:
      discard parseArgs(@["-I"])
    expect ValueError:
      discard parseArgs(@["--completions"])
    expect ValueError:
      discard parseArgs(@["--completion"])

  test "unknown options and invalid flag values":
    expect ValueError:
      discard parseArgs(@["--unknown-flag"])
    expect ValueError:
      discard parseArgs(@["-z"])
    expect ValueError:
      discard parseArgs(@["--all=yes"])
    expect ValueError:
      discard parseArgs(@["--depth=notanumber"])
    expect ValueError:
      discard parseArgs(@["--completions=unknown"])
    expect ValueError:
      discard parseArgs(@["--completion", "powershell"])
    expect ValueError:
      discard parseArgs(@["dir1", "dir2"])

suite "declarative option registry":
  test "all standard options are registered":
    check OptionSpecs.len == 21
    let (hasDepth, depthSpec) = findSpec("--depth")
    check hasDepth
    check depthSpec.shortName == "-L"
    check depthSpec.argKind == akInt
    check depthSpec.argName == "n"

    let (hasColor, colorSpec) = findSpec("--color")
    check hasColor
    check colorSpec.argKind == akChoice
    check colorSpec.choices == ColorChoices

    let (hasTheme, themeSpec) = findSpec("--theme")
    check hasTheme
    check themeSpec.argKind == akChoice
    check themeSpec.choices == ThemeChoices

    let (hasIgnore, ignoreSpec) = findSpec("-I")
    check hasIgnore
    check ignoreSpec.argKind == akString
    check ignoreSpec.repeatable

    let (hasComp, compSpec) = findSpec("--completions")
    check hasComp
    check compSpec.argKind == akChoice
    check compSpec.argName == "shell"
    check compSpec.choices == ShellChoices
    check compSpec.aliases == @["--completion"]

    let (hasAlias, aliasSpec) = findSpec("--completion")
    check hasAlias
    check aliasSpec.longName == "--completions"

  test "formatUsage outputs aligned options":
    let usage = formatUsage()
    check "files — a git-aware, pretty directory tree." in usage
    check "Usage:\n  files [options] [path]" in usage
    check "  -a, --all            show hidden files and gitignored entries (ghosted)" in usage
    check "  -L, --depth <n>      limit recursion depth" in usage
    check "    --completions <shell>  generate shell completion script (zsh, bash, fish, nu)" in usage
    check "  -v, --version        print version" in usage

suite "color activation":
  test "auto follows terminal detection":
    check colorEnabled(cmAuto, true)
    check not colorEnabled(cmAuto, false)

  test "explicit modes override terminal detection":
    check colorEnabled(cmAlways, false)
    check not colorEnabled(cmNever, true)

suite "compaction options":
  test "off by default and explicitly toggleable, last flag wins":
    check not parseArgs(@[]).compact
    check parseArgs(@["--compact"]).compact
    check not parseArgs(@["--compact", "--no-compact"]).compact
    check parseArgs(@["--no-compact", "--compact"]).compact

  test "environment accepts boolean values":
    for value in ["1", "true", "yes", "on", "TRUE"]:
      check parseArgs(@[], env = EnvOptions(compact: value)).compact
    for value in ["", "0", "false", "no", "off", "FALSE"]:
      check not parseArgs(@[], env = EnvOptions(compact: value)).compact

  test "explicit flags override environment including invalid values":
    check not parseArgs(@["--no-compact"], env = EnvOptions(compact: "1")).compact
    check parseArgs(@["--compact"], env = EnvOptions(compact: "invalid")).compact

  test "invalid environment is actionable but does not block help or completions":
    expect ValueError:
      discard parseArgs(@[], env = EnvOptions(compact: "invalid"))
    check parseArgs(@["--help"], env = EnvOptions(compact: "invalid")).showHelp
    check parseArgs(@["--version"], env = EnvOptions(compact: "invalid")).showVersion
    check parseArgs(@["--completions=zsh"], env = EnvOptions(compact: "invalid")).completionShell == "zsh"

  test "boolean flags reject values":
    expect ValueError:
      discard parseArgs(@["--compact=true"])
    expect ValueError:
      discard parseArgs(@["--no-compact=false"])

suite "environment preferences":
  test "empty environment preserves every built-in default":
    let opts = parseArgs(@[], EnvOptions())
    check opts.maxDepth == -1
    check opts.icons and opts.sizes and opts.git and opts.defaults
    check not opts.showAll and not opts.compact
    check opts.colorMode == cmAuto
    check opts.theme == ctRainbow

  test "all environment settings select their corresponding options":
    let opts = parseArgs(@[], EnvOptions(depth: "4", icons: "0", sizes: "false",
      git: "off", defaults: "no", all: "yes", compact: "true",
      color: "always", theme: "purple"))
    check opts.maxDepth == 4
    check not opts.icons and not opts.sizes and not opts.git and not opts.defaults
    check opts.showAll and opts.compact
    check opts.colorMode == cmAlways
    check opts.theme == ctPurple

  test "every boolean uses the same case-insensitive vocabulary":
    for value in ["1", "TRUE", "yes", "ON", "0", "FALSE", "no", "OFF"]:
      let enabled = value in ["1", "TRUE", "yes", "ON"]
      let opts = parseArgs(@[], EnvOptions(icons: value, sizes: value, git: value,
        defaults: value, all: value, compact: value))
      check opts.icons == enabled
      check opts.sizes == enabled
      check opts.git == enabled
      check opts.defaults == enabled
      check opts.showAll == enabled
      check opts.compact == enabled

  test "positive CLI switches restore preferences disabled in environment":
    let opts = parseArgs(@["--icons", "--sizes", "--git", "--defaults",
      "--all", "--compact", "--depth=3", "--color=always", "--theme=blue"],
      EnvOptions(icons: "0", sizes: "0", git: "0", defaults: "0", all: "0",
        compact: "0", depth: "1", color: "never", theme: "purple", noColor: true))
    check opts.icons and opts.sizes and opts.git and opts.defaults
    check opts.showAll and opts.compact
    check opts.maxDepth == 3
    check opts.colorMode == cmAlways
    check opts.theme == ctBlue

  test "negative CLI switches disable preferences enabled in environment":
    let opts = parseArgs(@["--no-icons", "--no-sizes", "--no-git", "--no-defaults",
      "--no-all", "--no-compact", "--no-color"], EnvOptions(icons: "1", sizes: "1",
      git: "1", defaults: "1", all: "1", compact: "1", color: "always"))
    check not opts.icons and not opts.sizes and not opts.git and not opts.defaults
    check not opts.showAll and not opts.compact
    check opts.colorMode == cmNever

  test "CLI overrides invalid values only for the corresponding setting":
    let invalid = EnvOptions(icons: "invalid", sizes: "invalid", git: "invalid",
      defaults: "invalid", all: "invalid", compact: "invalid", depth: "invalid",
      color: "invalid", theme: "invalid")
    let opts = parseArgs(@["--icons", "--sizes", "--git", "--defaults", "--all",
      "--compact", "-L", "2", "--color=auto", "--theme=green"], invalid)
    check opts.icons and opts.sizes and opts.git and opts.defaults
    check opts.showAll and opts.compact
    check opts.maxDepth == 2
    check opts.colorMode == cmAuto
    check opts.theme == ctGreen
    expect ValueError:
      discard parseArgs(@["--icons"], EnvOptions(icons: "invalid", git: "invalid"))

  test "NO_COLOR overrides FILES_COLOR, including invalid values":
    check parseArgs(@[], EnvOptions(color: "always", noColor: true)).colorMode == cmNever
    check parseArgs(@[], EnvOptions(color: "invalid", noColor: true)).colorMode == cmNever
    check parseArgs(@["--color=auto"], EnvOptions(color: "never", noColor: true)).colorMode == cmAuto
    check parseArgs(@[], EnvOptions(color: "ALWAYS")).colorMode == cmAlways

  test "root overrides both depth and git preferences; later flags win":
    let env = EnvOptions(depth: "invalid", git: "invalid")
    let root = parseArgs(@["--root"], env)
    check root.maxDepth == 1
    check not root.git
    let later = parseArgs(@["--root", "--git", "-L", "5"], env)
    check later.maxDepth == 5
    check later.git
    let toggles = parseArgs(@["--no-all", "--all", "--icons", "--no-icons",
      "--no-defaults", "--defaults", "--no-git", "--git"])
    check toggles.showAll and toggles.defaults and toggles.git
    check not toggles.icons

  test "depth accepts zero and unlimited but rejects invalid input with source":
    check parseArgs(@[], EnvOptions(depth: "0")).maxDepth == 0
    check parseArgs(@[], EnvOptions(depth: "-1")).maxDepth == -1
    for value in ["-2", "abc", "1.5", "9999999999999999999999999999"]:
      try:
        discard parseArgs(@[], EnvOptions(depth: value))
        check false
      except ValueError as e:
        check "FILES_DEPTH" in e.msg
      expect ValueError:
        discard parseArgs(@["--depth=" & value])

  test "invalid values name the environment variable to fix":
    for (env, name) in [
      (EnvOptions(icons: "bad"), "FILES_ICONS"),
      (EnvOptions(sizes: "bad"), "FILES_SIZES"),
      (EnvOptions(git: "bad"), "FILES_GIT"),
      (EnvOptions(defaults: "bad"), "FILES_DEFAULTS"),
      (EnvOptions(all: "bad"), "FILES_ALL"),
      (EnvOptions(compact: "bad"), "FILES_COMPACT"),
      (EnvOptions(color: "bad"), "FILES_COLOR"),
      (EnvOptions(theme: "bad"), "FILES_COLOR_THEME")]:
      try:
        discard parseArgs(@[], env)
        check false
      except ValueError as e:
        check name in e.msg

  test "informational commands ignore all persistent preferences":
    let invalid = EnvOptions(icons: "bad", sizes: "bad", git: "bad",
      defaults: "bad", all: "bad", compact: "bad", depth: "bad",
      color: "bad", theme: "bad")
    check parseArgs(@["--help"], invalid).showHelp
    check parseArgs(@["--version"], invalid).showVersion
    check parseArgs(@["--completions=zsh"], invalid).completionShell == "zsh"
