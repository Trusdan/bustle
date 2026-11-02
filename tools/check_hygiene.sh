#!/usr/bin/env bash
# Fails if a line added in the given git range contains a term from the deny-list.
#   HYGIENE_TERMS="one term per line" tools/check_hygiene.sh <range>
# Terms are fixed strings, matched case-insensitively. Vendored folders (addons/gut, addons/wyrd)
# are skipped. It never prints the terms or the matching lines, only a pass or fail message.
# An unset or empty term list skips the check with a warning (exit 0).
set -euo pipefail

range="${1:-}"
if [[ -z "$range" ]]; then
	echo "usage: HYGIENE_TERMS=... tools/check_hygiene.sh <range>" >&2
	exit 2
fi
if [[ -z "${HYGIENE_TERMS:-}" ]]; then
	echo "::warning::The hygiene term list is unset; skipping the content-hygiene check."
	exit 0
fi

umask 077
terms_file="$(mktemp)"
added_file="$(mktemp)"
trap 'rm -f "$terms_file" "$added_file"' EXIT

# Trim whitespace and drop empty lines. Never echo the terms.
while IFS= read -r line || [[ -n "$line" ]]; do
	trimmed="${line#"${line%%[![:space:]]*}"}"
	trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
	if [[ -n "$trimmed" ]]; then
		printf '%s\n' "$trimmed" >> "$terms_file"
	fi
done <<< "$HYGIENE_TERMS"

if [[ ! -s "$terms_file" ]]; then
	echo "::warning::The hygiene term list is empty; skipping the content-hygiene check."
	exit 0
fi

# Added lines and new file paths only, so removing a term never fails the check.
git diff --no-color --unified=0 "$range" -- . ':(exclude)addons/gut' ':(exclude)addons/wyrd' \
	| grep -E '^\+' > "$added_file" || true

if grep -F -i -q -f "$terms_file" "$added_file"; then
	echo "::error::Content hygiene failed: the diff adds a term from the deny-list."
	exit 1
fi
echo "Content hygiene passed."
