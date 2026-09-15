import std/[os, strutils]

switch("path", ".")

# Tests live in tests/ but import files/*; keep their binaries out of the tree.
if projectDir().endsWith("tests"):
  switch("outdir", projectDir() / ".." / "bin" / "tests")
