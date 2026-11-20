# Release checklist

How to cut a Bustle release, for example `v0.1.0`. **The maintainer creates the tag and the GitHub release.** Contributors and agents prepare everything up to step 5 in a pull request.

A release has **three zips**:

| Zip | Contents | For |
| --- | --- | --- |
| `bustle-<version>.zip` | `addons/bustle/` and `LICENSE` | every project |
| `bustle-wyrd-bridge-<version>.zip` | `addons/bustle_wyrd/` and `LICENSE` | projects that also use Wyrd (optional) |
| `bustle-example-<version>.zip` | one folder, `bustle-example-<version>/`: the example project (`examples/village/`) with `addons/bustle/` and `LICENSE` in it | trying Bustle: unzip, open `project.godot` in Godot 4.7.x, press Play |

Neither addon zip contains `addons/wyrd/` (a test-only copy), `addons/gut/`, `demo/`, `examples/`, `tests/`, `docs/`, `tools/` or the dev `project.godot`.

The example zip's `addons/bustle/` and `LICENSE` are byte for byte the addon zip's entries, under the example's folder. It leaves out the example's `.gitignore` (which ignores `addons/` in the repository, where the addon isn't copied in) and, like the addon zips, everything else in the repository. A commit without `examples/village/` (v0.9.0 and earlier) builds no example zip.

Each addon folder also carries its own `LICENSE` (an exact copy of the root one) and a short `README.md` (what the addon is, the Godot version, the license and a link to the docs), so a project that copies only the folder keeps them. From the first release after 0.9.0, each zip therefore holds the license twice: at the top and inside the folder. `tools/check_license_copies.sh` fails when a copy drifts from the root `LICENSE` or a folder's README is missing, and CI runs it with its self-test. **If the root `LICENSE` changes** (a new copyright year, say), copy it into both folders in the same pull request:

```bash
cp LICENSE addons/bustle/LICENSE && cp LICENSE addons/bustle_wyrd/LICENSE
tools/check_license_copies.sh
```

## Building the zips

`tools/build_release.sh` builds the zips the same way every time:

```bash
tools/build_release.sh                # from HEAD, into build/release/ (ignored by git)
tools/build_release.sh --ref v0.9.0   # from a tag or any commit
tools/build_release.sh --check --list # build twice, fail unless byte-identical, and list each zip
tools/build_release.sh --ref v0.9.0 --expect tools/release/published.sha256  # fail unless it gives the published hashes
```

- **Committed files only.** It takes the files from the commit, never the working tree, so local changes or untracked files can't get in: the addon zips through `git archive`, and the example zip from the commit's files directly (`git ls-tree` and `git cat-file`), since `.gitattributes` keeps `examples/` out of archives. `tools/release/write_zip.py` writes every zip the same way.
- **Same bytes every time, on any machine.** Entries are sorted by path, every entry gets the commit's own time and the same permissions, and the compression is pinned. The same commit gives byte-identical zips; the script prints each zip's SHA-256.
- **A pinned compressor.** The system's zlib is not used to compress: its output depends on its build, and zlib-ng (which some systems ship as their zlib) compresses the same file to different (equally valid) bytes from classic zlib. `tools/release/zlib_deflate.py`, a pure-Python port of classic zlib's level-9 deflate, compresses every entry instead, so the bytes are classic zlib's wherever the script runs. Each zip is read back with the system's zlib and checked against the committed files. It needs only Python 3; a build takes a few seconds.
- **Checked contents.** It refuses to build when `addons/bustle/VERSION` and `addons/bustle_wyrd/VERSION` disagree. It fails if an addon zip holds anything but its addon folder and `LICENSE`, or if the example zip holds anything but the example's committed files (but its `.gitignore`) and the addon zip's entries, all under its folder, or if its addon differs from the addon zip's.

CI checks on every pull request that the build works and is reproducible:

- `tools/build_release.sh --check --list` builds twice and compares the bytes.
- `tools/test_build_release.sh` runs on Linux and Windows:
  - it compares the pinned compressor with the system's zlib, byte for byte, on every tracked file and on edge cases (on Linux, where the runner's zlib is classic; `--require-classic` makes a different zlib an error there, not a skip);
  - it rebuilds v0.9.0 and fails unless both zips match `tools/release/published.sha256`;
  - it checks that a wrong expected hash fails the build.
- `tools/test_example_zip.sh` runs on Linux and Windows: it builds the zips twice (byte-identical, the example zip included), unpacks the example zip into a fresh folder, and loads that project headless with `tools/example.sh --check --project`: the import, its two-day check, the main scene for 300 frames and the editor, with no error or warning.

The published hashes of each release go in `tools/release/published.sha256` (one `<sha256>  <zip name>` line per zip). `--expect` needs the two addon zips listed, and checks the example zip's hash when it's listed (v0.9.0 had no example zip).

## The source archive

GitHub's "Download ZIP" and the archive of a commit are a third way to get Bustle, and the one the Godot Asset Library installs from: it downloads the archive of the commit the listing names, not a release zip. So the release zips alone don't cover it. The `export-ignore` rules in `.gitattributes` leave only these in a source archive:

- `addons/bustle/` and `addons/bustle_wyrd/`, each with its own `LICENSE` and `README.md`;
- `LICENSE` and `README.md`.

Everything else stays in the repository but out of the archive: `addons/wyrd/` (test-only), `addons/gut/`, `demo/`, `examples/`, `tests/`, `docs/`, `tools/`, `bench/`, the dev `project.godot` and the repository's own files. The rules ignore everything first and then let the four paths back in, so a new top-level file stays out until a rule names it.

The release zips are built from the same commit with `git archive` too, and the rules leave their paths alone, so the zips don't change: v0.9.0, tagged before the rules, still gives its published hashes. `tools/check_wyrd_pin.sh` reads the vendored Wyrd from the commit's files instead of an archive, since the rules keep it out of archives.

```bash
tools/check_source_archive.sh                # HEAD's archive holds only the four paths, and all of them,
                                             # with each plugin folder's plugin.cfg, LICENSE and README.md
tools/check_source_archive.sh --load         # also open it as a fresh project, both plugins on and no Wyrd
tools/test_check_source_archive.sh --load    # self-test: HEAD passes; v0.9.0 and a too-wide rule fail
```

CI runs the self-test with `--load` on Linux: the archive's addons must load in a fresh project's editor with no errors or warnings, the bridge included, since a user may install it without Wyrd.

## The Asset Library listing

The listing text is drafted in [asset-library/listing.md](asset-library/listing.md), one section per field of the submission form. **Submitting is a separate step that needs the maintainer's go-ahead;** a pull request only keeps the draft current.

- **The icon** is `docs/asset-library/icon.svg`, made in this repository and MIT licensed like the rest. The Asset Library needs a direct link to a square PNG or JPEG of at least 128 × 128 pixels, so its 256 × 256 PNG render, `icon.png`, is committed next to it. After changing the SVG, render the PNG again and commit both; CI fails when they differ:

  ```bash
  godot --headless --path . -s res://tools/asset_library/render_icon.gd             # write icon.png
  godot --headless --path . -s res://tools/asset_library/render_icon.gd -- --check  # fail unless it matches
  ```

  `plugin.cfg` has no icon setting in Godot 4 (its keys are the name, description, author, version and script), so the icon is referenced only by the listing. The folder holds a `.gdignore`, so Godot doesn't import the icon into the dev project.

- **Submitting or updating the entry** (maintainer, after the release's tag and zips, steps 6 to 9):
  1. Check the archive of the tag: `tools/check_source_archive.sh --ref vX.Y.Z --load`.
  2. Fill in the *at submission* fields of the listing: the version, the tag's full commit hash as the download commit, and the icon URL pinned to that commit.
  3. Submit, or edit the existing entry, on the Asset Library with the listing's text. One entry covers one Godot minor version.

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

8. Create the GitHub release from the tag. Attach the three zips from `build/release/`, and use the release notes (or the changelog section) as its text.
9. Add the three zips' SHA-256 lines to `tools/release/published.sha256` in a pull request, so CI keeps checking that the release can be rebuilt byte for byte.

A project that vendors Bustle pins the tag and its commit, so a tag must never move once pushed.
