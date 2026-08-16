import std/unittest
import files/ignore

proc m(): IgnoreMatcher =
  newIgnoreMatcher()

suite "gitignore matcher":
  test "basename wildcard":
    var matcher = m()
    matcher.addRule("/repo", "*.log")
    check matcher.isIgnored("/repo/x.log", false)
    check matcher.isIgnored("/repo/a/b/deep.log", false)
    check not matcher.isIgnored("/repo/a/b/deep.txt", false)

  test "negation re-includes":
    var matcher = m()
    matcher.addRule("/repo", "*.log")
    matcher.addRule("/repo", "!important.log")
    check not matcher.isIgnored("/repo/important.log", false)
    check matcher.isIgnored("/repo/other.log", false)

  test "negation only wins when last":
    var matcher = m()
    matcher.addRule("/repo", "!important.log")
    matcher.addRule("/repo", "*.log")
    check matcher.isIgnored("/repo/important.log", false)

  test "dir-only pattern":
    var matcher = m()
    matcher.addRule("/repo", "build/")
    check matcher.isIgnored("/repo/build", true)
    check matcher.isIgnored("/repo/build/x", false)
    check matcher.isIgnored("/repo/build/x", true)
    check matcher.isIgnored("/repo/a/build", true)
    check matcher.isIgnored("/repo/a/build/x.txt", true)
    check not matcher.isIgnored("/repo/a/buildx", true)

  test "dir-only does not match a file":
    var matcher = m()
    matcher.addRule("/repo", "dir/")
    check not matcher.isIgnored("/repo/dir", false)

  test "anchored pattern":
    var matcher = m()
    matcher.addRule("/repo", "/root.log")
    check matcher.isIgnored("/repo/root.log", false)
    check not matcher.isIgnored("/repo/a/root.log", false)

  test "middle-slash anchors":
    var matcher = m()
    matcher.addRule("/repo", "foo/bar")
    check matcher.isIgnored("/repo/foo/bar", false)
    check matcher.isIgnored("/repo/foo/bar", true)
    check not matcher.isIgnored("/repo/x/foo/bar", false)

  test "no-slash matches any depth":
    var matcher = m()
    matcher.addRule("/repo", "node_modules")
    check matcher.isIgnored("/repo/node_modules", true)
    check matcher.isIgnored("/repo/node_modules/pkg/index.js", false)
    check matcher.isIgnored("/repo/a/node_modules/pkg/index.js", false)

  test "double-star prefix":
    var matcher = m()
    matcher.addRule("/repo", "**/node_modules/")
    check matcher.isIgnored("/repo/node_modules", true)
    check matcher.isIgnored("/repo/node_modules/pkg", true)
    check matcher.isIgnored("/repo/a/node_modules/pkg", true)

  test "a/** matches inside but not itself":
    var matcher = m()
    matcher.addRule("/repo", "a/**")
    check matcher.isIgnored("/repo/a/x", false)
    check matcher.isIgnored("/repo/a/x/y", false)
    check not matcher.isIgnored("/repo/a", true)

  test "a/**/b":
    var matcher = m()
    matcher.addRule("/repo", "a/**/b")
    check matcher.isIgnored("/repo/a/b", false)
    check matcher.isIgnored("/repo/a/x/b", false)
    check matcher.isIgnored("/repo/a/x/y/b", false)
    check not matcher.isIgnored("/repo/b", false)

  test "question mark":
    var matcher = m()
    matcher.addRule("/repo", "file?.txt")
    check matcher.isIgnored("/repo/file1.txt", false)
    check not matcher.isIgnored("/repo/file12.txt", false)

  test "character class":
    var matcher = m()
    matcher.addRule("/repo", "file[0-9].txt")
    check matcher.isIgnored("/repo/file3.txt", false)
    check not matcher.isIgnored("/repo/filex.txt", false)

  test "escaped hash is literal":
    var matcher = m()
    matcher.addRule("/repo", "\\#foo")
    check matcher.isIgnored("/repo/#foo", false)
    check not matcher.isIgnored("/repo/foo", false)

  test "comment and blank lines ignored":
    var matcher = m()
    matcher.addRule("/repo", "# comment")
    matcher.addRule("/repo", "")
    matcher.addRule("/repo", "  ")
    check not matcher.isIgnored("/repo/anything", false)

  test "rules scoped to base directory":
    var matcher = m()
    matcher.addRule("/repo/sub", "*.log")
    check matcher.isIgnored("/repo/sub/x.log", false)
    check not matcher.isIgnored("/repo/other/x.log", false)

  test "last match wins across negation order":
    var matcher = m()
    matcher.addRule("/repo", "*.tmp")
    matcher.addRule("/repo", "!keep.tmp")
    matcher.addRule("/repo", "*.tmp")
    check matcher.isIgnored("/repo/keep.tmp", false)

  test "extra rule ignores negate semantics":
    var matcher = m()
    matcher.addRuleExtra("/repo", "!foo")
    check matcher.isIgnored("/repo/foo", false)
    check matcher.isIgnored("/repo/foo", true)

  test "star matches within segment only":
    var matcher = m()
    matcher.addRule("/repo", "a*b")
    check matcher.isIgnored("/repo/axb", false)
    check not matcher.isIgnored("/repo/a/x/b", false)
    check not matcher.isIgnored("/repo/a/b", false)

  test "trailing slash after strip":
    var matcher = m()
    matcher.addRule("/repo", "cache/ ")
    check matcher.isIgnored("/repo/cache", true)
