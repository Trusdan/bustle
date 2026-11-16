#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# Self-test for reproducible release zips (tools/build_release.sh):
#   1. the pinned compressor matches classic zlib byte for byte on every tracked file and on edge
#      cases, and the system zlib reads everything it writes (tools/release/test_zlib_deflate.py);
#   2. building v0.9.0 gives the published hashes in tools/release/published.sha256, whatever this
#      machine's zlib is;
#   3. a build whose hash isn't the expected one fails (a wrong hash in a scratch expect file).
#   tools/test_build_release.sh [--require-classic]
#     --require-classic  fail, rather than skip the byte comparison, when the system zlib isn't
#                        classic zlib (CI's Linux runner has classic zlib)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python="$(command -v python3 || command -v python || true)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0

echo "1. The pinned compressor against the system zlib:"
"$python" tools/release/test_zlib_deflate.py "$@" || fail=1

echo "2. v0.9.0 reproduces its published hashes:"
if ! git rev-parse --verify -q "v0.9.0^{commit}" >/dev/null; then
	echo "FAIL: the v0.9.0 tag isn't here (fetch tags first)"
	fail=1
elif ! tools/build_release.sh --ref v0.9.0 --out "$work/ok" --expect tools/release/published.sha256; then
	echo "FAIL: v0.9.0 doesn't reproduce its published hashes"
	fail=1
fi

echo "3. A wrong expected hash fails:"
sed 's/^9/0/' tools/release/published.sha256 > "$work/wrong.sha256"
set +e
out="$(tools/build_release.sh --ref v0.9.0 --out "$work/bad" --expect "$work/wrong.sha256" 2>&1)"
code=$?
set -e
if [[ $code -eq 0 ]] || ! grep -q "does not reproduce it" <<< "$out"; then
	echo "FAIL: a wrong expected hash didn't fail the build (exit $code)"
	fail=1
else
	grep "does not reproduce it" <<< "$out"
	echo "failed as it should (exit $code)"
fi

if [[ $fail -ne 0 ]]; then
	exit 1
fi
echo "Reproducible release self-test passed."
