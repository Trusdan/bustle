# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
"""Self-test for zlib_deflate.py, run by tools/test_build_release.sh.

Compresses every file tracked in the repository, plus edge cases (empty, tiny, long runs,
incompressible data, and inputs past 64 KiB that slide the window), and checks that:
- the system's zlib decompresses each one back to the input, whatever zlib build it is;
- when the system's zlib is classic zlib, the bytes are exactly the ones it writes at level 9.
  With --require-classic, a system zlib that isn't classic is an error rather than a skip.
"""
import hashlib
import os
import subprocess
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zlib_deflate  # noqa: E402


def system_deflate(data):
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    return compressor.compress(data) + compressor.flush()


def corpus(root):
    names = subprocess.check_output(["git", "-C", root, "ls-files", "-z"]).decode().split("\0")
    out = []
    for name in sorted(n for n in names if n):
        path = os.path.join(root, name)
        if os.path.isfile(path):
            with open(path, "rb") as handle:
                out.append((name, handle.read()))
    noise = b"".join(hashlib.sha256(i.to_bytes(4, "little")).digest() for i in range(3000))
    joined = b"".join(data for _, data in out[:300])
    out += [
        ("<empty>", b""), ("<one byte>", b"a"), ("<two bytes>", b"ab"), ("<three bytes>", b"abc"),
        ("<a run of 100000>", b"a" * 100000), ("<96000 bytes of noise>", noise),
        ("<300 files joined, %d bytes>" % len(joined), joined),
    ]
    return out


def main():
    root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"]).decode().strip()
    runtime = zlib.ZLIB_RUNTIME_VERSION
    classic = "ng" not in runtime.lower()
    if "--require-classic" in sys.argv and not classic:
        sys.exit("the system zlib is %s, not classic zlib, so the byte comparison can't run" % runtime)
    failures = []
    total = 0
    cases = corpus(root)
    for name, data in cases:
        total += len(data)
        ours = zlib_deflate.compress(data)
        if zlib.decompress(ours, -15) != data:
            failures.append("%s: does not decompress to the input" % name)
        elif classic and ours != system_deflate(data):
            failures.append("%s: differs from classic zlib %s" % (name, runtime))
    print("zlib_deflate: %d inputs, %d bytes; system zlib %s: %s" % (
        len(cases), total, runtime,
        "every one byte-identical to it" if classic and not failures else
        "byte comparison skipped (not classic zlib), every one decompresses" if not failures else "FAILED"))
    if failures:
        sys.exit("\n".join(failures[:20]))


if __name__ == "__main__":
    main()
