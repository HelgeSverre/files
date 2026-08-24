import std/unittest
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

suite "color activation":
  test "auto follows terminal detection":
    check colorEnabled(cmAuto, true)
    check not colorEnabled(cmAuto, false)

  test "explicit modes override terminal detection":
    check colorEnabled(cmAlways, false)
    check not colorEnabled(cmNever, true)
