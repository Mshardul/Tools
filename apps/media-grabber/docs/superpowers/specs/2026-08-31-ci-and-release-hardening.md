# CI and Release Infrastructure — MediaGrabber

Two pieces of infrastructure for the MediaGrabber app:

1. A test and lint CI workflow: split jobs, an OS matrix, dependency caching, a
   pinned toolchain, and a coverage summary.
2. A release workflow triggered by a version tag that builds, packages, and
   publishes an unsigned `.dmg` to GitHub Releases, driven from `make`.

Infrastructure only — no app runtime code, no new tests of app behaviour, no
coverage gate.

## Setting

The app is at `apps/media-grabber/` in the `Tools` monorepo: a Tuist-generated
macOS project with `GrabberKit` (headless framework), `MediaGrabber` (SwiftUI
app), and four test targets (~224 tests across 45 files). `.mise.toml` pins
tuist 4.205.0, swiftformat 0.62.1, swiftlint 0.65.1.

The Python leaves use the same shape this design reuses: a workflow at
`.github/workflows/python-clis.yml`, a helper script at
`.github/scripts/py-test-matrix.sh`, and its shell test at
`.github/scripts/tests/` run in a dedicated CI job.

## Key decisions

| Topic | Decision |
|---|---|
| CI jobs | `lint`, `scripts-test`, `test` (matrix), `coverage` |
| OS matrix | `macos-14` and `macos-15` for `test` |
| Coverage | Enabled, extracted, printed to the job summary. No pass/fail gate — thresholds come after a few reports are read. `GrabberKit` is the headline number; `MediaGrabber` (SwiftUI) is informational |
| Xcode | Pinned via an `XCODE_VERSION` env var declared identically at the top of both workflow files, read by every macOS job. Pinned for reproducible coverage numbers; bumped reactively (in both files) when a runner image drops it. A weekly scheduled run on `latest` surfaces retirement and upstream breakage out of band. Drop the pin if `latest` stays green across a couple of Xcode releases |
| Caching | mise tool cache and SwiftPM/DerivedData, keyed on `.mise.toml` and `Package.resolved` (a missing `Package.resolved` yields a constant key — expected, not broken) |
| CI concurrency | Per-ref group, `cancel-in-progress: true` |
| Release concurrency | Group `media-grabber-release`, `cancel-in-progress: false` — serialize, never interrupt a half-done publish |
| Release trigger | A `media-grabber-v*` git tag, or `workflow_dispatch` with a `version` input for retry and dry runs |
| Versioning | Manual SemVer, pre-1.0 (`0.x`). A person picks patch/minor/major; the mechanics are scripted |
| Version string forms | The tag is `media-grabber-v1.2.3`; every derived string (`MARKETING_VERSION`, DMG name, bump arithmetic) is bare `1.2.3` |
| Release entry point | `make release-patch` / `release-minor` / `release-major`. Bare `make release` errors |
| First release | `make release-minor` from the `0.0.0` sentinel yields `0.1.0` — no dedicated path |
| Signing | Ad-hoc (`codesign --sign -`), no hardened runtime, no `--deep`. Repository variable `MG_SIGN_IDENTITY` overrides the identity for a real Developer ID |
| DMG tool | andreyvit `create-dmg`, a single shell script, vendored at a pinned upstream SHA. No Homebrew in the release path |
| Release notes | Release `body` is always the install note; GitHub-generated commit notes are appended only when a previous `media-grabber-v*` tag exists (the first release would otherwise dump the whole monorepo history) |
| Release artifacts | `MediaGrabber-<version>.dmg` and `SHA256SUMS`; quarantine-clear instructions in the release body |

## Workstream A — CI

`.github/workflows/media-grabber.yml`, triggered on `push` and `pull_request`
touching `apps/media-grabber/**` or the workflow file, plus a weekly `schedule`
(the Xcode-`latest` canary).

```
concurrency:
  group: media-grabber-${{ github.ref }}
  cancel-in-progress: true

env:
  XCODE_VERSION: "16.1"   # both runner images; bump when setup-xcode reports "not found"

jobs:
  lint:          # macos-14, no build
  scripts-test:  # ubuntu, runs test_bump_version.sh
  test:          # matrix [macos-14, macos-15]
  coverage:      # macos-14, needs: test (whole matrix must be green)
```

`XCODE_VERSION` is the pin point. Both workflow files
(`media-grabber.yml` and `media-grabber-release.yml`) declare the same value at
the top `env:` block; every macOS job passes it to
`maxim-lobanov/setup-xcode@v1`. The value shown (`16.1`) is a placeholder — the
real one is chosen at implementation time from the runner image manifests. A
bump edits both files. The weekly `schedule` trigger on `media-grabber.yml` runs
the `test` job with `setup-xcode` set to `latest` instead of `XCODE_VERSION`, so
a retired Xcode or a `latest`-only regression shows up on its own schedule
rather than inside an unrelated PR. If those weekly runs stay green across a
couple of Xcode releases, the pin can be removed.

### `lint`

Checkout → `jdx/mise-action` → `maxim-lobanov/setup-xcode` (`$XCODE_VERSION`) →
`swiftformat --lint .` → `swiftlint lint --strict`. Runs on source files
directly, no `tuist generate`, so a formatting error surfaces without waiting on
a build.

### `scripts-test`

`runs-on: ubuntu-latest`. Checkout → run
`apps/media-grabber/scripts/tests/test_bump_version.sh`. A standalone job (like
`matrix-script` in `python-clis.yml`) so a script-logic failure is attributed
cleanly rather than buried inside a Swift-lint job.

### `test` (matrix)

```
strategy:
  fail-fast: false
  matrix:
    os: [macos-14, macos-15]
runs-on: ${{ matrix.os }}
```

Checkout → restore caches → `mise-action` → `setup-xcode` (`$XCODE_VERSION`,
or `latest` on the weekly `schedule` run) → `tuist generate --no-open` →
`tuist test` → upload the `.xcresult` as `xcresult-${{ matrix.os }}`.

`tuist test` (not raw `xcodebuild`) is right for CI where only pass/fail matters,
per CLAUDE.md. The scheme carries coverage (below), so the `.xcresult` is
coverage-bearing with no extra flags.

Caches:

| Path | Key |
|---|---|
| `~/.local/share/mise` | `mise-${{ matrix.os }}-${{ hashFiles('apps/media-grabber/.mise.toml') }}` |
| `~/Library/Developer/Xcode/DerivedData` and `apps/media-grabber/.build` | `spm-${{ matrix.os }}-${{ hashFiles('apps/media-grabber/**/Package.resolved') }}` |

Restore-keys fall back to the OS-scoped prefix, so a dependency bump still gets a
warm-ish cache. There are no external SPM dependencies today: `Package.resolved`
does not exist, `hashFiles` returns an empty string, and the key collapses to the
constant `spm-<os>-`. That is expected — the step is a near-no-op now and starts
carrying real cache the day a dependency is added.

### `coverage`

`needs: test`, `runs-on: macos-14`. `needs: test` means the entire `test` matrix
(both `macos-14` and `macos-15`) must be green for `coverage` to run — a failure
or skipped test on either leg suppresses the coverage number for that run. This
is deliberate: a coverage figure from a run where something is broken is
misleading. It also means the `coverage` job's own red check is not independent
of `test` — if `test` is red, `coverage` never reports.

1. Download `xcresult-macos-14`. `macos-14` is the canonical coverage host — it
   is also the `lint` host and matches the primary local development
   architecture, so its numbers reproduce on a contributor's machine. The
   `macos-15` leg still runs the whole suite; a test that only fails or skips
   there is a `test`-job failure (which, per above, blocks `coverage`). It is
   simply not the coverage *source*.
2. `xcrun xccov view --report --json Result.xcresult` → line coverage for
   `GrabberKit` and `MediaGrabber` (test bundles excluded).
3. Table to `$GITHUB_STEP_SUMMARY`: per-target line coverage and covered/total
   counts. `GrabberKit` first, labelled the headline figure; `MediaGrabber`
   labelled informational (SwiftUI view code). No blended number — one figure
   would average a meaningful number with a mostly-noise one and anchor a future
   gate to it.
4. Exit 0 regardless. No threshold comparison.

The parse is a shell + `python3` snippet inline in the workflow (the runner has
Python 3). Past ~15 lines it moves to `.github/scripts/mg-coverage-summary.sh`
with a test, matching the `py-test-matrix.sh` pattern.

### Coverage in the scheme

The workspace test scheme (`MediaGrabber-Workspace`) is defined explicitly in
`Project.swift` with a `TestAction` setting `coverage: true` and
`codeCoverageTargets` = `GrabberKit`, `MediaGrabber`, so every `tuist test` run —
CI and local — produces coverage. `automaticSchemesOptions: .enabled()` stays for
the per-target auto-schemes; only the workspace scheme is explicit.

This is the whole of Workstream A's `Project.swift` footprint.

## Workstream B — Release

### `make` targets (`apps/media-grabber/Makefile`)

```make
# --- Release ---
.PHONY: release release-patch release-minor release-major

CURRENT_VERSION = $(shell git tag --list 'media-grabber-v*' --sort=-v:refname \
	| head -1 | sed 's/^media-grabber-v//' | grep . || echo 0.0.0)

release-patch: BUMP := patch
release-minor: BUMP := minor
release-major: BUMP := major
release-patch release-minor release-major: release

release:
	@test -n "$(BUMP)" || { echo "pick one: make release-patch | release-minor | release-major"; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "working tree dirty — commit first"; exit 1; }
	@test "`git rev-parse --abbrev-ref HEAD`" = main || { echo "not on main"; exit 1; }
	@git fetch --quiet origin main
	@test "`git rev-parse HEAD`" = "`git rev-parse origin/main`" || { echo "local main != origin/main — push or pull first"; exit 1; }
	@next=$$(scripts/bump-version.sh $(CURRENT_VERSION) $(BUMP)) || exit 1 ; \
		echo "$(CURRENT_VERSION)  ->  $$next" ; \
		read -p "tag media-grabber-v$$next and push? [y/N] " ok ; \
		[ "$$ok" = y ] || { echo aborted; exit 1; } ; \
		git tag -a "media-grabber-v$$next" -m "media-grabber v$$next" ; \
		git push origin "media-grabber-v$$next" ; \
		echo "pushed media-grabber-v$$next — CI builds the release now"
```

`next=$$(...) || exit 1` is explicit: a `bump-version.sh` failure (bad current
version, unknown bump word) stops the recipe before any `git tag`. A bare
`;`-chained `next=\`...\`` would not — `;` ignores the preceding exit status, and
the recipe would reach `git tag` with an empty `$next`. The `read` and the
y/N check are on their own statements so an aborted confirmation also exits
non-zero without tagging.

`CURRENT_VERSION` uses lazy `=`, so the `git tag` call fires only when a
`release-*` target runs — `make`, `make build`, `make generate` never shell out
to git, and a `.git`-less checkout does not error.

The git calls are user-initiated (`make release-*` is the explicit ask), so this
sits within the repo's "no automatic git" rule. The guards — clean tree, on
`main`, synced with `origin/main` — stop the "tagged a dirty or stale commit"
mistake. This rationale is design context; it does not appear as Makefile
comments — the target's `echo` lines carry what a user needs at run time.

Bare `make release` hits the empty-`BUMP` check and errors.

### `scripts/bump-version.sh`

```
Usage: bump-version.sh <current> <patch|minor|major>
  current: bare MAJOR.MINOR.PATCH (e.g. 0.0.0)
Prints the next bare version to stdout.
  bump-version.sh 0.4.2 patch  -> 0.4.3
  bump-version.sh 0.4.2 minor  -> 0.5.0
  bump-version.sh 0.4.2 major  -> 1.0.0
```

Pure arithmetic — no git, no network. A malformed current version or unknown
bump word gives a non-zero exit and a stderr message.

### `scripts/tests/test_bump_version.sh`

Shape of `.github/scripts/tests/test_py_test_matrix.sh`: plain `bash`, `ok` /
`FAIL` lines, non-zero exit on any failure. Run by `scripts-test`. Cases:

- each bump kind from a mid-range version
- patch / minor / major from `0.0.0`
- minor zeroes the patch; major zeroes minor and patch
- rejects `1.2`, `1.2.3.4`, `v1.2.3`, `1.2.x`
- rejects an unknown bump word

### `scripts/create-dmg` (vendored)

andreyvit `create-dmg` is one shell script. It lives at
`apps/media-grabber/scripts/create-dmg` (with its `support/` template files if
the pinned revision uses them), copied from a specific upstream git SHA noted in
a one-line comment at the top. Homebrew cannot pin a formula version, Homebrew on
CI is slow and sometimes down, and the tool is small enough to own. Updating it
means re-vendoring at a new SHA. The vendored script is the only DMG path — no
`hdiutil` fallback.

### Release workflow — `.github/workflows/media-grabber-release.yml`

```
on:
  push:
    tags: ['media-grabber-v*']
  workflow_dispatch:
    inputs:
      version:
        description: 'bare version, e.g. 0.1.0'
        required: true
      dry_run:
        description: 'build and package but do not publish'
        type: boolean
        default: false
      overwrite:
        description: 'allow replacing an existing release for this version'
        type: boolean
        default: false

concurrency:
  group: media-grabber-release
  cancel-in-progress: false

jobs:
  release:
    runs-on: macos-14
    timeout-minutes: 30
```

`timeout-minutes: 30` keeps a hung step (a stuck `hdiutil`, say) from wedging the
serialized `concurrency` queue for the 6-hour default.

1. **Checkout.** Tag push: at the tag. `workflow_dispatch`: at the dispatch ref.
2. **Version.** Tag push: strip `media-grabber-v` from `github.ref_name`.
   `workflow_dispatch`: the `version` input. Fail unless it matches `N.N.N`.
3. **Ancestry.** `git merge-base --is-ancestor "$GITHUB_SHA" origin/main` — the
   built commit must be on `main`. A tag from a stray commit fails here before
   any build. Skipped for a `dry_run` dispatch.
4. **Existing-release guard.** Query the GitHub API for a release tagged
   `media-grabber-v<VERSION>`. If one exists and this is neither a `dry_run` nor
   an `overwrite` dispatch, fail — a re-dispatched or re-pushed version does not
   silently clobber a published release's notes and assets. `overwrite: true`
   (dispatch only) is the deliberate escape hatch for the retry path.
5. **Toolchain.** `mise-action` + `setup-xcode` (`$XCODE_VERSION`, this
   workflow's own `env:` copy of the pin).
6. **Build Release.** Export `TUIST_MG_VERSION=$VERSION`, then
   `tuist generate --no-open` and
   `tuist build --configuration Release MediaGrabber`. `Project.swift` reads
   `TUIST_MG_VERSION` into `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`,
   defaulting to `0.0.0` when unset. This is Workstream B's `Project.swift`
   footprint.
7. **Locate the `.app`** in the Release products dir.
8. **Sign.** `codesign --force --sign "${MG_SIGN_IDENTITY:--}" MediaGrabber.app`
   — no `--deep` (the framework is signed by the build; the app bundle signs on
   its own), no `--options runtime` (hardened runtime is inert without
   notarization and worsens Gatekeeper elsewhere; it also matches
   `ENABLE_HARDENED_RUNTIME: NO`). `MG_SIGN_IDENTITY` is a repository variable;
   unset means `-`. A comment marks where notarization and `--options runtime`
   arrive together. Then `codesign --verify --strict MediaGrabber.app` — an
   ad-hoc signing failure fails the job here rather than becoming a cryptic
   Gatekeeper error downstream.
9. **Package.** The vendored `scripts/create-dmg`, Applications-folder alias,
   plain layout, output `MediaGrabber-<VERSION>.dmg`. Failure fails the job.
10. **Verify.** `hdiutil attach` the image; assert `MediaGrabber.app` is present
    and a directory; assert
    `defaults read "$vol/MediaGrabber.app/Contents/Info" CFBundleShortVersionString`
    equals `$VERSION` — the one check tying the artifact to the tag, catching a
    stale `TUIST_MG_VERSION` or a `Project.swift` wiring bug; `hdiutil detach`.
    A corrupt DMG, a broken build, or a version mismatch fails here, before
    publish.
11. **Checksums.** `cd` into the artifact directory, then
    `shasum -a 256 MediaGrabber-<VERSION>.dmg > SHA256SUMS`, so the file holds a
    bare filename and verifies with `shasum -c`. This guards against transfer
    corruption only — it is not an authenticity control (anyone who can replace
    the `.dmg` asset can replace `SHA256SUMS` too). The release body does not
    present it as a trust anchor.
12. **Publish** (skipped on `dry_run`). `softprops/action-gh-release` uploads the
    `.dmg` and `SHA256SUMS`.
    - `body` is always exactly the install note (below). `action-gh-release`
      prepends `body` to any generated notes, so this puts the install note on
      top.
    - `generate_release_notes: true` when a previous `media-grabber-v*` tag
      exists (a step-4 output). For the first release there is no previous tag
      and generated notes would expand to the entire monorepo history, so
      `generate_release_notes` is left `false` and the `body` is extended with a
      leading "Initial release." line.
    - Install note:

      > MediaGrabber is not yet signed with an Apple Developer ID. On first
      > launch, right-click the app and choose **Open**, or run
      > `xattr -dr com.apple.quarantine /Applications/MediaGrabber.app`.

### `Project.swift` version wiring

```
let version = Environment.mgVersion.getString(default: "0.0.0")
...
settings: .settings(base: [
    "MARKETING_VERSION": .string(version),
    "CURRENT_PROJECT_VERSION": .string(version),
    ...
])
infoPlist: .extendingDefault(with: [
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    ...
])
```

`Environment.mgVersion` maps to `TUIST_MG_VERSION`. No env set → `0.0.0`. The
release workflow exports `TUIST_MG_VERSION=$VERSION` before `tuist generate`.

`CFBundleVersion` carries the same bare SemVer as `CFBundleShortVersionString`.
When Sparkle arrives (parent design spec §10.2, Phase 11) it compares
`CFBundleVersion` between releases; the Sparkle hint there notes that this scheme
depends on every release using a full, monotonically increasing
`MAJOR.MINOR.PATCH` (manual SemVer already guarantees this), or on moving
`CFBundleVersion` to a build counter at that point.

## Components

| Path | Role |
|---|---|
| `.github/workflows/media-grabber.yml` | CI: `lint`, `scripts-test`, `test` matrix, `coverage` |
| `.github/workflows/media-grabber-release.yml` | Release: tag / dispatch → build → package → verify → publish |
| `apps/media-grabber/scripts/bump-version.sh` | SemVer bump arithmetic |
| `apps/media-grabber/scripts/tests/test_bump_version.sh` | its test, run by `scripts-test` |
| `apps/media-grabber/scripts/create-dmg` (+ `support/`) | vendored DMG builder, pinned at an upstream SHA |
| `apps/media-grabber/Project.swift` | explicit coverage-bearing workspace scheme; version from `TUIST_MG_VERSION` |
| `apps/media-grabber/Makefile` | `release` / `release-patch` / `release-minor` / `release-major` |
| `apps/media-grabber/CLAUDE.md` | "Release" section: cutting a release, tag vs version-string, the `XCODE_VERSION` pin and its weekly canary, where signing / notarization / hardened runtime arrive |

## Failure modes

- **Malformed tag or dispatch version** (`media-grabber-vfoo`, `1.2`): step 2
  exits before any build.
- **Tag from a commit not on `main`:** step 3 ancestry check fails before build.
- **Re-releasing an existing version:** step 4 fails unless `dry_run` or
  `overwrite`.
- **`create-dmg` failure:** job fails at step 9, before publish.
- **Corrupt DMG, broken build inside it, or app version ≠ tag:** step 10
  verification fails, before publish.
- **`codesign` did not take:** step 8's `--verify --strict` fails the job.
- **Dirty or stale tree at `make release-*`:** guarded, errors before tagging.
- **`bump-version.sh` bad input:** the recipe's `next=$$(...) || exit 1` stops
  the recipe before any `git tag`.
- **Two tags pushed close together:** the release `concurrency` group serializes
  them; a hung run is bounded by `timeout-minutes: 30`, so the queue is not
  wedged.
- **Whole `test` matrix not green:** `coverage` does not run (`needs: test`). A
  `macos-15`-only failure therefore also suppresses the coverage summary for
  that run — intentional; a coverage number from a broken run is misleading.
- **`macos-15` image quirk** breaking the matrix: `fail-fast: false` keeps the
  `macos-14` leg reporting, so the failure is still attributable.
- **Pinned Xcode retired from an image:** `setup-xcode` fails with a clear
  error; bump `XCODE_VERSION`. The weekly `latest` run flags this before it
  lands in a PR.

## Testing

- `bump-version.sh` — `test_bump_version.sh`, run by `scripts-test`.
- `make` release targets — simple shell conditionals, exercised by hand at the
  first release, no harness.
- Vendored `create-dmg` — exercised by the release workflow's step-10 verify; a
  broken vendor fails there.
- CI workflow — validated by the PR's own CI run.
- Release workflow — validated before the first real tag by a `workflow_dispatch`
  `dry_run` (build + package + verify, no publish). The first published release
  is `media-grabber-v0.1.0`.

## Out of scope

- Coverage threshold / gate — set after real reports are read.
- Notarization, real Developer ID signing, hardened runtime — slot points left
  in place, added together later.
- In-app updater / Sparkle / appcast — parent design spec §10.2, Phase 11.
- `CHANGELOG.md` and curated release notes — auto-generated / fixed-body for now.
- Automatic version bumping from commit messages (`release-please` etc.) —
  revisited only if release cadence makes manual bumps a chore.
- Runtime resilience work and new app-behaviour tests.
- Tuist remote / binary cache — needs infrastructure; local caching only.
- Cross-matrix coverage diffing — `macos-14` is canonical; `macos-15` test
  failures are caught by the `test` job.
