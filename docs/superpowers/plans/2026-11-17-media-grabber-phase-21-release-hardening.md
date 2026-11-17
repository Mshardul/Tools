# Release Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A release is published only after the built, signed app has proved, on a Mac with nothing else installed, that it downloads, extracts audio, starts its sign-in helper, uninstalls cleanly and updates itself, and the app states every license it ships under.

**Architecture:** A `LicenseCatalog` in GrabberKit feeds a Licenses pane; `fetch-tools.sh` copies each license text into `Resources/Licenses`. A new `E2ETests` target drives the built app's bundled tools and helper through GrabberKit with a temporary home. An update script runs Sparkle against a local appcast. The release workflow gates on both.

**Tech Stack:** Swift 6, XCTest, Tuist, shell, GitHub Actions on macos-15.

**Spec:** `docs/superpowers/specs/2026-11-17-media-grabber-phase-21-release-hardening-design.md`

Written before the repository split (Phase 20). Tasks 1 and 2 do not depend on it; Tasks 3, 6 and 7 name the current workflow, feed and repository and are rewritten against the new repository once the split lands.

All paths are relative to `apps/media-grabber/` unless they start with `docs/` or `.github/`.

## Global Constraints

- Apple Silicon only; deployment target macOS 14.0; ad-hoc signing.
- Build, test and lint only through `make`; `mise exec -- tuist generate --no-open` after adding or removing files.
- Python only from `/Users/shardul/Documents/Github/Tools/.venv/bin/python`.
- Comments are single-line and explain why only; no `///`; no phase, ticket or spec-section references in code or UI copy.
- User-facing copy is true for the cause, plain and jargon-free; a cause-specific message has a test pinning cause to copy.
- The real Sparkle signing key is never used outside the release workflow.
- Every task ends with `make lint` clean and its tests green; the full `make test` is green before the last task.

## Review Focus

- A bundled tool or the helper that runs on the developer's Mac only because Homebrew or a global Node is on `PATH`.
- A license text that does not match the shipped version of its component.
- An end-to-end case that passes because it fell back to something outside the built app.
- A network case that retries and hides a real regression.
- The update test using the real signing key or the real feed.

---

## Part A: Licenses

### Task 1: License texts shipped in the app

**Files:**

- Create: `scripts/tests/test_licenses.sh`
- Modify: `scripts/fetch-tools.sh`, `scripts/tools.lock`, `Project.swift` (`Resources/Licenses` as a `.folderReference`), `.gitignore`, `Makefile` (`licenses-test`)

**Interfaces:**

- Produces: after `make tools`, `Resources/Licenses/{yt-dlp,ffmpeg,lame,node,shield,sparkle,mediagrabber}.txt`, each non-empty.
- `scripts/tools.lock` gains `license-yt-dlp` and `license-sparkle` lines (`NAME VERSION URL SHA256`) for the two licenses that are not inside a source archive already fetched; the others are copied from the archives the script already unpacks (Node's `LICENSE`, FFmpeg's `COPYING.LGPLv2.1`, LAME's `COPYING`, the helper's `LICENSE`) and from the repository root `LICENSE`.

- [ ] **Step 1: Failing test** `scripts/tests/test_licenses.sh`: runs with `MG_TOOLS_OUT` pointing at a temporary folder holding a pre-seeded `Resources/Licenses` missing `lame.txt`, calls `scripts/check-licenses.sh "$out/Resources/Licenses"`, expects non-zero and the missing name on stderr; then seeds all seven files and expects zero.
- [ ] **Step 2: Run** `make licenses-test`; expected FAIL (script absent).
- [ ] **Step 3: Implement** `scripts/check-licenses.sh <dir>`: for each of the seven names, `test -s "$dir/$name.txt"` or print `missing license: <name>` to stderr and exit 1.
- [ ] **Step 4: Run** `make licenses-test`; expected PASS.
- [ ] **Step 5: Fetch the texts.** In `fetch-tools.sh`, after the archives are unpacked, copy `node/LICENSE`, `ffmpeg-src/COPYING.LGPLv2.1`, `lame-src/COPYING`, `shield-src/LICENSE` and the repository root `LICENSE` into `$out/Resources/Licenses/`; fetch `license-yt-dlp` and `license-sparkle` through the existing checksum-verified `fetch`; fill the lock with the values for the pinned yt-dlp tag and Sparkle 2.7.1 (checksums computed from the downloaded files and recorded in the lock).
- [ ] **Step 6: Wire** `Project.swift` (`.folderReference(path: "Resources/Licenses")`), `.gitignore` (`Resources/Licenses`), and call `check-licenses.sh` at the end of `fetch-tools.sh`.
- [ ] **Step 7: Verify.** `make tools`; `ls Resources/Licenses` shows seven non-empty files; `make lint`.

### Task 2: Licenses pane

**Files:**

- Create: `Sources/GrabberKit/App/LicenseCatalog.swift`, `Sources/App/Preferences/Panes/LicensesPane.swift`, `Tests/GrabberKitTests/LicenseCatalogTests.swift`, `Tests/AppUnitTests/LicensesPaneTests.swift`
- Modify: `Sources/App/Preferences/PreferencesPane.swift`, the Preferences pane router (the view that switches on `PreferencesPane`), `Sources/App/About/AboutView.swift`, `Sources/App/AppModelInstall.swift`

**Interfaces:**

- Produces:
  - `public struct LicenseEntry: Sendable, Equatable { public let name: String; public let license: String; public let summary: String; public let homepage: URL; public let textFile: String }`
  - `public enum LicenseCatalog { public static let entries: [LicenseEntry] }` with one entry per bundled component: yt-dlp, FFmpeg, LAME, Node.js, the sign-in helper, Sparkle, plus MediaGrabber itself first.
  - `PreferencesPane.licenses` in the System group, title "Licenses", subtitle "What MediaGrabber is made of and the license each part comes with."
  - `AppModel.openLicenseText(_ entry: LicenseEntry, in bundle: Bundle)` opening `Licenses/<textFile>` through `openURLSink`.

- [ ] **Step 1: Failing tests** in `LicenseCatalogTests`: `test_everyBundledToolInTheLockHasAnEntry` (reads `scripts/tools.lock` through a path built from `#filePath`, maps lock names `yt-dlp`, `node`, `ffmpeg`, `lame`, `shield-plugin` to catalogue names, and asserts each is present), `test_everyEntryNamesADistinctTextFile`, `test_helperIsListedAsGPL3_andSeparateProgram` (the helper's `license` is "GPL 3.0 only" and its `summary` says it runs as a separate program), `test_appItselfIsListedFirstAsMIT`. In `LicensesPaneTests`: `test_openLicenseText_opensTheBundledFile` (temporary bundle with `Contents/Resources/Licenses/node.txt`; the `FakeOpenURLSink` receives that URL), `test_aboutLicensesRow_selectsTheLicensesPane`.
- [ ] **Step 2: Run** `make test ONLY=GrabberKitTests/LicenseCatalogTests`; expected FAIL (types undefined).
- [ ] **Step 3: Implement** `LicenseCatalog` with the entries from the spec table and the pane: a heading line "MediaGrabber is MIT-licensed. The tools below keep their own licenses.", then one `PrefRow` per entry with name, license, summary and a "Read license" button; use the existing `PrefPaneHeader` and row styles.
- [ ] **Step 4: Wire** the new pane case into the rail and router, change About's "Read licenses" button to set `appModel.page = .preferences(.licenses)`, and delete the `openNotices` method and `Resources/NOTICES.md`, whose content now lives in the catalogue and the license files.
- [ ] **Step 5: Verify.** `make lint`; `make test ONLY=GrabberKitTests`; `make test ONLY=AppUnitTests`; expected green. Run `make` and read the pane in the app.

### Task 3: Source mirrored in every release

**Files:**

- Create: `scripts/mirror-sources.sh`, `scripts/tests/test_mirror_sources.sh`
- Modify: `.github/workflows/media-grabber-release.yml`, `Makefile` (`mirror-test`), `CLAUDE.md` (Release section)

**Interfaces:**

- Produces: `scripts/mirror-sources.sh <out-dir>` downloads the `ffmpeg`, `lame` and `shield-source` entries from `scripts/tools.lock`, verifies each SHA-256, and writes them to `<out-dir>` as `<name>-<version>-source.<ext>`, exiting non-zero on any mismatch and leaving no file behind.

- [ ] **Step 1: Failing test:** with a fixture lock whose second entry has a wrong checksum (`file://` URLs), the script exits non-zero and `<out-dir>` is empty; with correct checksums it writes the files.
- [ ] **Step 2: Run** `make mirror-test`; expected FAIL.
- [ ] **Step 3: Implement** `mirror-sources.sh` reusing the lock format and the checksum check from `fetch-tools.sh`.
- [ ] **Step 4: Workflow.** Before "Publish release", run the script into `release-sources/`, add those files to the `SHA256SUMS` step and to the release's `files:`.
- [ ] **Step 5: Verify.** `make mirror-test`; run the workflow with `dry_run` and read the log: three source files listed with checksums.

## Part B: End-to-end

### Task 4: E2ETests target and `make e2e`

**Files:**

- Create: `Tests/E2ETests/E2EEnvironment.swift`, `Tests/E2ETests/BundledToolsE2ETests.swift`, `scripts/e2e/run.sh`
- Modify: `Project.swift` (target `E2ETests`, unit-test product, depends on `GrabberKit` and `TestSupport`, not part of `MediaGrabber-Workspace`'s default test action), `Makefile` (`e2e`)

**Interfaces:**

- Produces:
  - `struct E2EEnvironment { let app: URL; let home: URL; let tools: ManagedTools; let environment: [String: String]; static func make() throws -> E2EEnvironment }`; `make()` throws `XCTSkip` when `MG_E2E_APP` is unset, creates a temporary home, builds `ManagedTools(resourceRoot: app/Contents/Resources, supportRoot: home/Library/Application Support/MediaGrabber)`, and sets `PATH` to `/usr/bin:/bin` and `HOME` to the temporary home.
  - `E2EEnvironment.retryingOnce<T>(_ body: () async throws -> T) async throws -> T` for the network cases only.
  - `scripts/e2e/run.sh`: builds Release through `make build CONFIG=Release`, signs with `scripts/sign-app.sh`, runs `make test ONLY=E2ETests` with `MG_E2E_APP` set, then runs `make drop-build-app`, exiting with the test status.

- [ ] **Step 1: Failing test** `BundledToolsE2ETests.test_everyBundledToolReportsItsVersion`: for `yt-dlp`, `ffmpeg`, `ffprobe` and `node`, run the tool from `env.tools` with `--version` or `-version` through `ProcessRunner` and assert exit 0 and a non-empty first line.
- [ ] **Step 2: Run** `make test ONLY=E2ETests/BundledToolsE2ETests` with `MG_E2E_APP` unset; expected SKIP, not FAIL. Then `scripts/e2e/run.sh`; expected FAIL until the target and harness exist, PASS after.
- [ ] **Step 3: Implement** the target, `E2EEnvironment` and `run.sh`.
- [ ] **Step 4: Verify.** `make e2e`; expected one passing case on the built app, no build copy left behind (`mdfind 'kMDItemFSName == "MediaGrabber.app"'` lists only `/Applications`).

### Task 5: End-to-end cases

**Files:**

- Create: `Tests/E2ETests/DownloadE2ETests.swift`, `Tests/E2ETests/HelperE2ETests.swift`, `Tests/E2ETests/EnvironmentIsolationE2ETests.swift`, `Tests/E2ETests/UninstallE2ETests.swift`

**Interfaces:**

- Consumes: `E2EEnvironment` (Task 4); `CanaryProbe`, `DownloadEngine` with live dependencies, `PotPluginInstaller`, `AppFootprint`, `Persistence`.

- [ ] **Step 1: Write the cases, run each to see it fail for the right reason, then make it pass:**
  - `test_setupCheck_passesWithBundledDownloader` (network, retry once): `CanaryProbe.run` with `env.tools.ytDlpURL()` succeeds.
  - `test_videoDownloads_toATemporaryFolder` (network, retry once): submit the canary URL through the live engine with a temporary destination; the output file exists and is larger than zero.
  - `test_audioExtraction_producesM4aAndMp3`: run the bundled `ffmpeg` on a short generated test tone (`-f lavfi -i sine`) to `.m4a` and `.mp3`, then `ffprobe -show_streams` reports an audio stream for each.
  - `test_helper_startsFromTheBundle_andAnswersPing`: `PotPluginInstaller` built with `env.tools` resolves the launch, the process starts on a free port, `/ping` answers within 10 seconds, and the process is stopped in teardown.
  - `test_helper_returnsAToken` (network, retry once): `POST /get_pot` with a content binding returns a non-empty `poToken`.
  - `test_noHomebrewNoNode_firstRunStillWorks`: with `PATH=/usr/bin:/bin`, `EnvironmentProbe(tools: env.tools)` reports `isReadyForDownloads`.
  - `test_updatedDownloader_newerWins_olderIgnored`: write a stub executable to `<support>/bin/yt-dlp` printing a newer, then an older version, and assert `env.tools.ytDlpURL()` each time.
  - `test_oldHomebrewToolsAndOldHelperFolder_areNeverRun`: create executables at `/opt/homebrew/bin`-style paths inside the temporary home and a `bgutil-server/` folder in the support directory that write a marker file when run; after the probe, the download and the helper start, the marker does not exist.
  - `test_uninstall_removesFootprint_keepsDownloads_andDoesNotRecreateQueue`: build the footprint in the temporary home, call `persistence.saveQueue` with a pending write, run `UninstallSequence` with real effects pointed at the temporary home, wait one second, and assert the footprint is gone, `Downloads/clip.mp4` survives and `queue.json` does not exist.
- [ ] **Step 2: Verify.** `make e2e`; expected all cases pass; run it a second time to confirm no leftover processes (`pgrep -f build/main.js` prints nothing).

## Part C: Update path

### Task 6: Sparkle update test

**Files:**

- Create: `scripts/e2e/update-test.sh`
- Modify: `Project.swift` (feed URL read from `TUIST_MG_FEED_URL`, default the real feed), `Makefile` (`update-test`)

**Interfaces:**

- Produces: `scripts/e2e/update-test.sh` builds a version `0.0.1` and a version `0.0.2` of the app with a throwaway EdDSA public key and `TUIST_MG_FEED_URL=http://127.0.0.1:<port>/appcast.xml`, signs the `0.0.2` disk image with the matching private key, writes the appcast with `scripts/appcast.py`, serves both with `python -m http.server`, installs `0.0.1` under the temporary home's `Applications`, triggers a check through the app's update command, and asserts that `CFBundleShortVersionString` of the installed bundle becomes `0.0.2`.

- [ ] **Step 1: Spike (decision point).** Confirm Sparkle can be driven without the UI: try `SPUStandardUpdaterController` with a `-SUAutomaticallyUpdate` user default and `SUFeedURL` from the build, and the app's launch with an automatic-update default written to the temporary home. If automatic install cannot be triggered without clicking, drive the one Sparkle dialog with AppleScript through System Events. Write the chosen method at the top of the script.
- [ ] **Step 2: Failing test:** run the script before the feed override exists; expected FAIL at "feed unreachable".
- [ ] **Step 3: Implement** the feed override in `Project.swift` and the script.
- [ ] **Step 4: Verify.** `make update-test`; expected `0.0.1 -> 0.0.2` printed and exit 0; the real signing key file is never read (`grep -n SPARKLE_EDDSA scripts/e2e/update-test.sh` finds nothing).

## Part D: Gate and docs

### Task 7: Release workflow gate and Review Focus coverage

**Files:**

- Modify: `.github/workflows/media-grabber-release.yml`, `CLAUDE.md`, `docs/development.md`, `docs/architecture.md`
- Create: `docs/release-checklist.md`

- [ ] **Step 1: Workflow.** After "Smoke test bundled tools" add "End-to-end run" executing `MG_E2E_APP="$APP" make test ONLY=E2ETests` on the signed app; it runs on dry runs too. Run the workflow with `dry_run` and read the log: every case listed, none skipped.
- [ ] **Step 2: Checklist.** `docs/release-checklist.md` lists the one remaining manual check from the spec table: the read-only bundle that cannot be moved to the Trash, with the exact steps; the rest are automated.
- [ ] **Step 3: Docs.** `CLAUDE.md` Release section: the end-to-end gate, `make e2e`, `make update-test`; `docs/development.md`: how to run both locally; `docs/architecture.md`: the Licenses catalogue and where license texts live.
- [ ] **Step 4: Verify.** `make lint`; `make test`; `make e2e`; `make update-test`; `make licenses-test mirror-test appcast-test tools-test`; all green.
