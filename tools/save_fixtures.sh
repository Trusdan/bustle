#!/usr/bin/env bash
# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
# Golden save fixtures (docs/saves.md): what each released version's export_state() wrote.
#   tools/save_fixtures.sh --tag v0.9.0   regenerate tests/save_fixtures/v0.9.0/ from that tag
#   tools/save_fixtures.sh --check        regenerate every committed tag's fixtures into a temp dir
#                                         and fail on any difference
# Each run checks out the tag in a temporary git worktree outside the repo, copies in
# tools/save_fixtures/ from this checkout, imports it and runs the generator there, so the
# fixtures come from the tagged code. It never creates a tag. Needs the pinned Godot
# (tools/pins.env) on PATH as `godot`.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
fixtures=tests/save_fixtures

mode=""
tag=""
case "${1:-}" in
	--tag) mode=tag; tag="${2:?--tag needs a tag, such as v0.9.0}" ;;
	--check) mode=check ;;
	*) echo "usage: tools/save_fixtures.sh --tag <tag> | --check" >&2; exit 2 ;;
esac
if ! command -v godot >/dev/null 2>&1; then
	echo "godot is not on PATH. Install the version in tools/pins.env." >&2
	exit 1
fi

work="$(mktemp -d)"
trees=()
cleanup() {
	for tree in "${trees[@]}"; do git worktree remove --force "$tree" >/dev/null 2>&1 || true; done
	rm -rf "$work"
}
trap cleanup EXIT

# generate <tag> <out dir>
generate() {
	local t="$1" out="$2" tree="$work/tree-$1"
	git rev-parse --verify --quiet "refs/tags/$t^{commit}" >/dev/null || { echo "no tag $t" >&2; return 1; }
	local commit
	commit="$(git rev-parse "refs/tags/$t^{commit}")"
	git worktree add --detach --quiet "$tree" "$commit"
	trees+=("$tree")
	mkdir -p "$tree/tools/save_fixtures" "$out"
	cp tools/save_fixtures/save_builder.gd tools/save_fixtures/generate_save_fixtures.gd "$tree/tools/save_fixtures/"
	godot --headless --path "$tree" --import >/dev/null 2>&1 || true
	if ! godot --headless --path "$tree" -s res://tools/save_fixtures/generate_save_fixtures.gd -- \
			--out="$out" --tag="$t" --commit="$commit" >"$work/$t.log" 2>&1 \
			|| grep -E -q 'SCRIPT ERROR|Parse Error|^ERROR' "$work/$t.log"; then
		cat "$work/$t.log" >&2
		echo "The generator failed on $t." >&2
		return 1
	fi
	grep '^wrote' "$work/$t.log"
}

if [[ "$mode" == tag ]]; then
	rm -rf "${fixtures:?}/$tag"
	generate "$tag" "$root/$fixtures/$tag"
	exit 0
fi

fail=0
for dir in "$fixtures"/*/; do
	t="$(basename "$dir")"
	generate "$t" "$work/out/$t"
	if diff -r "$dir" "$work/out/$t" >"$work/$t.diff"; then
		echo "$t: $(ls "$dir" | wc -l | tr -d ' ') files match"
	else
		cat "$work/$t.diff"
		echo "$t: the committed fixtures differ from what the tag writes. Run tools/save_fixtures.sh --tag $t." >&2
		fail=1
	fi
done
exit "$fail"
