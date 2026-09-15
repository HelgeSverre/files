import std/[strutils]
import ./options

type
  ShellKind* = enum
    skZsh,
    skBash,
    skFish,
    skNu

proc parseShellKind*(s: string): ShellKind =
  case s.toLowerAscii()
  of "zsh":
    skZsh
  of "bash":
    skBash
  of "fish":
    skFish
  of "nu", "nushell":
    skNu
  else:
    raise newException(ValueError, "unsupported shell '" & s & "' (expected zsh, bash, fish, or nu)")

proc allFlags(spec: OptionSpec): seq[string] =
  result = @[]
  if spec.shortName.len > 0:
    result.add spec.shortName
  if spec.longName.len > 0:
    result.add spec.longName
  for a in spec.aliases:
    result.add a

proc escapeZsh(s: string): string =
  result = s.replace("[", "\\[").replace("]", "\\]").replace(":", "\\:").replace("'", "'\\''")

proc generateZsh*(specs: seq[OptionSpec] = OptionSpecs): string =
  var b = ""
  b.add "#compdef files\n\n"
  b.add "# Note: In Zsh, do NOT save this script as '_files' in your $fpath,\n"
  b.add "# as that would shadow Zsh's built-in file completion function.\n"
  b.add "# Use '_files_cli' instead: ~/.zsh/completions/_files_cli\n\n"
  b.add "_files_cli() {\n"
  b.add "    _arguments -s -S \\\n"

  var args: seq[string] = @[]
  for spec in specs:
    let flags = allFlags(spec)
    if flags.len == 0:
      continue

    var argPart = ""
    case spec.argKind
    of akNone:
      discard
    of akChoice:
      argPart = ":" & spec.argName & ":(" & spec.choices.join(" ") & ")"
    of akInt, akString:
      argPart = ":" & spec.argName & ":"

    let desc = escapeZsh(spec.description)

    for f in flags:
      var entry = ""
      if spec.repeatable:
        entry.add "*"
      elif flags.len > 1:
        entry.add "(" & flags.join(" ") & ")"
      entry.add f
      entry.add "[" & desc & "]"
      if argPart.len > 0:
        entry.add argPart
      args.add "        '" & entry & "'"

  args.add "        '*:directory:_files -/'"

  b.add args.join(" \\\n") & "\n"
  b.add "}\n\n"
  b.add "if [ \"$funcstack[1]\" = \"_files_cli\" ]; then\n"
  b.add "    _files_cli \"$@\"\n"
  b.add "else\n"
  b.add "    compdef _files_cli files 2>/dev/null || true\n"
  b.add "fi\n"
  result = b

proc generateBash*(specs: seq[OptionSpec] = OptionSpecs): string =
  var allOpts: seq[string] = @[]
  var choiceCases: seq[string] = @[]
  var argCases: seq[string] = @[]

  for spec in specs:
    let flags = allFlags(spec)
    for f in flags:
      allOpts.add f

    if spec.argKind == akChoice and spec.choices.len > 0:
      let pattern = flags.join("|")
      let choicesStr = spec.choices.join(" ")
      choiceCases.add "        " & pattern & ")\n" &
                      "            COMPREPLY=( $(compgen -W \"" & choicesStr & "\" -- \"$cur\") )\n" &
                      "            return 0\n" &
                      "            ;;"
    elif spec.argKind in {akInt, akString}:
      for f in flags:
        argCases.add f

  var b = ""
  b.add "_files_cli() {\n"
  b.add "    local cur prev\n"
  b.add "    COMPREPLY=()\n"
  b.add "    cur=\"${COMP_WORDS[COMP_CWORD]}\"\n"
  b.add "    prev=\"${COMP_WORDS[COMP_CWORD-1]}\"\n\n"

  if choiceCases.len > 0:
    b.add "    if [[ \"$cur\" == *=* ]]; then\n"
    b.add "        prev=\"${cur%%=*}\"\n"
    b.add "        cur=\"${cur#*=}\"\n"
    b.add "        case \"$prev\" in\n"
    for cc in choiceCases:
      b.add cc & "\n"
    b.add "        esac\n"
    b.add "        return 0\n"
    b.add "    fi\n\n"

  b.add "    case \"$prev\" in\n"
  for cc in choiceCases:
    b.add cc & "\n"
  if argCases.len > 0:
    b.add "        " & argCases.join("|") & ")\n"
    b.add "            return 0\n"
    b.add "            ;;\n"
  b.add "    esac\n\n"

  b.add "    if [[ \"$cur\" == -* ]]; then\n"
  b.add "        local opts=\"" & allOpts.join(" ") & "\"\n"
  b.add "        COMPREPLY=( $(compgen -W \"$opts\" -- \"$cur\") )\n"
  b.add "        return 0\n"
  b.add "    fi\n\n"

  b.add "    if type _filedir >/dev/null 2>&1; then\n"
  b.add "        _filedir -d\n"
  b.add "    else\n"
  b.add "        COMPREPLY=( $(compgen -d -- \"$cur\") )\n"
  b.add "    fi\n"
  b.add "}\n\n"
  b.add "complete -F _files_cli files\n"
  result = b

proc escapeFish(s: string): string =
  result = s.replace("\\", "\\\\").replace("\"", "\\\"")

proc generateFish*(specs: seq[OptionSpec] = OptionSpecs): string =
  var b = ""
  b.add "# fish completion for files\n\n"
  b.add "complete -c files -f\n"

  for spec in specs:
    var line = "complete -c files"
    if spec.shortName.len > 0:
      line.add " -s " & spec.shortName.strip(chars = {'-'})
    if spec.longName.len > 0:
      line.add " -l " & spec.longName.strip(chars = {'-'})
    for a in spec.aliases:
      if a.startsWith("--"):
        line.add " -l " & a.strip(chars = {'-'})
      elif a.startsWith("-"):
        line.add " -s " & a.strip(chars = {'-'})

    case spec.argKind
    of akNone:
      discard
    of akChoice:
      line.add " -x -a \"" & spec.choices.join(" ") & "\""
    of akInt, akString:
      line.add " -r"

    if spec.description.len > 0:
      line.add " -d \"" & escapeFish(spec.description) & "\""

    b.add line & "\n"

  b.add "complete -c files -a \"(__fish_complete_directories)\" -d \"Directory\"\n"
  result = b

proc generateNu*(specs: seq[OptionSpec] = OptionSpecs): string =
  var b = ""
  b.add "# nushell completion for files\n\n"

  for spec in specs:
    if spec.argKind == akChoice and spec.choices.len > 0:
      let flagClean = spec.longName.strip(chars = {'-'})
      b.add "def \"nu-complete files-" & flagClean & "\" [] {\n"
      b.add "  [ "
      for i, c in spec.choices:
        if i > 0:
          b.add " "
        b.add "\"" & c & "\""
      b.add " ]\n"
      b.add "}\n\n"

  b.add "export extern \"files\" [\n"

  for spec in specs:
    var flagDef = "  " & spec.longName
    if spec.shortName.len > 0:
      flagDef.add "(" & spec.shortName & ")"

    case spec.argKind
    of akNone:
      discard
    of akInt:
      flagDef.add ": int"
    of akString:
      flagDef.add ": string"
    of akChoice:
      let flagClean = spec.longName.strip(chars = {'-'})
      flagDef.add ": string@\"nu-complete files-" & flagClean & "\""

    if flagDef.len < 40:
      flagDef.add repeat(' ', 40 - flagDef.len)
    else:
      flagDef.add " "

    flagDef.add "# " & spec.description
    b.add flagDef & "\n"

    for a in spec.aliases:
      var aliasDef = "  " & a
      case spec.argKind
      of akNone:
        discard
      of akInt:
        aliasDef.add ": int"
      of akString:
        aliasDef.add ": string"
      of akChoice:
        let flagClean = spec.longName.strip(chars = {'-'})
        aliasDef.add ": string@\"nu-complete files-" & flagClean & "\""

      if aliasDef.len < 40:
        aliasDef.add repeat(' ', 40 - aliasDef.len)
      else:
        aliasDef.add " "
      aliasDef.add "# " & spec.description
      b.add aliasDef & "\n"

  b.add "  path?: directory                        # directory to list\n"
  b.add "]\n"
  result = b

proc generateCompletion*(shell: ShellKind, specs: seq[OptionSpec] = OptionSpecs): string =
  case shell
  of skZsh:
    result = generateZsh(specs)
  of skBash:
    result = generateBash(specs)
  of skFish:
    result = generateFish(specs)
  of skNu:
    result = generateNu(specs)
