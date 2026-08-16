import std/posix

type
  ObjKind* = enum okUnknown, okDir, okFile, okLink
  BulkEntry* = object
    name*: string
    kind*: ObjKind

const
  ATTR_CMN_RETURNED_ATTRS = 0x80000000'u32
  ATTR_CMN_NAME = 0x00000001'u32
  ATTR_CMN_OBJTYPE = 0x00000008'u32
  ATTR_BIT_MAP_COUNT = 5'u16
  FSOPT_PACK_INVAL_ATTRS = 0x00000008'u32
  VREG = 1'u32
  VDIR = 2'u32
  VLNK = 5'u32

type
  AttrList = object
    bitmapcount: uint16
    reserved: uint16
    commonattr: uint32
    volattr: uint32
    dirattr: uint32
    fileattr: uint32
    forkattr: uint32

proc getattrlistbulk(fd: cint, alist: pointer, buf: pointer,
                     bufsize: csize_t, opts: uint64): cint {.importc.}

var gBuf: array[128 * 1024, byte]

proc rd32(b: ptr UncheckedArray[byte], off: int): uint32 =
  uint32(b[off]) or (uint32(b[off + 1]) shl 8) or
  (uint32(b[off + 2]) shl 16) or (uint32(b[off + 3]) shl 24)

proc listDirBulk*(dir: string, outEntries: var seq[BulkEntry]): bool =
  ## Enumerate `dir` via getattrlistbulk (Darwin). Returns false on failure so
  ## callers can fall back to walkDir. Appends (name, kind) to `outEntries`.
  let fd = posix.open(dir.cstring, O_RDONLY)
  if fd < 0: return false
  defer: discard posix.close(fd)
  var alist = AttrList(
    bitmapcount: ATTR_BIT_MAP_COUNT,
    reserved: 0,
    commonattr: ATTR_CMN_RETURNED_ATTRS or ATTR_CMN_NAME or
                ATTR_CMN_OBJTYPE,
    volattr: 0,
    dirattr: 0,
    fileattr: 0,
    forkattr: 0
  )
  let b = cast[ptr UncheckedArray[byte]](addr gBuf[0])
  while true:
    let n = getattrlistbulk(fd, addr alist, addr gBuf[0],
                            csize_t(gBuf.len), uint64(FSOPT_PACK_INVAL_ATTRS))
    if n == 0: break
    if n < 0: return false
    var off = 0
    for i in 0 ..< int(n):
      let entryLen = int(rd32(b, off))
      if entryLen < 36 or off + entryLen > gBuf.len: break
      let nameOff = int(rd32(b, off + 24))
      let nameLen = int(rd32(b, off + 28))
      let objtype = rd32(b, off + 32)
      var kind: ObjKind
      case objtype
      of VDIR: kind = okDir
      of VLNK: kind = okLink
      of VREG: kind = okFile
      else: kind = okUnknown
      let nameBase = off + 24 + nameOff
      if nameBase < off or nameBase + nameLen > off + entryLen:
        off += entryLen
        continue
      var n = nameLen
      while n > 0 and b[nameBase + n - 1] == 0: dec n
      if n == 0:
        off += entryLen
        continue
      var e = BulkEntry(kind: kind)
      e.name = newString(n)
      copyMem(addr e.name[0], addr b[nameBase], n)
      outEntries.add e
      off += entryLen
  true
