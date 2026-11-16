#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# Self-test for tools/check_license_copies.sh on scratch copies of the files it reads: the real
# repository passes, and each kind of drift fails with a message naming the file to update.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/check_license_copies.sh"
repo="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0

# A fresh scratch root with copies of the real files.
scratch() {
	rm -rf "$work/root"
	mkdir -p "$work/root/addons/bustle" "$work/root/addons/bustle_wyrd"
	cp "$repo/LICENSE" "$work/root/LICENSE"
	for folder in addons/bustle addons/bustle_wyrd; do
		cp "$repo/$folder/LICENSE" "$repo/$folder/README.md" "$work/root/$folder/"
	done
}

expect() {
	local want="$1" label="$2" names="${3:-}"
	local out code
	set +e
	out="$("$script" "$work/root" 2>&1)"
	code=$?
	set -e
	if [[ "$code" -ne "$want" ]]; then
		echo "FAIL: ${label}: exit ${code}, wanted ${want}"
		fail=1
	fi
	if [[ -n "$names" ]] && ! grep -q -F "$names" <<< "$out"; then
		echo "FAIL: ${label}: the message doesn't name ${names}"
		fail=1
	fi
	echo "${label}: exit ${code}: ${out}"
}

scratch
expect 0 "the repository as it is passes"

scratch
sed -i 's/^Copyright (c) [0-9]*/Copyright (c) 2025/' "$work/root/addons/bustle/LICENSE"
expect 1 "an edited copy in addons/bustle fails" "addons/bustle/LICENSE"

scratch
printf '\n' >> "$work/root/addons/bustle_wyrd/LICENSE"
expect 1 "a copy with one extra line in addons/bustle_wyrd fails" "addons/bustle_wyrd/LICENSE"

scratch
sed -i 's/$/\r/' "$work/root/addons/bustle/LICENSE"
expect 1 "a copy with CRLF line endings fails" "addons/bustle/LICENSE"

scratch
rm "$work/root/addons/bustle_wyrd/LICENSE"
expect 1 "a missing copy fails" "addons/bustle_wyrd/LICENSE"

scratch
sed -i 's/^Copyright (c) [0-9]*/Copyright (c) 2025/' "$work/root/LICENSE"
expect 1 "a root LICENSE changed without its copies fails" "addons/bustle/LICENSE"

scratch
rm "$work/root/addons/bustle/README.md"
expect 1 "a missing plugin README fails" "addons/bustle/README.md"

if [[ $fail -ne 0 ]]; then
	exit 1
fi
echo "check_license_copies.sh self-test passed."
