# Release checklist

How to cut a Bustle release, for example `v0.1.0`. **The maintainer creates the tag and the GitHub release.** Contributors and agents prepare everything up to step 5 in a pull request.

A release has **two zips**:

| Zip | Contents | For |
| --- | --- | --- |
| `bustle-<version>.zip` | `addons/bustle/` and `LICENSE` | every project |
| `bustle-wyrd-bridge-<version>.zip` | `addons/bustle_wyrd/` and `LICENSE` | projects that also use Wyrd (optional) |

Neither zip contains `addons/wyrd/` (a test-only copy), `addons/gut/`, `demo/`, `tests/`, `docs/`, `tools/` or the dev `project.godot`.

## Before the tag (in a pull request)

1. **CI is green on `main`:** `test`, `test-windows` and `test-core-only`.
2. **Versions are bumped** in `addons/bustle/plugin.cfg`, `addons/bustle/VERSION` and `BustleInfo.VERSION` (a test checks they agree), and in `addons/bustle_wyrd/plugin.cfg` and `addons/bustle_wyrd/VERSION`.
3. **`CHANGELOG.md` is updated.**
4. **The API docs are regenerated** (`tools/gen_api_docs.sh`).
5. **The pull request is merged** into `main`, with CI green on the merge commit.

## The tag and the release (maintainer only)

6. Tag the merge commit on `main`:

   ```bash
   git tag -a v0.1.0 -m "Bustle 0.1.0"
   git push origin v0.1.0
   ```

7. Create the GitHub release from the tag with the two zips and the changelog section.

A project that vendors Bustle pins the tag and its commit, so a tag must never move once pushed.
