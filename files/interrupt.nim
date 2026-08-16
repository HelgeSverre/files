import std/posix

proc onSignal(sig: cint) {.noconv.} =
  let msg = "files: interrupted\n"
  discard write(cint(2), unsafeAddr msg[0], msg.len)
  exitnow(130)

proc install*() =
  discard signal(SIGINT, onSignal)
  discard signal(SIGTERM, onSignal)
