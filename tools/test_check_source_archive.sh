#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# Self-test for tools/check_source_archive.sh:
#   1. HEAD's source archive passes (with --load when given, as CI does);
#   2. v0.9.0, tagged before the export-ignore rules, fails and names a file that got in;
#   3. a rule that ignores a whole addon fails and names what's missing (a scratch commit in a
#      throwaway clone, so this repository is untouched).
#   tools/test_check_source_archive.sh [--load]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0

# expect_fail <case> <text the error must contain> <command...>
expect_fail() {
	local name="$1" text="$2"
	shift 2
	local out code
	set +e
	out="$("$@" 2>&1)"
	code=$?
	set -e
	if [[ $code -eq 0 ]] || ! grep -q -F "$text" <<< "$out"; then
		echo "FAIL: $name (exit $code)"
		echo "$out"
		fail=1
	else
		echo "ok: $name fails: $(grep -F "$text" <<< "$out" | head -n 1 | sed 's/^ *//')"
	fi
}

echo "1. HEAD's source archive:"
tools/check_source_archive.sh "$@" || fail=1

echo "2. v0.9.0, before the rules:"
if ! git rev-parse --verify -q "v0.9.0^{commit}" >/dev/null; then
	echo "FAIL: the v0.9.0 tag isn't here (fetch tags first)"
	fail=1
else
	expect_fail "v0.9.0" "holds files outside the addons" tools/check_source_archive.sh --ref v0.9.0
fi

echo "3. A rule that ignores an addon:"
git clone -q --no-local --no-checkout . "$work/repo"
git -C "$work/repo" checkout -q "$(git rev-parse HEAD)"
printf '/addons/bustle_wyrd export-ignore\n/addons/bustle_wyrd/** export-ignore\n' >> "$work/repo/.gitattributes"
git -C "$work/repo" -c user.name=test -c user.email=test@example.invalid commit -q -am "scratch"
expect_fail "ignoring addons/bustle_wyrd" "misses addons/bustle_wyrd/plugin.cfg" \
	"$work/repo/tools/check_source_archive.sh"

if [[ $fail -ne 0 ]]; then
	exit 1
fi
echo "Source archive self-test passed."
