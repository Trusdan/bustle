#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
#
# Checks the source archive of a commit: what GitHub's "Download ZIP" and the archive of a commit
# hold, which is what the Godot Asset Library installs from. The export-ignore rules in
# .gitattributes must leave only:
#   addons/bustle/, addons/bustle_wyrd/, LICENSE and README.md
# and all four must be there, each plugin folder with its plugin.cfg, LICENSE and README.md.
# Nothing else (tests, demo, docs, tools, the vendored Wyrd and GUT, the dev project.godot) may
# get in, and a new top-level file fails until a rule covers it.
#
#   tools/check_source_archive.sh [--ref REF] [--load]
#     --ref   the commit to check (default HEAD)
#     --load  also open the archive's files as a fresh project in the headless editor, with both
#             plugins enabled and no Wyrd, and fail on any ERROR or WARNING (needs godot on PATH)
set -euo pipefail
cd "$(dirname "$0")/.."

ref="HEAD"
load=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--ref) ref="$2"; shift 2 ;;
		--load) load=1; shift ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

commit="$(git rev-parse --verify "$ref^{commit}")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git archive --format=tar "$commit" | tar -x -C "$work"

files="$(cd "$work" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)"
extra="$(grep -v -E '^(LICENSE|README\.md|addons/bustle/.+|addons/bustle_wyrd/.+)$' <<< "$files" || true)"
if [[ -n "$extra" ]]; then
	echo "The source archive of $commit holds files outside the addons, LICENSE and README.md:" >&2
	head -n 10 <<< "$extra" | sed 's/^/    /' >&2
	echo "($(wc -l <<< "$extra") in all.) Add an export-ignore rule for them in .gitattributes." >&2
	exit 1
fi
for need in LICENSE README.md addons/bustle/{plugin.cfg,LICENSE,README.md} addons/bustle_wyrd/{plugin.cfg,LICENSE,README.md}; do
	if ! grep -q -x -F "$need" <<< "$files"; then
		echo "The source archive of $commit misses $need: an export-ignore rule in .gitattributes is too wide." >&2
		exit 1
	fi
done
echo "Source archive of $commit: $(wc -l <<< "$files") files, only the addons, LICENSE and README.md."

if [[ $load -eq 1 ]]; then
	cat > "$work/project.godot" <<-'EOF'
		config_version=5

		[application]

		config/name="Source archive check"

		[editor_plugins]

		enabled=PackedStringArray("res://addons/bustle/plugin.cfg", "res://addons/bustle_wyrd/plugin.cfg")
	EOF
	log="$work/editor.log"
	set +e
	godot --headless --editor --path "$work" --quit-after 120 > "$log" 2>&1
	code=$?
	set -e
	if [[ $code -ne 0 ]] || grep -q -E 'ERROR|WARNING' "$log"; then
		cat "$log" >&2
		echo "A fresh project with the source archive's addons logged an error or warning (editor exit $code)." >&2
		exit 1
	fi
	echo "A fresh project with both plugins enabled and no Wyrd loads in the editor with no errors or warnings."
fi
