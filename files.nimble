import std/strutils

version       = staticRead("VERSION").strip()
author        = "Helge Sverre"
description   = "A fast, git-aware directory tree for your terminal"
license       = "MIT"
bin           = @["files"]
binDir        = "bin"
skipDirs      = @["tests", "assets", "scripts"]
skipFiles     = @["install.sh", "justfile", "screenshot.png"]

requires "nim >= 2.0.0"
