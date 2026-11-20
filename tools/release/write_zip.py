# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
"""Writes one release zip the same way every time (tools/build_release.sh, docs/RELEASE.md).

Entries are sorted by path, every entry gets the given time (the commit's) and the same
permissions, and every entry is compressed by tools/release/zlib_deflate.py, a pure-Python port of
classic zlib's level-9 deflate, instead of the system's zlib, whose output depends on its build.
The zip is then read back with the system's zlib and every entry checked.

    write_zip.py ZIP EPOCH --tar
        the files of the tar on standard input (git archive's output), at their own paths
    write_zip.py ZIP EPOCH --commit COMMIT --map SRC DEST [--map SRC DEST ...] [--skip PATH ...]
        the files under each SRC in the commit, read from its blobs (git ls-tree and git cat-file,
        so .gitattributes export-ignore rules don't apply), each written under DEST instead of SRC;
        a file listed with --skip is left out
"""

import io
import subprocess
import sys
import tarfile
import time
import zipfile

sys.dont_write_bytecode = True  # no __pycache__ in the repository
import zlib_deflate  # noqa: E402  (next to this file)


def _pin_compressor():
    # Every deflated entry goes through the pure-Python compressor instead of the system zlib.
    if not hasattr(zipfile, "_get_compressor"):
        sys.exit("this Python's zipfile has no _get_compressor, so the compressor cannot be pinned")
    system_compressor = zipfile._get_compressor

    def pinned_compressor(compress_type, compresslevel=None):
        if compress_type == zipfile.ZIP_DEFLATED and compresslevel == 9:
            return zlib_deflate.Compressor()
        return system_compressor(compress_type, compresslevel)

    zipfile._get_compressor = pinned_compressor


def files_from_tar(stream):
    files = {}
    with tarfile.open(fileobj=io.BytesIO(stream.read())) as tar:
        for member in tar.getmembers():
            if member.isfile():
                files[member.name] = tar.extractfile(member).read()
    return files


def files_from_commit(commit, mapping, skip):
    sources = [src for src, _ in mapping]
    listed = subprocess.run(["git", "ls-tree", "-r", "-z", "--full-tree", commit, "--"] + sources,
                            check=True, capture_output=True).stdout
    blobs = []
    for entry in listed.split(b"\0"):
        if not entry:
            continue
        meta, path = entry.split(b"\t", 1)
        mode, kind, sha = meta.split(b" ")
        path = path.decode("utf-8")
        if path in skip:
            continue
        if kind != b"blob" or mode not in (b"100644", b"100755"):
            sys.exit("%s in %s is not a plain file (mode %s), which a release zip can't hold" % (path, commit, mode.decode()))
        blobs.append((path, sha))
    batch = subprocess.run(["git", "cat-file", "--batch"], check=True, capture_output=True,
                           input=b"".join(sha + b"\n" for _, sha in blobs)).stdout
    files = {}
    at = 0
    for path, sha in blobs:
        header_end = batch.index(b"\n", at)
        size = int(batch[at:header_end].split(b" ")[2])
        content = batch[header_end + 1:header_end + 1 + size]
        at = header_end + 1 + size + 1  # the blob, then a newline
        for src, dest in mapping:
            if path == src or path.startswith(src + "/"):
                files[dest + path[len(src):]] = content
                break
    return files


def write(zip_path, files, epoch):
    _pin_compressor()
    stamp = time.gmtime(max(epoch, 315532800))[:6]  # zip times start in 1980
    with zipfile.ZipFile(zip_path, "w") as out:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, date_time=stamp)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            out.writestr(info, files[name], compresslevel=9)
    # Read it back with the system zlib: every entry must decompress to the committed file.
    with zipfile.ZipFile(zip_path) as back:
        for name in sorted(files):
            if back.read(name) != files[name]:
                sys.exit("%s: %s does not read back as committed" % (zip_path, name))


def main(argv):
    zip_path, epoch, mode = argv[0], int(argv[1]), argv[2]
    if mode == "--tar":
        files = files_from_tar(sys.stdin.buffer)
    elif mode == "--commit":
        commit, rest = argv[3], argv[4:]
        mapping, skip = [], set()
        while rest:
            if rest[0] == "--map":
                mapping.append((rest[1], rest[2]))
                rest = rest[3:]
            elif rest[0] == "--skip":
                skip.add(rest[1])
                rest = rest[2:]
            else:
                sys.exit("unknown argument: %s" % rest[0])
        files = files_from_commit(commit, mapping, skip)
    else:
        sys.exit("unknown mode: %s" % mode)
    if not files:
        sys.exit("%s would be empty" % zip_path)
    write(zip_path, files, epoch)


if __name__ == "__main__":
    main(sys.argv[1:])
