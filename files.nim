import std/[os, tables, terminal, typedthreads]
import files/[completions, gitstatus, ignore, interrupt, options, render, util, walk]

const VersionStr = "files 0.2.6"

const DefaultIgnores* = [
  "node_modules/", "target/", "vendor/", "dist/", "build/", "output/",
  "__pycache__/", "venv/", "Pods/", "DerivedData/",
  ".next/", ".nuxt/", ".output/", ".cache/", ".pytest_cache/",
  "*.pyc", "*.pyo", ".DS_Store", "*.class"
]

type GitJob = object
  start: string
  statuses: Table[string, string]
  branch: string

proc gitWorker(job: ref GitJob) {.thread.} =
  let gi = fetchGit(job.start)
  job.statuses = gi.statuses
  job.branch = gi.branch

proc usage(): string =
  formatUsage()

proc fail(msg: string) =
  stderr.writeLine("files: " & msg)
  quit(1)

type RunState = object
  cli: CliOptions
  absRoot: string
  gitignore: IgnoreMatcher
  extra: IgnoreMatcher
  repoRoot: string
  statuses: Table[string, string]
  branch: string
  changed: int
  gitJob: ref GitJob
  gitThread: Thread[ref GitJob]
  gitRunning: bool
  root: Node

proc setupMatchers(rs: var RunState) =
  ## Resolve the target directory, install the interrupt handler, and build
  ## the gitignore matchers (built-in defaults plus any -I patterns).
  rs.absRoot = absolutePath(rs.cli.path)
  if not dirExists(rs.absRoot):
    fail("no such directory: " & rs.cli.path)
  interrupt.install()
  rs.gitignore = newIgnoreMatcher()
  if rs.cli.defaults:
    for d in DefaultIgnores:
      rs.gitignore.addRuleExtra(rs.absRoot, d)
  rs.extra = newIgnoreMatcher()
  for g in rs.cli.extraIgnores:
    rs.extra.addRuleExtra(rs.absRoot, g)

proc startGitFetch(rs: var RunState) =
  ## Kick off git status + branch on a background thread; the tree walk runs
  ## concurrently and `finishGit` joins the results afterwards.
  if not rs.cli.git: return
  rs.repoRoot = findRepoRoot(rs.absRoot)
  if rs.repoRoot == "": return
  discard rs.gitignore.preloadForWalk(rs.repoRoot, rs.absRoot)
  rs.gitJob = new(GitJob)
  rs.gitJob.start = rs.absRoot
  createThread(rs.gitThread, gitWorker, rs.gitJob)
  rs.gitRunning = true

proc walkTree(rs: var RunState) =
  let wopts = WalkOptions(maxDepth: rs.cli.maxDepth, showAll: rs.cli.showAll,
                          gitignore: rs.gitignore, extra: rs.extra)
  let ctx = newWalkContext(wopts, rs.gitignore, rs.extra)
  rs.root = collectNode(ctx, ActiveState(), ActiveState(), rs.absRoot, 0, false)

proc finishGit(rs: var RunState) =
  ## Wait for the git thread, then stamp status badges onto the walked tree.
  ## `changed` counts only badges that landed in the shown subtree.
  if not rs.gitRunning: return
  joinThread(rs.gitThread)
  rs.statuses = rs.gitJob.statuses
  rs.branch = rs.gitJob.branch
  rs.changed = assignStatuses(rs.root, rs.repoRoot, rs.absRoot, rs.statuses)

proc renderTreeOutput(rs: RunState): string =
  let tty = isatty(stdout)
  let color = colorEnabled(rs.cli.colorMode, tty)
  let termW = if tty: terminalWidth() else: 0
  var ropts = RenderOptions(color: color, theme: rs.cli.theme,
                            icons: rs.cli.icons, sizes: rs.cli.sizes,
                            termWidth: if termW > 0: termW else: 100000)
  var lines: seq[Line]
  renderTree(rs.root, ropts, lines)
  renderOutput(lines, ropts)

proc footer(rs: RunState): string =
  var dirs, files = 0
  var bytes = 0'i64
  summarize(rs.root, dirs, files, bytes)
  result = $dirs & " dirs · " & $files & " files"
  if rs.cli.sizes: result.add " · " & humanSize(bytes)
  if rs.branch.len > 0:
    result.add " · " & rs.branch
    if rs.changed > 0: result.add " · " & $rs.changed & " changed"

proc main() =
  let noColor = existsEnv("NO_COLOR") and getEnv("NO_COLOR").len > 0
  var cli: CliOptions
  try:
    cli = parseArgs(commandLineParams(), getEnv("FILES_COLOR_THEME"), noColor)
  except ValueError:
    fail(getCurrentExceptionMsg())
  if cli.completionShell.len > 0:
    try:
      let shellKind = parseShellKind(cli.completionShell)
      stdout.write(generateCompletion(shellKind))
      quit(0)
    except ValueError:
      fail(getCurrentExceptionMsg())
  if cli.showHelp:
    stdout.write(usage())
    quit(0)
  if cli.showVersion:
    stdout.write(VersionStr & "\n")
    quit(0)
  var rs = RunState(cli: cli)
  setupMatchers(rs)
  startGitFetch(rs)
  walkTree(rs)
  finishGit(rs)
  stdout.write(renderTreeOutput(rs))
  stdout.write(footer(rs) & "\n")

when isMainModule:
  main()
