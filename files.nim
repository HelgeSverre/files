import std/[os, strutils, tables, terminal, typedthreads]
import files/[gitstatus, ignore, interrupt, render, util, walk]

const VersionStr = "files 0.2.0"

const DefaultIgnores* = [
  "node_modules/", "target/", "vendor/", "dist/", "build/", "output/",
  "__pycache__/", "venv/", "Pods/", "DerivedData/",
  ".next/", ".nuxt/", ".output/", ".cache/", ".pytest_cache/",
  "*.pyc", "*.pyo", ".DS_Store", "*.class"
]

type CliOptions = object
  path: string
  showAll: bool
  maxDepth: int
  icons: bool
  color: bool
  sizes: bool
  git: bool
  defaults: bool
  extraIgnores: seq[string]
  showHelp: bool
  showVersion: bool

type GitJob = object
  start: string
  statuses: Table[string, string]
  branch: string

proc gitWorker(job: ref GitJob) {.thread.} =
  let gi = fetchGit(job.start)
  job.statuses = gi.statuses
  job.branch = gi.branch

proc usage(): string =
  """
files — a git-aware, pretty directory tree.

Usage:
  files [options] [path]

Options:
  -a, --all            show hidden files and gitignored entries (ghosted)
  -L, --depth <n>      limit recursion depth
  -I, --ignore <glob>  extra ignore pattern (repeatable)
  -t, --sizes          show file sizes (default)
      --no-sizes       hide file sizes
      --no-icons       disable nerd-font file icons
      --no-color       disable colors
      --no-git         do not query git status
      --no-defaults    disable built-in junk ignores (node_modules, target, ...)
  -h, --help           show this help
  -v, --version        print version
"""

proc fail(msg: string) =
  stderr.writeLine("files: " & msg)
  quit(1)

proc parseIntArg(a: string): int =
  try:
    result = parseInt(a)
  except ValueError:
    fail("invalid number: " & a)

proc parseArgs(argv: seq[string]): CliOptions =
  result.maxDepth = -1
  result.icons = true
  result.color = true
  result.sizes = true
  result.git = true
  result.defaults = true
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
      result.color = false
    of "--no-git":
      result.git = false
    of "--no-defaults":
      result.defaults = false
    of "-L", "--depth":
      inc i
      if i >= argv.len: fail("missing value for " & a)
      result.maxDepth = parseIntArg(argv[i])
    of "-I", "--ignore":
      inc i
      if i >= argv.len: fail("missing value for " & a)
      result.extraIgnores.add argv[i]
    else:
      if a.len > 2 and a.startsWith("--depth="):
        result.maxDepth = parseIntArg(a[8 .. ^1])
      elif a.len > 0 and a[0] == '-' and a != "-":
        fail("unknown option: " & a)
      elif result.path.len == 0:
        result.path = a
      else:
        fail("too many arguments")
    inc i
  if result.path.len == 0:
    result.path = "."

proc main() =
  let cli = parseArgs(commandLineParams())
  if cli.showHelp:
    stdout.write(usage())
    quit(0)
  if cli.showVersion:
    stdout.write(VersionStr & "\n")
    quit(0)

  let absRoot = absolutePath(cli.path)
  if not dirExists(absRoot):
    fail("no such directory: " & cli.path)

  interrupt.install()

  var gitignore = newIgnoreMatcher()
  if cli.defaults:
    for d in DefaultIgnores:
      gitignore.addRuleExtra(absRoot, d)
  var extra = newIgnoreMatcher()
  for g in cli.extraIgnores:
    extra.addRuleExtra(absRoot, g)

  var repoRoot = ""
  var statuses = initTable[string, string]()
  var branch = ""
  var gitJob = new(GitJob)
  gitJob.start = absRoot
  var gitThread: Thread[ref GitJob]
  var gitRunning = false
  if cli.git:
    repoRoot = findRepoRoot(absRoot)
    if repoRoot != "":
      gitignore.preload(repoRoot, absRoot)
      createThread(gitThread, gitWorker, gitJob)
      gitRunning = true

  let tty = isatty(stdout)
  let color = cli.color and tty
  let termW = if tty: terminalWidth() else: 0

  let wopts = WalkOptions(maxDepth: cli.maxDepth, showAll: cli.showAll,
                          gitignore: gitignore, extra: extra,
                          repoRoot: repoRoot, statuses: statuses)
  let root = collectNode(absRoot, 0, false, ActiveState(), ActiveState(), wopts)

  if gitRunning:
    joinThread(gitThread)
    statuses = gitJob.statuses
    branch = gitJob.branch
    assignStatuses(root, repoRoot, absRoot, statuses)

  var ropts = RenderOptions(color: color, icons: cli.icons, sizes: cli.sizes,
                            termWidth: if termW > 0: termW else: 100000)
  var lines: seq[Line]
  renderTree(root, ropts, lines)
  let outStr = renderOutput(lines, ropts)

  stdout.write(outStr)

  var dirs, files = 0
  var bytes = 0'i64
  summarize(root, dirs, files, bytes)
  var foot = $dirs & " dirs · " & $files & " files"
  if cli.sizes: foot.add " · " & humanSize(bytes)
  var changed = 0
  for v in statuses.values:
    if v.len > 0: inc changed
  if branch.len > 0:
    foot.add " · " & branch
    if changed > 0: foot.add " · " & $changed & " changed"
  stdout.write(foot & "\n")

when isMainModule:
  main()
