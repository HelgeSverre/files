import std/[strutils, unittest]
import files/[render, util, walk]

proc sampleTree(): Node =
  result = Node(name: "repo", kind: kDir, depth: 0)
  let dir = Node(name: "src", kind: kDir, depth: 1)
  dir.children.add Node(name: "main.nim", kind: kFile, depth: 2, status: "M ")
  result.children.add dir

proc rendered(theme: ColorTheme, color = true): string =
  let opts = RenderOptions(color: color, theme: theme, icons: false,
                           sizes: false, termWidth: 120)
  var lines: seq[Line]
  renderTree(sampleTree(), opts, lines)
  renderOutput(lines, opts)

suite "tree rendering":
  test "named themes change structural colors":
    let purple = rendered(ctPurple)
    let green = rendered(ctGreen)
    check purple != green
    check purple.contains("repo")
    check green.contains("repo")

  test "named theme rotates from its starting hue with depth":
    let purple = rendered(ctPurple)
    let (r0, g0, b0) = hslToRgb(275.0, 0.5, 0.72)
    let (r1, g1, b1) = hslToRgb(307.0, 0.5, 0.72)
    check purple.contains(rgb(r0, g0, b0))
    check purple.contains(rgb(r1, g1, b1))

  test "semantic badge colors do not change with theme":
    check rendered(ctPurple).contains(Green & "\e[1m [M]")
    check rendered(ctYellow).contains(Green & "\e[1m [M]")

  test "disabled color emits no ANSI escapes":
    check not rendered(ctRed, color = false).contains("\e[")

  test "rainbow remains the default parser value":
    check parseColorTheme("") == ctRainbow
    check parseColorTheme("default") == ctRainbow
    check parseColorTheme("RAINBOW") == ctRainbow
