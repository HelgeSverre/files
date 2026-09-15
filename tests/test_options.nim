import std/[strutils, unittest]
import files/[options, render]

suite "CLI options":
  test "environment selects theme":
    let opts = parseArgs(@[], envTheme = "green")
    check opts.path == "."
    check opts.theme == ctGreen
    check opts.colorMode == cmAuto

  test "CLI overrides theme and NO_COLOR":
    let opts = parseArgs(@["--theme=orange", "--color", "always"],
                         envTheme = "ultraviolet", noColorEnv = true)
    check opts.theme == ctOrange
    check opts.colorMode == cmAlways

  test "help remains available with invalid environment theme":
    let opts = parseArgs(@["--help"], envTheme = "ultraviolet")
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
      discard parseArgs(@[], envTheme = "ultraviolet")

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

    let optsShort = parseArgs(@["-R"])
    check optsShort.maxDepth == 1
    check not optsShort.git

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
    check OptionSpecs.len == 15
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
