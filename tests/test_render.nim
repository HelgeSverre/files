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

proc compactTree(): Node =
  result = Node(name: "repo", kind: kDir)
  let src = Node(name: "src", kind: kDir, depth: 1)
  let main = Node(name: "main", kind: kDir, depth: 2)
  let kotlin = Node(name: "kotlin", kind: kDir, depth: 3)
  kotlin.children = @[
    Node(name: "AdParser.kt", kind: kFile, depth: 4, size: 1024, status: "M "),
    Node(name: "Model.kt", kind: kFile, depth: 4)]
  main.children = @[kotlin]
  src.children = @[main]
  result.children = @[src, Node(name: "README.md", kind: kFile, depth: 1)]

proc renderNode(root: Node, compact = true, color = false, sizes = false,
                width = 120): string =
  let opts = RenderOptions(compact: compact, color: color, sizes: sizes,
                           icons: false, termWidth: width)
  var lines: seq[Line]
  renderTree(root, opts, lines)
  renderOutput(lines, opts)

suite "directory compaction":
  test "chains compact while root, siblings, files and badges remain":
    check renderNode(compactTree()) == "repo/\n" &
      "├── src/main/kotlin/\n" &
      "│   ├── AdParser.kt [M]\n" &
      "│   └── Model.kt\n" &
      "└── README.md\n"

  test "disabled mode retains individual rows":
    let output = renderNode(compactTree(), compact = false)
    check "├── src/\n│   └── main/\n│       └── kotlin/" in output
    check "src/main" notin output

  test "every folder segment retains its original rainbow depth color":
    let output = renderNode(compactTree(), color = true)
    for depth, name in @["src/", "main/", "kotlin/"]:
      let (r, g, b) = hslToRgb(float((215 + (depth + 1) * 32) mod 360), 0.5, 0.72)
      check rgb(r, g, b) & "\e[1m" & name & AnsiReset in output

  test "rendering preserves real nodes, depths, statistics and sizes":
    let root = compactTree()
    let output = renderNode(root, sizes = true)
    check "1.0 KB" in output
    check root.children[0].name == "src"
    check root.children[0].children[0].name == "main"
    check root.children[0].children[0].children[0].depth == 3
    var dirs, files: int
    var bytes: int64
    summarize(root, dirs, files, bytes)
    check dirs == 4
    check files == 3
    check bytes == 1024

  test "branching directories stop compaction":
    let root = compactTree()
    root.children[0].children.add Node(name: "test", kind: kDir, depth: 2)
    let output = renderNode(root)
    check "├── src/\n│   ├── main/kotlin/" in output
    check "│   └── test/" in output

  test "files alongside directories prevent folding":
    let root = compactTree()
    root.children[0].children.add Node(name: "notes.txt", kind: kFile, depth: 2)
    check "├── src/\n│   ├── main/kotlin/" in renderNode(root)

  test "symlinks are not folded":
    let root = compactTree()
    root.children[0].children = @[
      Node(name: "linked", kind: kLink, depth: 2, linkTarget: "elsewhere")]
    check "├── src/\n│   └── linked → elsewhere" in renderNode(root)

  test "empty directories and collected depth boundaries terminate chains":
    let root = compactTree()
    root.children[0].children[0].children = @[]
    check "├── src/main/\n└── README.md" in renderNode(root)

  test "visibility boundaries retain their separate styling":
    let root = compactTree()
    root.children[0].children[0].hidden = true
    check "├── src/\n│   └── main/\n" in renderNode(root)

  test "compacted paths respect terminal width including Unicode":
    let root = compactTree()
    root.children[0].children[0].name = "日本語"
    root.children[0].children[0].children[0].children[0].status = ""
    let output = renderNode(root, width = 17)
    for line in output.splitLines:
      check displayWidth(line) <= 17
    check "AdParser" in output
