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
tools/build_release.sh --ref v0.9.0 --expect tools/release/published.sha256  # fail unless it gives the published hashes
```

- **Committed files only.** It takes the files from the commit (`git archive`), never the working tree, so local changes or untracked files can't get in.
- **Same bytes every time, on any machine.** Entries are sorted by path, every entry gets the commit's own time and the same permissions, and the compression is pinned. The same commit gives byte-identical zips; the script prints each zip's SHA-256.
- **A pinned compressor.** The system's zlib is not used to compress: its output depends on its build, and zlib-ng (which some systems ship as their zlib) compresses the same file to different (equally valid) bytes from classic zlib. `tools/release/zlib_deflate.py`, a pure-Python port of classic zlib's level-9 deflate, compresses every entry instead, so the bytes are classic zlib's wherever the script runs. Each zip is read back with the system's zlib and checked against the committed files. It needs only Python 3; a build takes a few seconds.
- **Checked contents.** It refuses to build when `addons/bustle/VERSION` and `addons/bustle_wyrd/VERSION` disagree. It fails if a zip holds anything but its addon folder and `LICENSE`.

CI checks on every pull request that the build works and is reproducible:

- `tools/build_release.sh --check --list` builds twice and compares the bytes.
- `tools/test_build_release.sh` runs on Linux and Windows:
  - it compares the pinned compressor with the system's zlib, byte for byte, on every tracked file and on edge cases (on Linux, where the runner's zlib is classic; `--require-classic` makes a different zlib an error there, not a skip);
  - it rebuilds v0.9.0 and fails unless both zips match `tools/release/published.sha256`;
  - it checks that a wrong expected hash fails the build.

The published hashes of each release go in `tools/release/published.sha256` (one `<sha256>  <zip name>` line per zip).

## Before the tag (in a pull request)

1. **CI is green on `main`:** `test`, `test-windows` and `test-core-only`.
2. **Versions are bumped** in `addons/bustle/plugin.cfg`, `addons/bustle/VERSION` and `BustleInfo.VERSION`, and in `addons/bustle_wyrd/plugin.cfg` and `addons/bustle_wyrd/VERSION`. `tests/core/test_versions_agree.gd` checks that all five agree, and `tests/core/test_info.gd` pins the version's parts.
3. **`CHANGELOG.md` is updated:** `[Unreleased]` moves into a dated section for the version, with a "Breaking changes since" list (or "None"), and an empty `[Unreleased]` is left at the top. Release notes are drafted in `docs/release-notes/<version>.md`.
4. **The API docs are regenerated** (`tools/gen_api_docs.sh`), and the public API manifest is current (`tools/public_api.sh --write`). Every deprecation and removal follows [public-api/VERSIONING.md](public-api/VERSIONING.md), with its entry in `public-api/deprecations.json`.
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
9. Add the two zips' SHA-256 lines to `tools/release/published.sha256` in a pull request, so CI keeps checking that the release can be rebuilt byte for byte.

A project that vendors Bustle pins the tag and its commit, so a tag must never move once pushed.
