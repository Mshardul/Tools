# MediaGrabber Phase 20: Repo split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MediaGrabber builds, tests, lints and dry-runs a release from its own repository `Mshardul/MediaGrabber`, with every address final.

**Architecture:** The history is filtered into a new local folder, all reference edits are made there before the first push, then keys, Pages and a dry run are set up on the new repository. Tools is cleaned up last.

**Tech Stack:** Tuist, Make, GitHub Actions, GitHub CLI (`gh`), Sparkle 2.7.1, shell, Python (stdlib script plus pytest).

**Spec:** `docs/superpowers/specs/2026-11-17-media-grabber-phase-20-repo-split-design.md`

## Global Constraints

- Shell variables, exported before any user task: `OLD="$HOME/Documents/Github/Tools"`, `NEW="$HOME/Documents/Github/MediaGrabber"`, `REPO=Mshardul/MediaGrabber`.
- Agent tasks run inside `$NEW`. Tools source files are never edited before Task 17; the only earlier touches are the Task 1 commit and the Task 11 build-output cleanup.
- Tag: `vX.Y.Z`. Bare `X.Y.Z` is the version everywhere else.
- Feed: `https://github.com/Mshardul/MediaGrabber/releases/latest/download/appcast.xml`.
- Runtime config: `https://raw.githubusercontent.com/Mshardul/MediaGrabber/main/config/player-clients.json`.
- Secret `SPARKLE_EDDSA_PRIVATE_KEY`, variable `MG_SPARKLE_PUBLIC_KEY` (build reads it as `TUIST_SPARKLE_PUBLIC_KEY`). `MG_SIGN_IDENTITY` is not set; signing stays ad hoc.
- Workflow dispatch inputs of `release.yml`: `version`, `dry_run`, `overwrite`.
- Build, test and run only through `make`. At most one `MediaGrabber.app` on the machine.
- Python only from `$NEW/.venv/bin/python`. System `python3` only creates the venv.
- Comments are single-line only, in every language and file type. No phase or ticket references in code or UI copy. Markdown prose is one paragraph per line.
- Each task ends on its gate and hands off. Tasks marked **You** need your accounts, keys or git.

## Review Focus

- A tag list where `v0.10.0` sits beside `v0.9.0` must resolve to `0.10.0`, not `0.9.0` (Task 4).
- Tags that are not release versions (`vfoo`, `v1.2`, `v1.2.3-rc1`, `media-grabber-v9.9.9`) must be ignored by the version lookup (Task 4).
- `make release-dry-run` and `make release-overwrite` with a missing or malformed `VERSION` must refuse before any workflow starts (Task 4).
- Re-running a release for a version already in the feed must replace its entry, not add a second one (Task 5).
- An empty or missing previous appcast must produce a valid feed with one item (Task 5).

---

### Task 1: Repository and filtered history (You)

**Files:** none in the repo; creates `$NEW`.

- [ ] **Step 1: Confirm the name is free**

Run: `gh repo view "$REPO" >/dev/null 2>&1 && echo TAKEN || echo free` Expected: `free`

- [ ] **Step 2: Create the empty repository**

Run: `gh repo create "$REPO" --public` Expected: prints `https://github.com/Mshardul/MediaGrabber`. No README, licence or gitignore is added.

- [ ] **Step 3: Filter a fresh clone of Tools into `$NEW`**

Filter a fresh clone, never the Tools checkout. Commit everything in `$OLD` first, because only committed files are carried.

```bash
test ! -e "$NEW"
git clone --no-local "$OLD" "$NEW"
cd "$NEW"
git filter-repo \
  --path apps/media-grabber/ \
  --path docs/superpowers/ \
  --path .github/workflows/media-grabber.yml \
  --path .github/workflows/media-grabber-release.yml \
  --path LICENSE \
  --path-rename apps/media-grabber/: \
  --path-rename .github/workflows/media-grabber.yml:.github/workflows/ci.yml \
  --path-rename .github/workflows/media-grabber-release.yml:.github/workflows/release.yml
git filter-repo --force --invert-paths \
  --path docs/superpowers/specs/2026-05-25-claude-usage-dashboard-design.md \
  --path docs/superpowers/plans/2026-05-25-claude-usage-dashboard.md \
  --path docs/superpowers/specs/2026-08-21-tools-collection-design.md \
  --path docs/superpowers/plans/2026-08-21-tools-collection-layout.md
git remote add origin "git@github.com:$REPO.git"
```

`git filter-repo` is at `/opt/homebrew/bin/git-filter-repo`. The app's own `docs/superpowers/` merges into the root `docs/superpowers/` because both land at the same path. Nothing is pushed. The result has exactly this content:

- the contents of `apps/media-grabber/` at the root;
- `docs/superpowers/` at the same path, minus `specs/2026-05-25-claude-usage-dashboard-design.md`, `plans/2026-05-25-claude-usage-dashboard.md`, `specs/2026-08-21-tools-collection-design.md`, `plans/2026-08-21-tools-collection-layout.md`;
- `.github/workflows/media-grabber.yml` as `.github/workflows/ci.yml`;
- `.github/workflows/media-grabber-release.yml` as `.github/workflows/release.yml`;
- `LICENSE`;
- no `.DS_Store` files.

- [ ] **Step 4: Check the result**

```bash
cd "$NEW" && test -f Project.swift && test -d site && test -f LICENSE && test -f .github/workflows/ci.yml && test -f .github/workflows/release.yml && test ! -e apps && echo layout-ok
find "$NEW" -name .DS_Store -not -path '*/.git/*'
for f in specs/2026-05-25-claude-usage-dashboard-design.md plans/2026-05-25-claude-usage-dashboard.md specs/2026-08-21-tools-collection-design.md plans/2026-08-21-tools-collection-layout.md; do test ! -e "$NEW/docs/superpowers/$f" || echo "unexpected $f"; done
test -f "$NEW/docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md" && echo parent-spec-ok
```

Expected: `layout-ok`, nothing from `find`, nothing from the loop, `parent-spec-ok`.

- [ ] **Step 5: Scan the history for secrets**

Run: `brew install gitleaks && gitleaks detect --source "$NEW" --no-banner` Expected: `no leaks found`. Any finding stops the phase; do not push.

**Gate:** all four expected results above. Hand off to Task 2.

---

### Task 2: Carry Claude's memory (You)

**Files:** none in the repo; copies a folder under `~/.claude/projects/`.

- [ ] **Step 1: Copy the memory folder**

```bash
MEM_OLD="$HOME/.claude/projects/$(echo "$OLD" | tr / -)/memory"
MEM_NEW="$HOME/.claude/projects/$(echo "$NEW" | tr / -)/memory"
test -d "$MEM_OLD" && test ! -e "$MEM_NEW" && mkdir -p "$(dirname "$MEM_NEW")" && cp -R "$MEM_OLD" "$MEM_NEW"
```

Expected: no output, exit 0. A failure means the source is missing or the destination already exists; nothing was copied.

- [ ] **Step 2: Find memories that name old paths**

Run: `grep -ln 'Github/Tools\|\.venv\|media-grabber-v' "$MEM_NEW"/*.md` Expected: a list of files. Start Claude in `$NEW` from here on, and name each edit one at a time. Nothing is deleted or rewritten without you naming it.

**Gate:** `ls "$MEM_NEW/MEMORY.md"` exists. Hand off to Task 3.

---

### Task 3: Python tooling and venv (Agent)

**Files:**

- Create: `requirements.txt`, `pyproject.toml`, `.pre-commit-config.yaml`, `.prettierrc.json`, `.prettierignore`, `.github/workflows/docs-format.yml`
- Modify: `.gitignore`, `Makefile` (`PY` at line 52, `.PHONY` at line 10)

**Interfaces:**

- Produces: `make venv`; `PY ?= .venv/bin/python` used by `plugin-test`.

- [ ] **Step 1: Copy the shared tooling files**

Run: `cp "$OLD/.prettierrc.json" "$OLD/.prettierignore" "$OLD/.pre-commit-config.yaml" "$NEW/" && cp "$OLD/.github/workflows/docs-format.yml" "$NEW/.github/workflows/"`

- [ ] **Step 2: Trim them to this repository**
  - `.prettierignore`: drop entries for other tools; keep `.venv`, `Derived`, `build`, `.build/`, `.superpowers/`.
  - `.pre-commit-config.yaml`: keep the ruff, ruff-format, check-yaml, check-added-large-files and prettier-markdown hooks; delete the stacked rollout comments.
  - `.github/workflows/docs-format.yml`: unchanged.

- [ ] **Step 3: Create `requirements.txt`**

One single-line comment, then `pytest==<version>`. The version is the one reported by `"$OLD/.venv/bin/python" -m pytest --version`.

- [ ] **Step 4: Create `pyproject.toml`**

`[tool.ruff]` with `target-version` and `line-length = 100` as in `$OLD/pyproject.toml` and `extend-exclude = [".venv", "build", "Derived"]`; `[tool.ruff.lint]` with `select = ["E", "F", "W", "I"]`; `[tool.ruff.format]`; `[tool.pytest.ini_options]` with `addopts = "-q"`. No rollout comments.

- [ ] **Step 5: Edit `.gitignore` and `Makefile`**

Add `.venv/`, `.ruff_cache/`, `.pytest_cache/` to `.gitignore`. In the Makefile set `PY ?= .venv/bin/python`, add `venv` to `.PHONY`, and add:

```make
venv:
	python3 -m venv .venv
	.venv/bin/pip install -r requirements.txt
```

- [ ] **Step 6: Verify**

Run: `make venv && .venv/bin/python -m pytest --version && make plugin-test` Expected: the pinned pytest version, then the plugin tests pass.

**Gate:** the three commands pass; `make lint` clean.

---

### Task 4: Tag lookup and release make targets (Agent)

**Files:**

- Create: `scripts/current-version.sh`, `scripts/tests/test_current_version.sh`
- Modify: `Makefile` (lines 74-96), `.github/workflows/ci.yml` (done in Task 7)

**Interfaces:**

- Produces: `scripts/current-version.sh` reads tag names on stdin and prints the highest bare `N.N.N`, or `0.0.0` when none qualifies. `make release-dry-run VERSION=`, `make release-overwrite VERSION=`, `make site-deploy` start `release.yml` (inputs `version`, `dry_run`, `overwrite`) and `pages.yml`.

- [ ] **Step 1: Write the failing test `scripts/tests/test_current_version.sh`**

Model it on `scripts/tests/test_bump_version.sh`. Cases (stdin → stdout):

- empty → `0.0.0`
- `v0.9.0`, `v0.10.0`, `v0.2.0` → `0.10.0`
- `v1.2.3`, `vfoo`, `media-grabber-v9.9.9`, `v1.2`, `v1.2.3-rc1` → `1.2.3`
- `v0.1.0` → `0.1.0`

- [ ] **Step 2: Run it to see it fail**

Run: `scripts/tests/test_current_version.sh` Expected: FAIL, `scripts/current-version.sh` not found.

- [ ] **Step 3: Implement `scripts/current-version.sh`**

Keep only lines matching `^v[0-9]+\.[0-9]+\.[0-9]+$`, strip `v`, sort numerically on each of the three fields (`sort -t. -k1,1n -k2,2n -k3,3n`), take the last, print `0.0.0` if empty. The script must exit 0 on empty input and on input with no qualifying line, so a `grep` that matches nothing must not abort it under `set -e -o pipefail`.

- [ ] **Step 4: Run the test**

Run: `scripts/tests/test_current_version.sh` Expected: PASS.

- [ ] **Step 5: Update the Makefile release block**

- `CURRENT_VERSION = $(shell git tag --list 'v[0-9]*' | scripts/current-version.sh)`.
- In `release`: the prompt, tag, annotation and push use `v$$next`; the annotation is `MediaGrabber v$$next`; the final echo says `pushed v$$next`. Checks for a clean tree, `main`, and `origin/main` are unchanged; bare `release` still errors.
- Add to `.PHONY` and implement:
  - `release-dry-run`: requires `VERSION` and validates it as `N.N.N`, then `gh workflow run release.yml -f version=$(VERSION) -f dry_run=true`.
  - `release-overwrite`: the same validation, a `read -p` confirmation in the existing style, then `gh workflow run release.yml -f version=$(VERSION) -f overwrite=true`.
  - `site-deploy`: `gh workflow run pages.yml`.
- Validation errors read `VERSION=X.Y.Z required` and `VERSION must be N.N.N`, and exit non-zero before any `gh` call.

- [ ] **Step 6: Verify the targets**

```bash
make -n release-dry-run VERSION=0.1.0
make release-dry-run
make release-dry-run VERSION=1.2
make release-overwrite
make release-overwrite VERSION=abc
```

Expected: the first prints a line containing `gh workflow run release.yml -f version=0.1.0 -f dry_run=true`; the other four exit non-zero with the validation messages and start nothing.

**Gate:** Step 4 and Step 6 results; `make lint` clean.

---

### Task 5: Feed address and appcast script (Agent)

**Files:**

- Modify: `scripts/appcast.py:9`, `Project.swift:22`, `scripts/tests/test_appcast.sh`

- [ ] **Step 1: Add failing tests to `scripts/tests/test_appcast.sh`**
  - `feed_pin`: the `FEED` value in `scripts/appcast.py` equals the `SUFeedURL` value in `Project.swift`, and both equal `https://github.com/Mshardul/MediaGrabber/releases/latest/download/appcast.xml`.
  - `reinsert_replaces`: inserting version `0.1.0` twice with different signatures leaves exactly one `<sparkle:version>0.1.0</sparkle:version>` item, carrying the second signature.
  - `empty_existing`: `--existing` pointing at an empty file yields a valid feed with exactly one item.
  - `missing_existing`: `--existing` pointing at a path that does not exist yields a valid feed with exactly one item.

- [ ] **Step 2: Run them**

Run: `make appcast-test` Expected: `feed_pin` FAILS (old address). `reinsert_replaces` and `empty_existing` pass: `upsert` already drops a same-version item. `missing_existing` may fail; that is the signal to handle a missing file.

- [ ] **Step 3: Implement**

Set `FEED` in `scripts/appcast.py` and `SUFeedURL` in `Project.swift` to the feed address. If `empty_existing` or `missing_existing` failed in Step 2, change the existing-file read, `parse_items` or `render` so an empty or missing input starts empty.

- [ ] **Step 4: Run**

Run: `make appcast-test` Expected: all pass.

**Gate:** `make appcast-test` green.

---

### Task 6: Runtime config address (Agent)

**Files:**

- Modify: `Sources/GrabberKit/Download/PlayerClientCatalog.swift:32`
- Test: the existing suite that covers `PlayerClientCatalog` (find with `grep -rln PlayerClientCatalog Tests`)

- [ ] **Step 1: Add the failing test**

`testRemoteURLPointsAtMediaGrabberRepo`: `XCTAssertEqual(PlayerClientCatalog.remoteURL.absoluteString, "https://raw.githubusercontent.com/Mshardul/MediaGrabber/main/config/player-clients.json")`. Update any existing test that pins the old string.

- [ ] **Step 2: Run it**

Run: `make test ONLY=GrabberKitTests/<Suite>` Expected: FAIL on the string.

- [ ] **Step 3: Change `remoteURL`**

To the string in the test.

- [ ] **Step 4: Run it**

Expected: PASS.

**Gate:** the suite passes; `make lint` clean.

---

### Task 7: CI workflow (Agent)

**Files:**

- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Edit**
  - `name: ci`; concurrency group `ci-${{ github.ref }}`.
  - Remove the `paths` filters under `push` and `pull_request`, the top-level `defaults.run.working-directory`, and every `working-directory: .` line.
  - Remove the `apps/media-grabber/` prefix everywhere: `.mise.toml` and `.xcode-version` at the root, `mise` `working_directory: .`, cache keys and paths (`hashFiles('.mise.toml')`, `.build`, `**/Package.resolved`).
  - `scripts-test` runs `scripts/tests/test_bump_version.sh` and `scripts/tests/test_current_version.sh`.

- [ ] **Step 2: Verify**

`actionlint` checks expressions, inputs and the shell in `run:` blocks, which a YAML parse does not. If `command -v actionlint` finds nothing, stop and ask you to run `brew install actionlint`.

```bash
grep -n 'apps/media-grabber\|working-directory' .github/workflows/ci.yml
actionlint .github/workflows/*.yml
```

Expected: no output from either.

**Gate:** both commands print nothing. The real check is Task 12.

---

### Task 8: Release workflow (Agent)

**Files:**

- Modify: `.github/workflows/release.yml`

**Interfaces:**

- Consumes: `scripts/appcast.py` arguments (`--existing --version --url --signature --length --notes --out`), unchanged.
- Produces: workflow-run artifact `appcast`; a published release carrying `MediaGrabber-X.Y.Z.dmg`, `SHA256SUMS`, `appcast.xml`.

- [ ] **Step 1: Tag, paths and version**
  - `tags: ['v*']`; the derive step uses `v="${REF_NAME#v}"` and keeps the `N.N.N` validation. Every tag string is `v${version}`.
  - Remove `defaults.run.working-directory` and every `working-directory: .`; drop `apps/media-grabber/` from `.xcode-version`, `mise`, `path=` outputs, the upload path and release files.

- [ ] **Step 2: Existing-release handling**
  - For a non-dry run, delete any draft for the tag first:
    ```bash
    id="$(gh api "repos/$GITHUB_REPOSITORY/releases" --paginate -q ".[] | select(.draft and .tag_name==\"$TAG\") | .id")"
    [ -z "$id" ] || gh api -X DELETE "repos/$GITHUB_REPOSITORY/releases/$id"
    ```
  - A published release for the tag stops the run unless `dry_run` or `overwrite`. With `overwrite`, the delete happens after the appcast is built (Step 4), just before the new draft is created.
  - The previous-release check counts published releases other than this tag: `gh release list --exclude-drafts --json tagName -q "[.[] | select(.tagName != \"$TAG\")] | length"`.

- [ ] **Step 3: Verify feed and key in the built app**

After the smoke test, read `SUFeedURL` from `Contents/Info` and fail unless it equals the feed address. If `vars.MG_SPARKLE_PUBLIC_KEY` is set, `SUPublicEDKey` must equal it. If it is unset, fail on a publish and allow it on a dry run.

- [ ] **Step 4: Appcast from the latest release**

Replace the `curl` of the Pages feed:

```bash
if gh release view --json tagName >/dev/null 2>&1; then
  gh release download --pattern appcast.xml --output appcast-current.xml --clobber \
    || { echo "the latest release has no appcast.xml, so the update feed is broken" >&2; exit 1; }
else
  : > appcast-current.xml
fi
```

The enclosure URL is `https://github.com/Mshardul/MediaGrabber/releases/download/v${VERSION}/MediaGrabber-${VERSION}.dmg` and the notes link is `https://github.com/Mshardul/MediaGrabber/releases/tag/v${VERSION}`. `appcast.py` writes `appcast.xml` in the working directory. The upload step changes from `name: media-grabber-appcast`, `path: apps/media-grabber/appcast.xml` to `name: appcast`, `path: appcast.xml`.

- [ ] **Step 5: Publish as draft, check, then publish**

Replace the `softprops` and `peaceiris` steps with one step, skipped on a dry run, using `GH_TOKEN`:

```bash
[ "$OVERWRITE" != "true" ] || gh release delete "$TAG" --yes --cleanup-tag
gh release create "$TAG" "$DMG" SHA256SUMS appcast.xml --draft --target "$GITHUB_SHA" --title "MediaGrabber $VERSION" --notes-file release-notes.md ${GENERATE:+--generate-notes}
names="$(gh release view "$TAG" --json assets -q '.assets[].name' | LC_ALL=C sort | tr '\n' ' ')"
[ "$names" = "MediaGrabber-$VERSION.dmg SHA256SUMS appcast.xml " ] || { echo "assets incomplete: $names" >&2; exit 1; }
gh release edit "$TAG" --draft=false --latest
```

`release-notes.md` holds the existing install note, preceded by `Initial release.` when no earlier published release exists. `GENERATE` is set when one does. The Pages publish step is removed. `--cleanup-tag` removes the old tag with the release, so the new tag is created at `$GITHUB_SHA` and matches the DMG.

- [ ] **Step 6: Verify**

```bash
grep -n 'apps/media-grabber\|media-grabber-v\|mshardul.github.io\|softprops\|peaceiris\|working-directory' .github/workflows/release.yml
actionlint .github/workflows/*.yml
```

Expected: no output from either.

**Gate:** both print nothing. The real check is Task 15.

---

### Task 9: Pages workflow (Agent)

**Files:**

- Create: `.github/workflows/pages.yml`

- [ ] **Step 1: Create it with exactly this content**

```yaml
name: pages

on:
  push:
    branches: [main]
    paths: ['site/**']
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with:
          path: site
      - id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: Verify**

Run: `actionlint .github/workflows/*.yml` Expected: no output.

**Gate:** actionlint is clean. `site/` is carried over from Tools and is the first product page; its first deploy is Task 14, Step 3.

---

### Task 10: Reference sweep (Agent)

**Files:**

- Modify: `Resources/NOTICES.md:6`, `README.md:9`, `roadmap.md` (any hit of the sweep pattern), `CLAUDE.md`, `docs/development.md`, `docs/state-flow.md:5`, `docs/superpowers/specs/2026-11-04-media-grabber-release-distribution-design.md`, `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` (lines 3, 58, 69, 231, 268, 593, 608, 610, 612)

- [ ] **Step 1: Edit each as a plain statement of the current state**
  - `NOTICES.md`: the ffmpeg build script is `scripts/fetch-tools.sh` in `https://github.com/Mshardul/MediaGrabber`.
  - `README.md`: the download link is `https://github.com/Mshardul/MediaGrabber/releases/latest`.
  - `CLAUDE.md` Release section (the `release-major` line naming the `media-grabber-v*` tag, and the line naming `.github/workflows/media-grabber-release.yml`): tag `vX.Y.Z`; the make targets from Task 4; workflows `ci.yml`, `release.yml`, `pages.yml`; the feed is the latest release's `appcast.xml`; Pages serves only the product page; the key names; remove "Pages must serve the `gh-pages` branch". Python section: `.venv/bin/python`, `make venv`. The doc-tree line no longer distinguishes a repo-root tree from an app-local one.
  - `docs/development.md`: remove `cd apps/media-grabber` and "From `apps/media-grabber`".
  - `docs/state-flow.md`: paths are relative to the repository root.
  - Release distribution spec: the feed is the latest release's asset, the tag is `vX.Y.Z`, no filtered-release-list workaround, and `overwrite` is the explicit way to replace a published release.
  - Parent spec (living doc): line 3 leaf is the repository root; lines 58 and 69 describe the repository root and a tree rooted at `/`; lines 231, 268, 593, 608, 610, 612 drop the `apps/media-grabber/` prefix from `docs/design-system.md`, `docs/mockups/screens.html`, `docs/job-status-and-actions.md`, `roadmap.md`, `future-ideas.md`, `README.md` and `docs/development.md`.

- [ ] **Step 2: Verify**

```bash
grep -rInE 'Mshardul/Tools|mshardul\.github\.io/Tools|media-grabber-v|apps/media-grabber|\.\./\.\./\.venv|Github/Tools|gh-pages|media-grabber(-release)?\.yml|media-grabber-appcast' . --exclude-dir=.git --exclude-dir=.venv --exclude-dir=Derived --exclude-dir=build --exclude-dir=superpowers --exclude-dir=archived
```

Expected: no output. A hit inside a ticket row or audit report that describes past work stays; any other hit is fixed. Then run the same pattern without the `superpowers` exclusion on the two living specs:

```bash
grep -nE 'Mshardul/Tools|mshardul\.github\.io/Tools|media-grabber-v|apps/media-grabber|\.\./\.\./\.venv|Github/Tools|gh-pages|media-grabber(-release)?\.yml|media-grabber-appcast' docs/superpowers/specs/2026-11-04-media-grabber-release-distribution-design.md docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md
```

Expected: no output.

**Gate:** the grep is clean as described.

---

### Task 11: Local gate (Agent)

- [ ] **Step 1: Lint, test, build**

Run: `make lint && make test && make` Expected: lint clean, all tests green, the app builds and launches.

- [ ] **Step 2: One app only**

Run: `mdfind 'kMDItemCFBundleIdentifier == "app.mediagrabber.mac"'` Expected: exactly one path. If a second is a build output from the Tools checkout, run `make drop-build-app` there.

**Gate:** both steps. Hand off to Task 12.

---

### Task 12: Push and CI (You)

- [ ] **Step 1: Push**

```bash
cd "$NEW"
git add -A
git commit -m "Point every address at the standalone repository"
git push -u origin main
```

The first push carries the history and the edited files. It also triggers `pages.yml` because `site/` is new; that run fails until Task 14 turns Pages on, so ignore it. CI runs before Task 13 creates the key; `Project.swift` omits `SUPublicEDKey` when `TUIST_SPARKLE_PUBLIC_KEY` is unset, so the build and tests do not need it.

- [ ] **Step 2: Watch CI**

```bash
sleep 10
RUN="$(gh run list --repo "$REPO" --workflow ci.yml --limit 1 --json databaseId -q '.[0].databaseId')"
test -n "$RUN" || { echo "no ci run yet; wait and repeat" >&2; false; }
gh run watch --repo "$REPO" --exit-status "$RUN"
gh run list --repo "$REPO" --workflow ci.yml --limit 1 --json conclusion -q '.[0].conclusion'
curl -fsSI https://raw.githubusercontent.com/Mshardul/MediaGrabber/main/config/player-clients.json | head -1
```

Expected: `success`, then an `HTTP/2 200` line.

**Gate:** both expected results. A red run goes back to the owning task.

---

### Task 13: Sparkle keys (You)

- [ ] **Step 1: Find the tool and check its options**

```bash
GK="$(find ~/Library/Developer/Xcode/DerivedData ~/Library/Caches/tuist -path '*Sparkle/bin/generate_keys' -type f 2>/dev/null | head -1)"
echo "$GK"
"$GK" --help
```

Expected: a path, then the options. If `--account`, `-x` or `-p` differ, use what `--help` shows.

- [ ] **Step 2: Create the pair under its own account**

Run: `"$GK" --account MediaGrabber` Expected: prints a new public key. A message that a key already exists means the account name was not used; stop.

- [ ] **Step 3: Export the private key outside the repository**

```bash
"$GK" --account MediaGrabber -x "$HOME/mediagrabber-sparkle-private.key"
wc -l "$HOME/mediagrabber-sparkle-private.key"
```

Expected: one line.

- [ ] **Step 4: Back it up**

Paste the file's contents into your password manager. Confirm you can read it back before the next step.

- [ ] **Step 5: Set the secret and the variable**

```bash
PUB="$("$GK" --account MediaGrabber -p)"
gh secret set SPARKLE_EDDSA_PRIVATE_KEY --repo "$REPO" < "$HOME/mediagrabber-sparkle-private.key"
gh variable set MG_SPARKLE_PUBLIC_KEY --repo "$REPO" --body "$PUB"
```

- [ ] **Step 6: Check**

```bash
gh secret list --repo "$REPO"
test "$(gh variable get MG_SPARKLE_PUBLIC_KEY --repo "$REPO")" = "$PUB" && echo key-matches
```

Expected: the secret is listed; `key-matches`.

- [ ] **Step 7: Remove the exported file**

Only after Step 4 is confirmed: `rm "$HOME/mediagrabber-sparkle-private.key"`.

**Gate:** Step 6. The private key is in the keychain and the password manager only.

---

### Task 14: Pages source (You)

- [ ] **Step 1: Set the source to GitHub Actions**

Run: `gh api -X POST "repos/$REPO/pages" -f build_type=workflow` Expected: JSON. If Pages already exists, use `-X PUT` with the same field.

- [ ] **Step 2: Check**

Run: `gh api "repos/$REPO/pages" -q .build_type` Expected: `workflow`

- [ ] **Step 3: Deploy the first page**

```bash
gh workflow run pages.yml --repo "$REPO"
sleep 10
RUN="$(gh run list --repo "$REPO" --workflow pages.yml --limit 1 --json databaseId -q '.[0].databaseId')"
test -n "$RUN" || { echo "no pages run yet; wait and repeat" >&2; false; }
gh run watch --repo "$REPO" --exit-status "$RUN"
curl -fsSI "$(gh api "repos/$REPO/pages" -q .html_url)" | head -1
```

Expected: the run succeeds and curl prints `HTTP/2 200`.

**Gate:** Step 3.

---

### Task 15: Release dry run (You)

- [ ] **Step 1: Start it**

Run (in `$NEW`): `make release-dry-run VERSION=0.1.0` Expected: `gh` reports the workflow run was requested.

- [ ] **Step 2: Watch it**

```bash
sleep 10
RUN="$(gh run list --repo "$REPO" --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')"
test -n "$RUN" || { echo "no release run yet; wait and repeat" >&2; false; }
gh run watch --repo "$REPO" --exit-status "$RUN"
gh api "repos/$REPO/actions/runs/$RUN/artifacts" -q '.artifacts[].name'
```

Expected: the run succeeds; the artifact list includes `appcast`. A run that skipped signing has no `appcast` artifact and does not count.

**Gate:** Step 2. The feed and key checks of Task 8 Step 3 passed inside the run.

---

### Task 16: Close the phase in the docs (Agent)

**Files:**

- Modify: `roadmap.md` (Phase 20 and 21 entries), `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1 (same entries), `CLAUDE.md` (phase line)

- [ ] **Step 1: Edit**

Phase 20 is `_(shipped)_` and Phase 21 is `_(next)_` in both files. The `CLAUDE.md` phase line lists Phase 20 as shipped and Phase 21 next.

- [ ] **Step 2: Verify**

Run: `grep -n 'Phase 20' roadmap.md CLAUDE.md` Expected: Phase 20 appears as shipped.

**Gate:** the grep. Hand off; you push this change.

---

### Task 17: Tools cleanup (You)

Run only after Tasks 12 to 16 are done.

- [ ] **Step 1: Retire the old keys**

```bash
gh secret delete SPARKLE_EDDSA_PRIVATE_KEY --repo Mshardul/Tools
gh variable delete MG_SPARKLE_PUBLIC_KEY --repo Mshardul/Tools
```

- [ ] **Step 2: Turn off Pages on Tools if it served only this app**

Check first: `gh api repos/Mshardul/Tools/pages -q .html_url`. If it serves anything else, skip. Otherwise: `gh api -X DELETE repos/Mshardul/Tools/pages`.

- [ ] **Step 3: Remove the app from Tools**

```bash
cd "$OLD"
make -C apps/media-grabber drop-build-app
git rm -rq apps/media-grabber .github/workflows/media-grabber.yml .github/workflows/media-grabber-release.yml
git ls-files docs/superpowers | grep -Ev '2026-05-25-claude-usage-dashboard|2026-08-21-tools-collection' | xargs git rm -q
rm -rf apps/media-grabber
```

The last line removes ignored build leftovers that `git rm` does not touch. You run it, so it is your call.

- [ ] **Step 4: Point Tools at the new repository**

Ask the agent to make two edits in Tools: add one line to `$OLD/README.md` linking `https://github.com/Mshardul/MediaGrabber`, and drop the sentence about the Swift app from the first-line comment of `$OLD/pyproject.toml`. This edits Tools, so name each file and say yes first.

- [ ] **Step 5: Commit and push Tools**

```bash
cd "$OLD"
git add -A
git commit -m "Move MediaGrabber to its own repository"
git push
```

- [ ] **Step 6: Check**

```bash
test ! -d "$OLD/apps/media-grabber" && echo app-gone
ls "$OLD/docs/superpowers/specs" "$OLD/docs/superpowers/plans"
gh secret list --repo Mshardul/Tools | grep -c SPARKLE
grep -rIn 'media-grabber' "$OLD" --exclude-dir=.git --exclude-dir=.venv --exclude-dir=node_modules
```

Expected: `app-gone`; the two listings show only the four other-tool documents; the count is `0`; the last grep prints nothing.

**Gate:** Step 6. The phase is complete.
