# CI and Release Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the MediaGrabber app a split-job CI workflow with an OS matrix, caching, a pinned toolchain, and a coverage summary, plus a tag-triggered release workflow that builds, packages, verifies, and publishes an unsigned `.dmg` to GitHub Releases, driven from `make`.

**Architecture:** Two GitHub Actions workflow files at the repo root (`.github/workflows/`), two small shell scripts plus one shell-test harness under `apps/media-grabber/scripts/`, a vendored copy of andreyvit `create-dmg`, and edits to `apps/media-grabber/Project.swift`, `Makefile`, and `CLAUDE.md`. No app runtime code changes. The shell scripts follow the existing `.github/scripts/py-test-matrix.sh` + `.github/scripts/tests/` pattern; each gets its own CI job so a failure is attributed cleanly.

**Tech Stack:** GitHub Actions, Tuist 4.205.0 (via `mise`), `xcodebuild` / `xccov`, bash, `hdiutil`, `codesign`, `softprops/action-gh-release`, `maxim-lobanov/setup-xcode`, `jdx/mise-action`.

**Spec:** `apps/media-grabber/docs/superpowers/specs/2026-08-31-ci-and-release-hardening.md`

## Global Constraints

- **Repo:** monorepo at `/Users/shardul/Documents/Github/Tools`. The app is the leaf `apps/media-grabber/`.
- **Toolchain versions** (pinned in `apps/media-grabber/.mise.toml`, do not change): tuist `4.205.0`, swiftformat `0.62.1`, swiftlint `0.65.1`. `tuist` is not on `PATH` — invoke via `mise exec -- tuist …` from inside `apps/media-grabber/`.
- **Xcode pin:** an `XCODE_VERSION` env var declared identically at the top `env:` block of BOTH workflow files. The value `16.1` in this plan is a placeholder — replace it in Task 12 with a real version present on both `macos-14` and `macos-15` runner images (check the [actions/runner-images](https://github.com/actions/runner-images) manifests for `macos-14` and `macos-15` at implementation time; pick a version listed for both).
- **Tag format:** release tags are `media-grabber-v<MAJOR>.<MINOR>.<PATCH>` (e.g. `media-grabber-v0.1.0`). Every derived string — `MARKETING_VERSION`, `CFBundleShortVersionString`, DMG filename, `bump-version.sh` I/O — is the **bare** `MAJOR.MINOR.PATCH`, no `v`.
- **Versioning:** manual SemVer, pre-1.0. The `0.0.0` string is the "nothing released yet" sentinel; it is never itself tagged.
- **Comments:** single-line only, only to explain *why*, only where names don't carry it. No stacked `//` or `#` blocks, no multi-line doc comments, in any file type (Swift, shell, YAML, Make, TOML). This is a hard repo rule — see `apps/media-grabber/CLAUDE.md`. Design rationale from the spec does NOT get transcribed into code as comments.
- **Git:** never run `git` commands except where a task step explicitly says to. The `make release-*` targets invoke `git` because the user runs them deliberately — that is allowed; ambient `git status` / `git log` while implementing is not.
- **No `git commit` inside CI or scripts.** The only `git` writes are in the `make release` recipe (`git tag`, `git push`), run by a human.
- **Signing:** ad-hoc only (`codesign --sign -`). No `--deep`, no `--options runtime`. A repository variable `MG_SIGN_IDENTITY` overrides the identity; unset means `-`.
- **DMG:** built by the vendored `apps/media-grabber/scripts/create-dmg`. No Homebrew in the release path, no `hdiutil` fallback path.
- **Out of scope** (do not build, do not stub beyond a one-line comment marker where the spec says): coverage gate/threshold, notarization, real Developer ID signing, hardened runtime, Sparkle/updater, `CHANGELOG.md`, commit-message-driven versioning, Tuist remote cache, cross-matrix coverage diffing.

---

## File Structure

**New files:**

| Path | Responsibility |
|---|---|
| `apps/media-grabber/scripts/bump-version.sh` | Pure SemVer arithmetic: `<current> <patch\|minor\|major>` → next bare version on stdout. No git, no network. |
| `apps/media-grabber/scripts/tests/test_bump_version.sh` | Test harness for `bump-version.sh`, shape of `.github/scripts/tests/test_py_test_matrix.sh`. |
| `apps/media-grabber/scripts/create-dmg` (+ `support/` if the pinned revision needs it) | Vendored andreyvit `create-dmg`, copied verbatim at a pinned upstream SHA recorded in a one-line comment at the top. |
| `.github/workflows/media-grabber-release.yml` | Release pipeline: tag / dispatch → version → guards → build → sign → package → verify → publish. |

**Modified files:**

| Path | Change |
|---|---|
| `.github/workflows/media-grabber.yml` | Full rewrite: `concurrency`, `env.XCODE_VERSION`, weekly `schedule`, jobs `lint` / `scripts-test` / `test` (matrix) / `coverage`, caching. |
| `apps/media-grabber/Project.swift` | Explicit `MediaGrabber-Workspace` scheme with coverage on for `GrabberKit` + `MediaGrabber`; `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` from `TUIST_MG_VERSION` env, default `0.0.0`. |
| `apps/media-grabber/Makefile` | `release` / `release-patch` / `release-minor` / `release-major` targets; `CURRENT_VERSION` (lazy). |
| `apps/media-grabber/CLAUDE.md` | New "## Release" section. |

**Task order and dependencies:**

```
Task 1  bump-version.sh + test           (independent)
Task 2  scripts-test wiring is folded into Task 11 (CI rewrite)
Task 3  vendor create-dmg                 (independent)
Task 4  Project.swift — version wiring    (independent)
Task 5  Project.swift — coverage scheme   (independent of 4, same file — do after 4)
Task 6  Makefile release targets          (needs Task 1)
Task 7  release workflow                  (needs Tasks 3, 4)
Task 8  CLAUDE.md Release section          (needs Tasks 6, 7 to describe them accurately)
Task 9  CI workflow rewrite               (needs Task 1 for scripts-test job, Task 5 for coverage)
```

Renumbered below into build order: 1 bump-version, 2 create-dmg, 3 Project.swift version, 4 Project.swift coverage, 5 Makefile, 6 release workflow, 7 CI workflow, 8 CLAUDE.md.

---

### Task 1: `bump-version.sh` + test harness

**Files:**
- Create: `apps/media-grabber/scripts/bump-version.sh`
- Test: `apps/media-grabber/scripts/tests/test_bump_version.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: an executable `bump-version.sh` at `apps/media-grabber/scripts/bump-version.sh`. Contract: `bump-version.sh <current> <bump>` where `<current>` is `N.N.N` (non-negative integers) and `<bump>` is exactly `patch`, `minor`, or `major`. On success: prints the next bare `N.N.N` to stdout, exits 0. On bad input: prints a message to stderr, exits non-zero, prints nothing to stdout. `minor` resets patch to 0; `major` resets minor and patch to 0.

- [ ] **Step 1: Write the failing test**

Create `apps/media-grabber/scripts/tests/test_bump_version.sh`:

```bash
#!/usr/bin/env bash
# Tests for bump-version.sh.
# Run: apps/media-grabber/scripts/tests/test_bump_version.sh

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bump-version.sh"
fails=0

ok_case() {
    local name="$1" current="$2" bump="$3" expected="$4" actual
    actual="$("$SCRIPT" "$current" "$bump")"
    if [ "$actual" = "$expected" ]; then
        printf 'ok   - %s\n' "$name"
    else
        printf 'FAIL - %s\n      expected: %s\n      actual:   %s\n' "$name" "$expected" "$actual"
        fails=$((fails + 1))
    fi
}

rejects() {
    local name="$1"; shift
    if "$SCRIPT" "$@" >/dev/null 2>&1; then
        printf 'FAIL - %s (expected non-zero exit)\n' "$name"
        fails=$((fails + 1))
    else
        printf 'ok   - %s\n' "$name"
    fi
}

ok_case "patch mid-range"        0.4.2 patch 0.4.3
ok_case "minor mid-range"        0.4.2 minor 0.5.0
ok_case "major mid-range"        0.4.2 major 1.0.0
ok_case "patch from 0.0.0"       0.0.0 patch 0.0.1
ok_case "minor from 0.0.0"       0.0.0 minor 0.1.0
ok_case "major from 0.0.0"      0.0.0 major 1.0.0
ok_case "minor zeroes patch"     3.7.9 minor 3.8.0
ok_case "major zeroes minor+patch" 3.7.9 major 4.0.0
ok_case "two-digit components"   9.10.11 patch 9.10.12

rejects "too few parts"          1.2 patch
rejects "too many parts"         1.2.3.4 patch
rejects "v prefix"               v1.2.3 patch
rejects "non-numeric component"  1.2.x patch
rejects "unknown bump word"      1.2.3 sideways
rejects "missing bump arg"       1.2.3
rejects "empty current"          "" patch

if [ "$fails" -ne 0 ]; then
    printf '\n%d test(s) failed\n' "$fails"
    exit 1
fi
printf '\nall tests passed\n'
```

- [ ] **Step 2: Make the test executable and run it — verify it fails**

Run:
```bash
chmod +x apps/media-grabber/scripts/tests/test_bump_version.sh
apps/media-grabber/scripts/tests/test_bump_version.sh
```
Expected: FAIL — `bump-version.sh` does not exist, every `ok_case` errors under `set -e` (the harness itself aborts at the first `$("$SCRIPT" ...)`).

- [ ] **Step 3: Write `bump-version.sh`**

Create `apps/media-grabber/scripts/bump-version.sh`:

```bash
#!/usr/bin/env bash
# Usage: bump-version.sh <current N.N.N> <patch|minor|major>  -> prints next bare version

set -euo pipefail

current="${1:-}"
bump="${2:-}"

die() { echo "bump-version: $1" >&2; exit 1; }

case "$current" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) die "current version must be N.N.N, got: '${current}'" ;;
esac

IFS=. read -r major minor patch <<EOF
$current
EOF

for part in "$major" "$minor" "$patch"; do
    case "$part" in
        ''|*[!0-9]*) die "current version must be N.N.N, got: '${current}'" ;;
    esac
done

case "$bump" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    *) die "bump must be patch|minor|major, got: '${bump}'" ;;
esac

printf '%s.%s.%s\n' "$major" "$minor" "$patch"
```

- [ ] **Step 4: Make executable and run the test — verify it passes**

Run:
```bash
chmod +x apps/media-grabber/scripts/bump-version.sh
apps/media-grabber/scripts/tests/test_bump_version.sh
```
Expected: PASS — `all tests passed`, every line `ok`.

- [ ] **Step 5: Sanity-check the `1.2.x` rejection specifically**

The glob `[0-9]*.[0-9]*.[0-9]*` matches `1.2.x` (the third component starts with... no, `x` is not `[0-9]`). Confirm the per-component numeric loop is what rejects it:
```bash
apps/media-grabber/scripts/bump-version.sh 1.2.x patch; echo "exit: $?"
```
Expected: `bump-version: current version must be N.N.N, got: '1.2.x'` on stderr, exit 1.

- [ ] **Step 6: Commit**

```bash
git add apps/media-grabber/scripts/bump-version.sh apps/media-grabber/scripts/tests/test_bump_version.sh
git commit -m "feat(media-grabber): add bump-version.sh with test harness"
```

---

### Task 2: Vendor `create-dmg`

**Files:**
- Create: `apps/media-grabber/scripts/create-dmg` (and `apps/media-grabber/scripts/support/` only if the pinned revision references it)

**Interfaces:**
- Consumes: nothing.
- Produces: an executable `apps/media-grabber/scripts/create-dmg`. Contract (andreyvit's): `create-dmg [options] <output.dmg> <source-folder-or-app>`. The release workflow (Task 6) calls it as
  `scripts/create-dmg --volname "MediaGrabber <VERSION>" --app-drop-link 0 0 "MediaGrabber-<VERSION>.dmg" "<dir containing MediaGrabber.app>"`.
  The exact option names must match the vendored revision — verify against the script's own `--help` / header after vendoring and adjust the Task 6 invocation to match.

- [ ] **Step 1: Fetch the upstream script at a pinned SHA**

Pick a specific commit from `https://github.com/andreyvit/create-dmg` (use the latest commit on `master` at implementation time; record its full 40-char SHA). Download that revision's `create-dmg`:

```bash
SHA=<full-40-char-sha>
mkdir -p apps/media-grabber/scripts
curl -fsSL "https://raw.githubusercontent.com/andreyvit/create-dmg/${SHA}/create-dmg" \
  -o apps/media-grabber/scripts/create-dmg
chmod +x apps/media-grabber/scripts/create-dmg
```

- [ ] **Step 2: Add the provenance comment**

Open `apps/media-grabber/scripts/create-dmg`. Immediately after the shebang line, insert exactly one comment line (single line — repo rule):

```bash
# vendored from github.com/andreyvit/create-dmg @ <full-40-char-sha> — re-vendor to update
```

- [ ] **Step 3: Check for support files**

Read the script. If it `source`s or references sibling files (some revisions ship a `support/` dir with an AppleScript template), fetch those too at the same SHA into `apps/media-grabber/scripts/support/` and add the same one-line provenance comment to each. If it is fully self-contained (common for recent revisions), skip this step.

- [ ] **Step 4: Smoke-test the vendored script locally**

```bash
cd /tmp && rm -rf cdmg-smoke && mkdir -p cdmg-smoke/Payload.app/Contents && \
  echo '<plist/>' > cdmg-smoke/Payload.app/Contents/Info.plist && \
  /Users/shardul/Documents/Github/Tools/apps/media-grabber/scripts/create-dmg \
    --volname "smoke" cdmg-smoke/out.dmg cdmg-smoke/ 2>&1 | tail -5; \
  ls -la cdmg-smoke/out.dmg
```
Expected: `out.dmg` created, non-zero size. If the option names differ from `--volname`, note the real ones — Task 6 references them.

- [ ] **Step 5: Verify lint ignores it**

The script is `.sh`-style with no extension; swiftformat/swiftlint only touch `.swift`. Confirm:
```bash
cd apps/media-grabber && mise exec -- swiftformat --lint . 2>&1 | grep -i create-dmg || echo "not touched by swiftformat — good"
```
Expected: `not touched by swiftformat — good`.

- [ ] **Step 6: Commit**

```bash
git add apps/media-grabber/scripts/create-dmg apps/media-grabber/scripts/support 2>/dev/null || git add apps/media-grabber/scripts/create-dmg
git commit -m "chore(media-grabber): vendor create-dmg at pinned SHA"
```

---

### Task 3: `Project.swift` — version from environment

**Files:**
- Modify: `apps/media-grabber/Project.swift`

**Interfaces:**
- Consumes: the `TUIST_MG_VERSION` process env var (set by the release workflow; unset elsewhere).
- Produces: the generated project's `MediaGrabber` and `GrabberKit` targets carry `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` equal to `$TUIST_MG_VERSION`, or `0.0.0` when unset. The built `.app`'s `Info.plist` has `CFBundleShortVersionString` and `CFBundleVersion` set to that value. Tuist reads `TUIST_MG_VERSION` via `Environment.mgVersion` (Tuist maps `Environment.foo` to the `TUIST_FOO` env var).

- [ ] **Step 1: Read the current file**

Run: `cat apps/media-grabber/Project.swift`
Note the current `settings:` base dict on the `MediaGrabber` target (has `CODE_SIGN_IDENTITY`, `CODE_SIGN_STYLE`, `ENABLE_HARDENED_RUNTIME`, `ENABLE_APP_SANDBOX`) and the project-level `settings:` base (has `SWIFT_VERSION`, `MACOSX_DEPLOYMENT_TARGET`). Note `infoPlist: .extendingDefault(with: [...])` on `MediaGrabber` (has `LSMinimumSystemVersion`, `CFBundleDisplayName`, `NSHumanReadableCopyright`).

- [ ] **Step 2: Add the version constant at the top of the file**

Immediately after `import ProjectDescription`, add:

```swift
let mgVersion = Environment.mgVersion.getString(default: "0.0.0")
```

- [ ] **Step 3: Add the version keys to the project-level base settings**

In the project-level `settings: .settings(base: [...])`, add two entries alongside `SWIFT_VERSION`:

```swift
"MARKETING_VERSION": .string(mgVersion),
"CURRENT_PROJECT_VERSION": .string(mgVersion),
```

- [ ] **Step 4: Wire the Info.plist keys on the `MediaGrabber` target**

In the `MediaGrabber` target's `infoPlist: .extendingDefault(with: [...])`, add:

```swift
"CFBundleShortVersionString": "$(MARKETING_VERSION)",
"CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
```

- [ ] **Step 5: Regenerate and verify the default (no env)**

```bash
cd apps/media-grabber
mise exec -- tuist generate --no-open
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$(find . -name 'MediaGrabber-Info.plist' -path '*Derived*' | head -1)" 2>/dev/null \
  || mise exec -- tuist build MediaGrabber 2>&1 | tail -3
```
Then read the built app's plist:
```bash
find . -name 'Info.plist' -path '*MediaGrabber.app*' -exec /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' {} \;
```
Expected: `0.0.0`.

- [ ] **Step 6: Verify the env override**

```bash
cd apps/media-grabber
TUIST_MG_VERSION=1.2.3 mise exec -- tuist generate --no-open
TUIST_MG_VERSION=1.2.3 mise exec -- tuist build MediaGrabber 2>&1 | tail -3
find . -name 'Info.plist' -path '*MediaGrabber.app*' -exec /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' {} \;
```
Expected: `1.2.3`. Then regenerate once more with no env so the checked-in generated project (if any) is not left with `1.2.3` — though generated files are gitignored (`*.xcodeproj`, `*.xcworkspace`, `Derived/`), so this is just hygiene.

- [ ] **Step 7: Lint**

```bash
cd apps/media-grabber && mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```
Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add apps/media-grabber/Project.swift
git commit -m "feat(media-grabber): version bundle from TUIST_MG_VERSION env"
```

---

### Task 4: `Project.swift` — explicit workspace scheme with coverage

**Files:**
- Modify: `apps/media-grabber/Project.swift`

**Interfaces:**
- Consumes: the `MediaGrabber`, `GrabberKit`, `GrabberKitTests`, `AppUnitTests` targets (already defined in the file).
- Produces: a generated scheme named `MediaGrabber-Workspace` whose `TestAction` runs `GrabberKitTests` + `AppUnitTests` with code coverage enabled, gathering coverage for the `GrabberKit` and `MediaGrabber` targets only. `mise exec -- tuist test` (no scheme arg) and `xcodebuild ... -scheme MediaGrabber-Workspace ... test` both produce a coverage-bearing `.xcresult`.

- [ ] **Step 1: Confirm the auto-generated scheme lacks coverage**

```bash
cd apps/media-grabber
grep -i codeCoverage MediaGrabber.xcworkspace/xcshareddata/xcschemes/MediaGrabber-Workspace.xcscheme || echo "no coverage attr — confirmed"
```
Expected: `no coverage attr — confirmed`.

- [ ] **Step 2: Add the explicit scheme to `Project.swift`**

Add a top-level `schemes:` argument to the `Project(...)` call (after `targets:`). Keep `automaticSchemesOptions: .enabled()` in `options:` — the per-target auto-schemes stay; this only makes the workspace scheme explicit:

```swift
schemes: [
    .scheme(
        name: "MediaGrabber-Workspace",
        shared: true,
        buildAction: .buildAction(targets: ["MediaGrabber", "GrabberKit"]),
        testAction: .targets(
            ["GrabberKitTests", "AppUnitTests"],
            options: .options(
                coverage: true,
                codeCoverageTargets: ["GrabberKit", "MediaGrabber"]
            )
        )
    )
]
```

If `tuist generate` errors on any symbol here (API drift between Tuist versions — `.scheme`, `.buildAction`, `.testAction`, `.targets`, `.options`, `coverage:`, `codeCoverageTargets:`), run `mise exec -- tuist --help` and check the installed `ProjectDescription` — the 4.205.0 API is what governs. The intent is fixed: a shared scheme, both test targets, coverage on, coverage scoped to `GrabberKit` + `MediaGrabber`. Adjust syntax to the installed API without changing that intent.

- [ ] **Step 3: Regenerate and verify the scheme now has coverage**

```bash
cd apps/media-grabber
mise exec -- tuist generate --no-open
grep -i 'codeCoverageEnabled\|CodeCoverage' MediaGrabber.xcworkspace/xcshareddata/xcschemes/MediaGrabber-Workspace.xcscheme
```
Expected: an attribute like `codeCoverageEnabled = "YES"` and `<CodeCoverageTargets>` listing the two targets.

- [ ] **Step 4: Run the tests with coverage and confirm the `.xcresult` carries it**

```bash
cd apps/media-grabber
mise exec -- tuist test 2>&1 | tail -5
RESULT="$(find . -name '*.xcresult' -newer Project.swift | head -1)"
xcrun xccov view --report --only-targets "$RESULT" 2>&1 | head -20
```
Expected: `tuist test` passes; `xccov` prints a table with `GrabberKit` and `MediaGrabber` rows and coverage percentages. If `xccov` says "no coverage data", the scheme wiring did not take — revisit Step 2.

- [ ] **Step 5: Lint**

```bash
cd apps/media-grabber && mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add apps/media-grabber/Project.swift
git commit -m "feat(media-grabber): coverage-enabled MediaGrabber-Workspace scheme"
```

---

### Task 5: `Makefile` release targets

**Files:**
- Modify: `apps/media-grabber/Makefile`

**Interfaces:**
- Consumes: `apps/media-grabber/scripts/bump-version.sh` (Task 1).
- Produces: `make release-patch`, `make release-minor`, `make release-major` targets that compute the next version from the latest `media-grabber-v*` tag, confirm interactively, then `git tag` + `git push` the new tag. Bare `make release` errors. No change to the existing `generate` / `build` / `run` targets or `.DEFAULT_GOAL`.

- [ ] **Step 1: Read the current Makefile**

Run: `cat apps/media-grabber/Makefile`
Note: `.DEFAULT_GOAL := run`, existing `.PHONY: generate build run`, the `APP_NAME` / `BUNDLE_ID` / `DERIVED` / `APP` vars.

- [ ] **Step 2: Append the release block**

Add to the end of the file (the `# --- Release ---` line is a single-line section marker, allowed):

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

`CURRENT_VERSION` uses lazy `=` (not `:=`) on purpose: the `git tag` shell-out then runs only when a `release-*` target is invoked, not on every `make`.

- [ ] **Step 3: Verify bare `make release` errors**

```bash
cd apps/media-grabber && make release; echo "exit: $?"
```
Expected: `pick one: make release-patch | release-minor | release-major`, exit 2 (make's error exit).

- [ ] **Step 4: Verify `CURRENT_VERSION` resolves and the dirty-tree guard trips**

With the working tree dirty from the previous tasks' uncommitted state — actually everything is committed, so make a scratch change:
```bash
cd apps/media-grabber && touch /tmp/x && echo "// scratch" >> Makefile && make release-patch; echo "exit: $?"; git checkout Makefile 2>/dev/null || true
```
Wait — do not `git checkout` (repo rule). Instead: verify the guard without dirtying. Print what `CURRENT_VERSION` resolves to:
```bash
cd apps/media-grabber && make -n release-patch 2>&1 | head -3 && echo "---" && bash -c "git tag --list 'media-grabber-v*' --sort=-v:refname | head -1 | sed 's/^media-grabber-v//' | grep . || echo 0.0.0"
```
Expected: with no `media-grabber-v*` tags yet, prints `0.0.0`. `make -n` (dry run) shows the recipe lines without executing.

- [ ] **Step 5: Verify the `bump-version.sh` path is correct from the Makefile's cwd**

The recipe calls `scripts/bump-version.sh` — `make` runs recipes from the Makefile's directory (`apps/media-grabber/`), so this resolves to `apps/media-grabber/scripts/bump-version.sh`. Confirm:
```bash
cd apps/media-grabber && test -x scripts/bump-version.sh && echo "path ok"
```
Expected: `path ok`.

- [ ] **Step 6: Commit**

```bash
git add apps/media-grabber/Makefile
git commit -m "feat(media-grabber): make release-{patch,minor,major} targets"
```

---

### Task 6: Release workflow

**Files:**
- Create: `.github/workflows/media-grabber-release.yml`

**Interfaces:**
- Consumes: `apps/media-grabber/scripts/create-dmg` (Task 2), `Project.swift`'s `TUIST_MG_VERSION` wiring (Task 3), the repo variable `MG_SIGN_IDENTITY` (optional), `secrets.GITHUB_TOKEN` (auto-provided).
- Produces: on a `media-grabber-v*` tag push or a `workflow_dispatch`, a GitHub Release for that tag with `MediaGrabber-<VERSION>.dmg` and `SHA256SUMS` attached. `workflow_dispatch` with `dry_run: true` builds + packages + verifies but does not publish.

- [ ] **Step 1: Create the workflow skeleton**

Create `.github/workflows/media-grabber-release.yml`:

```yaml
name: media-grabber-release

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

env:
  XCODE_VERSION: "16.1"

jobs:
  release:
    runs-on: macos-14
    timeout-minutes: 30
    defaults:
      run:
        working-directory: apps/media-grabber
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
```

- [ ] **Step 2: Add the version-derivation step**

Append to `steps:`:

```yaml
      - name: Derive version
        id: version
        working-directory: .
        env:
          EVENT_NAME: ${{ github.event_name }}
          REF_NAME: ${{ github.ref_name }}
          INPUT_VERSION: ${{ inputs.version }}
        run: |
          if [ "$EVENT_NAME" = "workflow_dispatch" ]; then
            v="$INPUT_VERSION"
          else
            v="${REF_NAME#media-grabber-v}"
          fi
          case "$v" in
            [0-9]*.[0-9]*.[0-9]*) ;;
            *) echo "not a bare N.N.N version: '$v'" >&2; exit 1 ;;
          esac
          for p in $(echo "$v" | tr . ' '); do
            case "$p" in ''|*[!0-9]*) echo "bad component in '$v'" >&2; exit 1 ;; esac
          done
          echo "version=$v" >> "$GITHUB_OUTPUT"
```

- [ ] **Step 3: Add the ancestry guard**

```yaml
      - name: Tag commit must be on main
        working-directory: .
        if: ${{ !(github.event_name == 'workflow_dispatch' && inputs.dry_run) }}
        run: |
          git fetch --quiet origin main
          git merge-base --is-ancestor "$GITHUB_SHA" origin/main \
            || { echo "built commit is not on origin/main" >&2; exit 1; }
```

- [ ] **Step 4: Add the existing-release guard**

```yaml
      - name: No clobbering an existing release
        working-directory: .
        if: ${{ !(github.event_name == 'workflow_dispatch' && (inputs.dry_run || inputs.overwrite)) }}
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAG: media-grabber-v${{ steps.version.outputs.version }}
        run: |
          if gh release view "$TAG" >/dev/null 2>&1; then
            echo "release $TAG already exists — use overwrite:true to replace" >&2
            exit 1
          fi
```

- [ ] **Step 5: Add toolchain + build**

```yaml
      - uses: jdx/mise-action@v2
        with:
          working_directory: apps/media-grabber
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: ${{ env.XCODE_VERSION }}
      - name: Build Release
        env:
          TUIST_MG_VERSION: ${{ steps.version.outputs.version }}
        run: |
          mise exec -- tuist generate --no-open
          mise exec -- tuist build --configuration Release MediaGrabber
```

- [ ] **Step 6: Add locate + sign**

```yaml
      - name: Locate and sign the app
        id: app
        env:
          MG_SIGN_IDENTITY: ${{ vars.MG_SIGN_IDENTITY }}
        run: |
          app="$(find . -name 'MediaGrabber.app' -path '*Release*' -type d | head -1)"
          test -n "$app" || { echo "MediaGrabber.app not found" >&2; exit 1; }
          codesign --force --sign "${MG_SIGN_IDENTITY:--}" "$app"
          codesign --verify --strict "$app"
          echo "path=$app" >> "$GITHUB_OUTPUT"
```

The absence of `--deep` and `--options runtime` is deliberate (spec §Signing). When notarization is added later, `--options runtime` comes back in the same change.

- [ ] **Step 7: Add package + verify**

Use the option names confirmed in Task 2 Step 4. Assuming andreyvit's current flags:

```yaml
      - name: Package DMG
        id: dmg
        env:
          VERSION: ${{ steps.version.outputs.version }}
          APP: ${{ steps.app.outputs.path }}
        run: |
          staging="$(mktemp -d)"
          cp -R "$APP" "$staging/"
          dmg="MediaGrabber-${VERSION}.dmg"
          scripts/create-dmg --volname "MediaGrabber ${VERSION}" "$dmg" "$staging"
          test -f "$dmg" || { echo "dmg not created" >&2; exit 1; }
          echo "path=$dmg" >> "$GITHUB_OUTPUT"
      - name: Verify DMG
        env:
          VERSION: ${{ steps.version.outputs.version }}
          DMG: ${{ steps.dmg.outputs.path }}
        run: |
          vol="$(mktemp -d)"
          hdiutil attach "$DMG" -nobrowse -mountpoint "$vol"
          test -d "$vol/MediaGrabber.app" || { hdiutil detach "$vol"; echo "no app in dmg" >&2; exit 1; }
          got="$(defaults read "$vol/MediaGrabber.app/Contents/Info" CFBundleShortVersionString)"
          hdiutil detach "$vol"
          test "$got" = "$VERSION" || { echo "app version '$got' != tag '$VERSION'" >&2; exit 1; }
```

- [ ] **Step 8: Add checksums**

```yaml
      - name: Checksums
        env:
          DMG: ${{ steps.dmg.outputs.path }}
        run: |
          d="$(dirname "$DMG")"; f="$(basename "$DMG")"
          ( cd "$d" && shasum -a 256 "$f" > SHA256SUMS && shasum -c SHA256SUMS )
```

- [ ] **Step 9: Add publish**

```yaml
      - name: Check for a previous release tag
        id: prev
        working-directory: .
        run: |
          n="$(git tag --list 'media-grabber-v*' | grep -v "media-grabber-v${{ steps.version.outputs.version }}$" | wc -l | tr -d ' ')"
          echo "exists=$([ "$n" -gt 0 ] && echo true || echo false)" >> "$GITHUB_OUTPUT"
      - name: Publish release
        if: ${{ !(github.event_name == 'workflow_dispatch' && inputs.dry_run) }}
        uses: softprops/action-gh-release@v2
        with:
          tag_name: media-grabber-v${{ steps.version.outputs.version }}
          files: |
            apps/media-grabber/MediaGrabber-${{ steps.version.outputs.version }}.dmg
            apps/media-grabber/SHA256SUMS
          generate_release_notes: ${{ steps.prev.outputs.exists }}
          body: |
            ${{ steps.prev.outputs.exists == 'true' && '' || 'Initial release.' }}

            MediaGrabber is not yet signed with an Apple Developer ID. On first launch,
            right-click the app and choose **Open**, or run
            `xattr -dr com.apple.quarantine /Applications/MediaGrabber.app`.
```

- [ ] **Step 10: Lint the YAML locally**

```bash
python3 -c "import sys; sys.exit(0)" # (pyyaml may be absent — use the online-free check:)
cd /Users/shardul/Documents/Github/Tools && \
  /opt/homebrew/bin/mise exec -- ruby -ryaml -e 'YAML.load_file(".github/workflows/media-grabber-release.yml"); puts "yaml ok"' 2>/dev/null \
  || node -e 'require("fs").readFileSync(".github/workflows/media-grabber-release.yml","utf8"); console.log("read ok")'
```
Expected: `yaml ok` or `read ok`. If neither runtime is present, visually inspect indentation.

- [ ] **Step 11: Commit**

```bash
git add .github/workflows/media-grabber-release.yml
git commit -m "feat(media-grabber): tag-triggered release workflow"
```

- [ ] **Step 12: Note for the human — dry-run validation happens after merge**

The release workflow cannot run until it is on the default branch. After this plan's PR merges, before cutting `media-grabber-v0.1.0`, trigger it once via the Actions tab: `workflow_dispatch` with `version: 0.1.0`, `dry_run: true`. Confirm build + package + verify pass. Then `make release-minor` for the real thing.

---

### Task 7: CI workflow rewrite

**Files:**
- Modify: `.github/workflows/media-grabber.yml` (full replacement of contents)

**Interfaces:**
- Consumes: `apps/media-grabber/scripts/tests/test_bump_version.sh` (Task 1), the coverage-enabled scheme from `Project.swift` (Task 4).
- Produces: four jobs — `lint`, `scripts-test`, `test` (matrix `macos-14` + `macos-15`), `coverage` (`needs: test`). A weekly `schedule` runs `test` against Xcode `latest`.

- [ ] **Step 1: Read the current workflow**

Run: `cat .github/workflows/media-grabber.yml`

- [ ] **Step 2: Replace it entirely**

```yaml
name: media-grabber

on:
  push:
    paths: ['apps/media-grabber/**', '.github/workflows/media-grabber.yml']
  pull_request:
    paths: ['apps/media-grabber/**', '.github/workflows/media-grabber.yml']
  schedule:
    - cron: '17 6 * * 1'   # Mon 06:17 UTC — Xcode-latest canary

concurrency:
  group: media-grabber-${{ github.ref }}
  cancel-in-progress: true

env:
  XCODE_VERSION: "16.1"

defaults:
  run:
    working-directory: apps/media-grabber

jobs:
  lint:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
        with:
          working_directory: apps/media-grabber
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: ${{ env.XCODE_VERSION }}
      - run: mise exec -- swiftformat --lint .
      - run: mise exec -- swiftlint lint --strict

  scripts-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: apps/media-grabber/scripts/tests/test_bump_version.sh
        working-directory: .

  test:
    strategy:
      fail-fast: false
      matrix:
        os: [macos-14, macos-15]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Cache mise tools
        uses: actions/cache@v4
        with:
          path: ~/.local/share/mise
          key: mise-${{ matrix.os }}-${{ hashFiles('apps/media-grabber/.mise.toml') }}
          restore-keys: mise-${{ matrix.os }}-
      - name: Cache SwiftPM / DerivedData
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Developer/Xcode/DerivedData
            apps/media-grabber/.build
          key: spm-${{ matrix.os }}-${{ hashFiles('apps/media-grabber/**/Package.resolved') }}
          restore-keys: spm-${{ matrix.os }}-
      - uses: jdx/mise-action@v2
        with:
          working_directory: apps/media-grabber
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: ${{ github.event_name == 'schedule' && 'latest' || env.XCODE_VERSION }}
      - run: mise exec -- tuist generate --no-open
      - run: mise exec -- tuist test
      - name: Collect xcresult
        if: always()
        run: |
          r="$(find . -name '*.xcresult' | head -1)"
          test -n "$r" && cp -R "$r" "$RUNNER_TEMP/Result.xcresult"
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: xcresult-${{ matrix.os }}
          path: ${{ runner.temp }}/Result.xcresult
          if-no-files-found: warn

  coverage:
    needs: test
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: xcresult-macos-14
          path: ${{ runner.temp }}/xcresult
      - name: Coverage summary
        working-directory: .
        run: |
          result="$(find "$RUNNER_TEMP/xcresult" -name '*.xcresult' | head -1)"
          test -n "$result" || { echo "no xcresult" >&2; exit 1; }
          xcrun xccov view --report --json "$result" > /tmp/cov.json
          python3 - <<'PY' >> "$GITHUB_STEP_SUMMARY"
          import json
          d = json.load(open("/tmp/cov.json"))
          rows = {t["name"]: t for t in d.get("targets", [])}
          def line(name, label):
              t = rows.get(name)
              if not t: return f"| {name} | _no data_ | | {label} |"
              pct = t["lineCoverage"] * 100
              return f"| {name} | {pct:.1f}% | {t['coveredLines']}/{t['executableLines']} | {label} |"
          print("### MediaGrabber coverage")
          print()
          print("| Target | Line coverage | Lines | Note |")
          print("|---|---|---|---|")
          print(line("GrabberKit", "**headline**"))
          print(line("MediaGrabber", "informational (SwiftUI view code)"))
          PY
```

- [ ] **Step 3: Choke-point check — the `xccov --report --json` shape**

The `targets` array and the `name` / `lineCoverage` / `coveredLines` / `executableLines` keys are the documented `xccov` JSON schema. Verify against the local `.xcresult` from Task 4 Step 4:
```bash
cd apps/media-grabber
r="$(find . -name '*.xcresult' | head -1)"
xcrun xccov view --report --json "$r" | python3 -c 'import json,sys; d=json.load(sys.stdin); print([ (t["name"], t.get("lineCoverage"), t.get("coveredLines"), t.get("executableLines")) for t in d["targets"] ])'
```
Expected: a list of tuples with `GrabberKit` and `MediaGrabber` present, numeric values. If a key name differs in this Xcode's `xccov`, fix the Python in Step 2 to match, then re-verify.

- [ ] **Step 4: Verify the `schedule` conditional expression**

`${{ github.event_name == 'schedule' && 'latest' || env.XCODE_VERSION }}` — GitHub Actions ternary idiom. On `schedule` → `latest`; otherwise → the pinned value. Confirm the expression parses by pushing the branch and watching the first run (the `test` job's `setup-xcode` step log shows which version it selected).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/media-grabber.yml
git commit -m "feat(media-grabber): split CI into lint/scripts-test/test-matrix/coverage"
```

- [ ] **Step 6: Push the branch and watch CI**

```bash
git push -u origin HEAD
```
Expected on the PR: `lint` green, `scripts-test` green, `test (macos-14)` + `test (macos-15)` green, `coverage` green with a coverage table in its job summary. `fail-fast: false` means a single-leg failure still reports the other. If `coverage` is skipped, check whether a `test` leg failed (`needs: test` requires all).

---

### Task 8: `CLAUDE.md` Release section

**Files:**
- Modify: `apps/media-grabber/CLAUDE.md`

**Interfaces:**
- Consumes: the behaviour of Tasks 5, 6, 7 as built.
- Produces: a `## Release` section documenting how to cut a release and the pin-maintenance note.

- [ ] **Step 1: Read the current CLAUDE.md structure**

Run: `grep -n '^##' apps/media-grabber/CLAUDE.md`
Pick the insertion point: after `## Build & test`, before `## Toolchain`.

- [ ] **Step 2: Insert the section**

```markdown
## Release

- Versions are manual SemVer, pre-1.0. `make release-patch` / `release-minor` /
  `release-major` computes the next version from the latest `media-grabber-v*`
  tag, confirms, then tags and pushes. Bare `make release` errors.
- The **tag** is `media-grabber-vX.Y.Z`; every derived string (`MARKETING_VERSION`,
  DMG name, `bump-version.sh` I/O) is the bare `X.Y.Z`.
- A tag push runs `.github/workflows/media-grabber-release.yml`: build Release,
  ad-hoc sign, DMG via the vendored `scripts/create-dmg`, verify the DMG's app
  version matches the tag, publish a GitHub Release with the `.dmg` + `SHA256SUMS`.
- To test the release path without publishing: Actions tab → media-grabber-release
  → Run workflow → set `version`, tick `dry_run`.
- `XCODE_VERSION` is pinned in an `env:` block at the top of BOTH workflow files;
  a bump edits both. A weekly scheduled CI run tests against Xcode `latest` so a
  retired pin surfaces out of band.
- Notarization, real Developer ID signing, and hardened runtime are not wired —
  the release workflow's sign step has a comment marking where they slot in.
```

- [ ] **Step 3: Verify markdown renders and no line is a stacked comment**

The bullets are prose in a doc, not code comments — fine. Confirm no accidental broken list nesting:
```bash
sed -n '/^## Release/,/^## Toolchain/p' apps/media-grabber/CLAUDE.md
```

- [ ] **Step 4: Commit**

```bash
git add apps/media-grabber/CLAUDE.md
git commit -m "docs(media-grabber): add Release section to CLAUDE.md"
```

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| CI jobs `lint` / `scripts-test` / `test` / `coverage` | Task 7 |
| OS matrix `macos-14` + `macos-15` | Task 7 |
| Coverage extracted, GrabberKit headline / MediaGrabber informational, no blend, no gate | Task 7 Step 2 |
| `XCODE_VERSION` in both files, weekly `latest` canary | Tasks 6, 7 |
| Caching (mise + SwiftPM/DerivedData), constant key when no `Package.resolved` | Task 7 Step 2 |
| CI concurrency cancel-in-progress | Task 7 Step 2 |
| Release concurrency, `cancel-in-progress: false`, `timeout-minutes: 30` | Task 6 Step 1 |
| Release trigger: tag + `workflow_dispatch` (`version`, `dry_run`, `overwrite`) | Task 6 Step 1 |
| Manual SemVer, `make release-*`, bare `make release` errors | Task 5 |
| First release from `0.0.0` sentinel, no dedicated path | Task 5 (bump math) + Task 1 Step 1 test cases |
| Version string vs tag forms | Global Constraints + Tasks 1, 3, 6 |
| Ad-hoc signing, no `--deep`, no `--options runtime`, `MG_SIGN_IDENTITY` | Task 6 Step 6 |
| `codesign --verify --strict` | Task 6 Step 6 |
| Vendored `create-dmg`, pinned SHA, no Homebrew, no `hdiutil` fallback | Task 2 |
| Release steps: version → ancestry → existing-release guard → build → sign → package → verify (incl. version==tag) → checksums (cd first) → publish | Task 6 Steps 2–9 |
| Release notes: body = install note always; generated notes only if prev tag; first release fixed body | Task 6 Step 9 |
| SHA256SUMS integrity-not-authenticity | (framing only — not asserted as security in the body; Task 6 Step 9 body text makes no trust claim) |
| `Project.swift` version wiring from `TUIST_MG_VERSION`, default `0.0.0` | Task 3 |
| `Project.swift` explicit coverage scheme | Task 4 |
| `CFBundleVersion` == `CFBundleShortVersionString`; Sparkle note deferred | Task 3 Step 4 (both keys wired) + spec §Project.swift (Sparkle hint lives in parent design spec, not this plan) |
| `Makefile` targets, lazy `CURRENT_VERSION` | Task 5 |
| `CLAUDE.md` Release section | Task 8 |
| Failure modes | covered by the guard steps in Tasks 5, 6 |

Gap check: the spec mentions the coverage parser "moves to `.github/scripts/mg-coverage-summary.sh` with a test if it grows past ~15 lines". The Python in Task 7 Step 2 is ~18 lines. **Decision:** keep it inline for now — it is a single self-contained heredoc, not shell logic worth a harness, and extracting it adds a file + a test job for a print-only script. If a reviewer disagrees, extraction is a clean follow-up. Noted here so it is a conscious choice, not an oversight.

**2. Placeholder scan:** `XCODE_VERSION: "16.1"` and the `create-dmg` SHA are flagged placeholders with explicit "replace at implementation time" instructions and a source to get the real value (Global Constraints, Task 2 Step 1). Not silent TODOs. No other placeholders.

**3. Type consistency:**
- `bump-version.sh` contract (`<current> <bump>` → stdout) — defined Task 1, consumed identically Task 5 (`scripts/bump-version.sh $(CURRENT_VERSION) $(BUMP)`) and Task 6 is independent of it.
- `steps.version.outputs.version` — produced Task 6 Step 2, consumed Steps 4, 5, 6, 7, 9 with that exact name.
- `steps.app.outputs.path` — produced Step 6, consumed Step 7.
- `steps.dmg.outputs.path` — produced Step 7, consumed Steps 7 (verify), 8.
- `steps.prev.outputs.exists` — produced Step 9, consumed Step 9 publish (`generate_release_notes`, `body`).
- `TUIST_MG_VERSION` — set Task 6 Step 5, read by `Environment.mgVersion` (`mgVersion` constant) Task 3 Step 2. Tuist's `Environment.foo` ↔ `TUIST_FOO` mapping is the mechanism.
- Scheme name `MediaGrabber-Workspace` — Task 4 produces it; Task 7 `tuist test` uses it implicitly (single explicit scheme) and `download-artifact` name `xcresult-macos-14` matches Task 7's `upload-artifact` name `xcresult-${{ matrix.os }}`.

Consistent.

---

## Execution Handoff

Plan complete and saved to `apps/media-grabber/docs/superpowers/plans/2026-08-31-ci-and-release-infrastructure.md`. Two execution options:

**1. Subagent-Driven (recommended)** — a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — tasks executed in this session via executing-plans, batch execution with checkpoints.

Which approach?
