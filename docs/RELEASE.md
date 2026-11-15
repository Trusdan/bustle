# Release checklist

How to cut a Bustle release, for example `v0.1.0`. **The maintainer creates the tag and the GitHub release.** Contributors and agents prepare everything up to step 5 in a pull request.

A release has **two zips**:

| Zip | Contents | For |
| --- | --- | --- |
| `bustle-<version>.zip` | `addons/bustle/` and `LICENSE` | every project |
| `bustle-wyrd-bridge-<version>.zip` | `addons/bustle_wyrd/` and `LICENSE` | projects that also use Wyrd (optional) |

Neither zip contains `addons/wyrd/` (a test-only copy), `addons/gut/`, `demo/`, `tests/`, `docs/`, `tools/` or the dev `project.godot`.

## Building the zips

`tools/build_release.sh` builds both zips the same way every time:

```bash
tools/build_release.sh                # from HEAD, into build/release/ (ignored by git)
tools/build_release.sh --ref v0.9.0   # from a tag or any commit
tools/build_release.sh --check --list # build twice, fail unless byte-identical, and list each zip
```

- **Committed files only.** It takes the files from the commit (`git archive`), never the working tree, so local changes or untracked files can't get in.
- **Same bytes every time.** Entries are sorted by path, every entry gets the commit's own time and the same permissions, and the compression is fixed. The same commit gives byte-identical zips; the script prints each zip's SHA-256.
- **Checked contents.** It refuses to build when `addons/bustle/VERSION` and `addons/bustle_wyrd/VERSION` disagree. It fails if a zip holds anything but its addon folder and `LICENSE`.

CI runs `tools/build_release.sh --check --list` on every pull request, so a change that breaks the build or its reproducibility shows up before release.

## Before the tag (in a pull request)

1. **CI is green on `main`:** `test`, `test-windows` and `test-core-only`.
2. **Versions are bumped** in `addons/bustle/plugin.cfg`, `addons/bustle/VERSION` and `BustleInfo.VERSION`, and in `addons/bustle_wyrd/plugin.cfg` and `addons/bustle_wyrd/VERSION`. `tests/core/test_versions_agree.gd` checks that all five agree, and `tests/core/test_info.gd` pins the version's parts.
3. **`CHANGELOG.md` is updated:** `[Unreleased]` moves into a dated section for the version, with a "Breaking changes since" list (or "None"), and an empty `[Unreleased]` is left at the top. Release notes are drafted in `docs/release-notes/<version>.md`.
4. **The API docs are regenerated** (`tools/gen_api_docs.sh`).
5. **The pull request is merged** into `main`, with CI green on the merge commit.

## The tag and the release (maintainer only)

6. Tag the merge commit on `main`:

   ```bash
   git tag -a v0.1.0 -m "Bustle 0.1.0"
   git push origin v0.1.0
   ```

7. Build the zips from the tag and check they're reproducible:

   ```bash
   tools/build_release.sh --ref v0.1.0 --check --list
   ```

8. Create the GitHub release from the tag. Attach the two zips from `build/release/`, and use the release notes (or the changelog section) as its text.

A project that vendors Bustle pins the tag and its commit, so a tag must never move once pushed.
