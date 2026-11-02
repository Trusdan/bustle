#!/usr/bin/env bash
# Self-test for tools/check_hygiene.sh with made-up terms in a scratch repository: a clean change
# passes, a change that adds a term fails, removing a term passes, vendored folders are skipped,
# and no output ever contains the term.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/check_hygiene.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"
git init -q -b main .
git config user.email test@example.invalid
git config user.name test
echo "hello" > a.txt
git add -A && git commit -q -m base

secret="Zqxwvforbidden"
terms=$'\n  '"$secret"$'  \nanotherzzterm\n'
fail=0

expect() {
	local want="$1" label="$2" range="$3"
	local out code
	set +e
	out="$(HYGIENE_TERMS="$terms" "$script" "$range" 2>&1)"
	code=$?
	set -e
	if [[ "$code" -ne "$want" ]]; then
		echo "FAIL: ${label}: exit ${code}, wanted ${want}"
		fail=1
	fi
	if grep -q -i -F "$secret" <<< "$out"; then
		echo "FAIL: ${label}: the output shows the term"
		fail=1
	fi
}

echo "plain words" >> a.txt
git commit -q -am clean
expect 0 "a clean change passes" "HEAD~1..HEAD"

echo "this mentions ZQXWVFORBIDDEN loudly" >> a.txt
git commit -q -am dirty
expect 1 "an added term fails (case-insensitive)" "HEAD~1..HEAD"

git revert --no-edit HEAD >/dev/null
expect 0 "removing a term passes" "HEAD~1..HEAD"

mkdir -p addons/gut
echo "$secret" > addons/gut/x.txt
git add -A && git commit -q -m vendored
expect 0 "vendored folders are skipped" "HEAD~1..HEAD"

set +e
out="$(HYGIENE_TERMS="" "$script" "HEAD~1..HEAD" 2>&1)"
code=$?
set -e
if [[ "$code" -ne 0 ]] || ! grep -q "skipping" <<< "$out"; then
	echo "FAIL: an empty list should warn and skip"
	fail=1
fi

if [[ "$fail" -ne 0 ]]; then
	exit 1
fi
echo "check_hygiene.sh self-test passed."
