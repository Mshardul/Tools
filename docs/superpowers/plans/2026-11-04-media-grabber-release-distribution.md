# Release, Install, Update, Uninstall and Bundled Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A friend downloads one DMG, installs it with Open Anyway, and the app updates itself in place, ships every tool it runs, and removes itself and its data from one Preferences button.

**Architecture:** Sparkle 2 (EdDSA, appcast on GitHub Pages, DMG as the update archive) handles app updates. A `ManagedTools` type resolves every tool to a bundled copy, with an optional newer yt-dlp in Application Support. An `Uninstaller` in GrabberKit deletes a single footprint list. CI builds, signs inside-out, signs the DMG for Sparkle, and publishes release plus appcast.

**Tech Stack:** Swift 6, SwiftUI, Tuist, Sparkle 2.6.4, GitHub Actions on macos-15, shell scripts.

**Spec:** `docs/superpowers/specs/2026-11-04-media-grabber-release-distribution-design.md`

All paths are relative to `apps/media-grabber/` unless they start with `docs/` or `.github/`.

## Global Constraints

- Apple Silicon (arm64) only; deployment target macOS 14.0.
- Ad-hoc signing (`CODE_SIGN_IDENTITY "-"`, hardened runtime off); notarization is not part of this plan.
- Tag `media-grabber-vN.N.N`; bare `N.N.N` is both `CFBundleShortVersionString` and `CFBundleVersion`.
- Feed URL `https://mshardul.github.io/Tools/media-grabber/appcast.xml`; archive is `MediaGrabber-N.N.N.dmg`.
- Release asset names keep the version; the README links to `https://github.com/Mshardul/Tools/releases?q=media-grabber-v`, never `releases/latest`.
- User-facing copy is true for the cause, plain, jargon-free and offers an action; a cause-specific message has a test pinning cause to copy.
- Comments are single-line and explain why only; no `///`; no phase, ticket or spec-section references in code or UI copy.
- Build, test and lint only through `make` (`make test ONLY=Target/Suite`, `make lint`); run `mise exec -- tuist generate --no-open` after adding or removing files.
- Every task ends with `make lint` clean and its tests green; the full `make test` is green before the final task.

## Review Focus

- Running from `~/Downloads` or a mounted DMG (translocated path): update check must be disabled with an explanation, never fail silently.
- Uninstall when a download is mid-flight: the persistence flush must not recreate `queue.json` after deletion.
- Uninstall when the bundle cannot be trashed: data is already gone, the user is told the one remaining step.
- yt-dlp update with a truncated download or wrong checksum: previous working copy stays, no partial file is ever executed.
- yt-dlp update that passes checksum but fails the canary: updated copy is deleted, bundled copy used.
- A Mac with no Homebrew, no Node and no `PATH` entries: first run reaches Home with nothing to install.
- Existing installs that have Homebrew tools and old `~/Library/Application Support/MediaGrabber/bgutil-server`: the app ignores them and never executes them.

---

## Part A: Release, update, install, uninstall

### Task 1: Sparkle updater replaces the notify-only checker

**Files:**

- Create: `Tuist/Package.swift`, `Sources/App/Updates/AppUpdating.swift`, `Sources/App/Updates/SparkleUpdater.swift`, `Tests/AppUnitTests/AppUpdatingTests.swift`
- Modify: `Project.swift` (Sparkle dependency, Info.plist keys), `Sources/App/MediaGrabberApp.swift`, `Sources/App/AppModel.swift`, `Sources/App/About/AboutView.swift`, `Sources/App/Preferences/Panes/UpdatesPane.swift`, `Sources/App/AppModelDialogs.swift`, `Tests/AppUnitTests/AboutViewTests.swift`, `Tests/AppUnitTests/Support/AppModelTestHelpers.swift`, `Tests/AppUnitTests/PasscodeFlowIntegrationTests.swift`
- Delete: `Sources/App/About/AppUpdateChecker.swift`, `Sources/App/AppModelUpdates.swift`, `Tests/AppUnitTests/AppUpdateCheckerTests.swift`, `Tests/AppUnitTests/AppModelUpdatesTests.swift`

**Interfaces:**

- Produces:
  - `@MainActor protocol AppUpdating: AnyObject { var canCheckForUpdates: Bool { get }; var automaticallyChecks: Bool { get set }; func checkForUpdates() }`
  - `@MainActor final class SparkleUpdater: AppUpdating`, wrapping `SPUStandardUpdaterController(startingUpdater: true, ...)`
  - `AppModel.updater: AppUpdating`, injected through `AppModel.init(updater:)`

- [ ] **Step 1: Declare Sparkle.** `Tuist/Package.swift` pins `https://github.com/sparkle-project/Sparkle` exactly `2.6.4`; `Project.swift` adds `.external(name: "Sparkle")` to the `MediaGrabber` target; run `mise exec -- tuist install` then `tuist generate --no-open`.
- [ ] **Step 2: Info.plist.** Add `SUFeedURL` (feed URL above), `SUPublicEDKey` (generate the keypair with Sparkle's `generate_keys`; the public key is committed, the private key goes only into the CI secret `SPARKLE_ED_PRIVATE_KEY` and the login Keychain), `SUEnableAutomaticChecks` `true`, `SUScheduledCheckInterval` `86400`.
- [ ] **Step 3: Write failing tests** in `AppUpdatingTests.swift` with a `FakeUpdater: AppUpdating`: `test_preferenceToggle_drivesUpdaterAutomaticChecks` (setting `prefs.autoCheckAppUpdates = false` sets `updater.automaticallyChecks == false`, and back), `test_aboutCheckButton_callsCheckForUpdates`, `test_aboutCheckButton_disabledWhenUpdaterCannotCheck`.
- [ ] **Step 4: Run** `make test ONLY=AppUnitTests/AppUpdatingTests`; expected FAIL, types undefined.
- [ ] **Step 5: Implement** `AppUpdating`, `SparkleUpdater`, and the wiring: `AppModel` owns `updater`; `MediaGrabberApp` constructs `SparkleUpdater` and adds a "Check for Updates…" command under the app menu; `AboutView` row shows the button and the current version; `UpdatesPane` binds its app toggle to `updater.automaticallyChecks` through `prefs`.
- [ ] **Step 6: Delete** the four files listed, remove `appUpdateChecker`, `checkForAppUpdateOnLaunch`, `AppModelDialogs.updateAvailable`, the `mg.lastPromptedUpdateVersion` key, and every test-helper reference; `AppUpdateStatus` and `GitHubRelease*` no longer exist anywhere.
- [ ] **Step 7: Verify.** `make lint`; `make test ONLY=AppUnitTests`; expected all green. Run `make` and confirm Check for Updates… appears and opens Sparkle's window (it reports "unable to check" until the feed exists, which is correct).

### Task 2: Install-location check and move-to-Applications

**Files:**

- Create: `Sources/App/Updates/InstallLocation.swift`, `Tests/AppUnitTests/InstallLocationTests.swift`
- Modify: `Sources/App/AppModel.swift`, `Sources/App/AppModelDialogs.swift`, `Sources/App/About/AboutView.swift`, `Sources/App/Updates/SparkleUpdater.swift`

**Interfaces:**

- Consumes: `AppRelauncher` (existing, `Sources/App`); `AppUpdating.canCheckForUpdates` (Task 1)
- Produces:
  - `enum InstallLocation { case applications, needsMove(reason: Reason) ; enum Reason { case downloadsOrVolume, translocated } ; static func evaluate(bundleURL: URL, applicationsDirectories: [URL]) -> InstallLocation }`
  - `AppModelDialogs.moveToApplications() -> ConfirmationDialog`
  - `AppModel.offerMoveToApplicationsIfNeeded() async`

- [ ] **Step 1: Failing tests** `test_evaluate_*`: `/Applications/MediaGrabber.app` → `.applications`; `~/Applications/MediaGrabber.app` → `.applications`; `/private/var/folders/x/AppTranslocation/ABC/d/MediaGrabber.app` → `.needsMove(.translocated)`; `/Volumes/MediaGrabber 0.1.0/MediaGrabber.app` and `~/Downloads/MediaGrabber.app` → `.needsMove(.downloadsOrVolume)`.
- [ ] **Step 2: Run** `make test ONLY=AppUnitTests/InstallLocationTests`; expected FAIL.
- [ ] **Step 3: Implement** `evaluate` (string-contains `AppTranslocation`, else prefix match against `applicationsDirectories`).
- [ ] **Step 4: Wire the offer.** On launch, when `.needsMove` and the app is not a debug build, show `moveToApplications()` (copy: "MediaGrabber works best from your Applications folder. Move it there now?", buttons "Move" / "Not now"). "Move" copies the bundle to `/Applications` (replacing a same-named copy after confirming), relaunches from there through `AppRelauncher`, and trashes the original when it is writable. A failed copy shows a plain message with a Reveal in Finder action.
- [ ] **Step 5: Disable updating off-location.** `SparkleUpdater.canCheckForUpdates` is false when `.needsMove`; `AboutView` shows "Move MediaGrabber to your Applications folder to get updates." in that state, with the Move action beside it. Test: `test_aboutShowsMoveHint_whenNeedsMove` in `AboutViewTests`.
- [ ] **Step 6: Verify.** `make lint`; `make test ONLY=AppUnitTests`; expected green.

### Task 3: Uninstall action

**Files:**

- Create: `Sources/GrabberKit/Uninstall/AppFootprint.swift`, `Sources/GrabberKit/Uninstall/Uninstaller.swift`, `Tests/GrabberKitTests/UninstallerTests.swift`, `Tests/AppUnitTests/AppModelUninstallTests.swift`
- Modify: `Sources/GrabberKit/Model/Persistence.swift`, `Sources/App/Preferences/Panes/AdvancedPane.swift`, `Sources/App/AppModelDialogs.swift`, `Sources/App/AppModel.swift`

**Interfaces:**

- Consumes: the persistence protocol in `Persistence.swift` (the one declaring `saveQueue`/`flushNow`)
- Produces:
  - `public enum AppFootprint { public static func directories(home: URL) -> [URL] }` returning exactly: `Library/Application Support/MediaGrabber`, `Library/Logs/MediaGrabber`, `Library/Caches/app.mediagrabber.mac`, `Library/Saved Application State/app.mediagrabber.mac.savedState`
  - `public struct Uninstaller: Sendable { public init(home: URL, bundleURL: URL, removeItem: @escaping @Sendable (URL) throws -> Void, trashItem: @escaping @Sendable (URL) throws -> Void, clearDefaults: @escaping @Sendable (String) -> Void); public func run() -> UninstallOutcome }`
  - `public enum UninstallOutcome: Sendable, Equatable { case removed, dataRemovedBundleRemains }`
  - persistence protocol gains `func disableWrites()`: after it, `saveX` and `flushNow` write nothing
  - `AppModel.uninstall() async`

- [ ] **Step 1: Failing tests** in `UninstallerTests` using a temporary home: `test_removesEveryFootprintDirectory`, `test_leavesSiblingDownloadsUntouched` (a `Downloads/clip.mp4` survives), `test_clearsPreferencesDomain` (`clearDefaults` called with `app.mediagrabber.mac`), `test_trashesBundleLast` (call order: removes, defaults, trash), `test_trashFailure_returnsDataRemovedBundleRemains`.
- [ ] **Step 2: Failing tests** in `AppModelUninstallTests`: `test_confirmDeclined_changesNothing`, `test_confirmAccepted_cancelsDownloads_disablesPersistenceWrites_thenRunsUninstaller_thenTerminates` (assert `disableWrites` precedes the uninstaller and `flushNow` is never called afterwards), `test_activeDownloadsNamedInDialog`.
- [ ] **Step 3: Run** both suites; expected FAIL.
- [ ] **Step 4: Implement** `AppFootprint`, `Uninstaller` (`removeItem` per directory ignoring not-found, then `clearDefaults`, then `trashItem(bundleURL)`), `disableWrites()` on the real persistence class and on `FakePersistence` in `Tests/TestSupport`.
- [ ] **Step 5: Implement the flow.** `AppModelDialogs.uninstall(activeDownloads: Int)`: destructive style, title "Remove MediaGrabber?", message "This removes MediaGrabber and everything it saved. Your downloaded files stay where they are." plus, when `activeDownloads > 0`, "N downloads in progress will be cancelled."; buttons "Remove" / "Cancel". `AppModel.uninstall()`: confirm; cancel all jobs and stop child processes and the sign-in helper; `persistence.disableWrites()`; run `Uninstaller`; on `.removed` terminate immediately without the quit flush; on `.dataRemovedBundleRemains` show "MediaGrabber's data is removed. Drag MediaGrabber from your Applications folder to the Trash to finish." with a Reveal in Finder action.
- [ ] **Step 6: UI.** `AdvancedPane` gets an "Uninstall" `PrefRow` below App data: helper "Removes MediaGrabber and everything it saved.", destructive button "Uninstall…".
- [ ] **Step 7: Verify.** `make lint`; `make test ONLY=GrabberKitTests/UninstallerTests`; `make test ONLY=AppUnitTests/AppModelUninstallTests`; expected green. Do not click Uninstall in the dev build with real data; the temporary-home tests cover it.

### Task 4: Release workflow signs for Sparkle and publishes the appcast

**Files:**

- Create: `scripts/make-appcast.sh`, `scripts/tests/make-appcast-test.sh`
- Modify: `.github/workflows/media-grabber-release.yml`, `Makefile` (target `appcast-test`), `CLAUDE.md` (Release section)

**Interfaces:**

- Produces: `scripts/make-appcast.sh <version> <dmg-path> <ed-signature> <dmg-length> <download-url> <existing-appcast-or-empty>` writing `appcast.xml` to stdout; items newest first, each with `sparkle:version`, `sparkle:shortVersionString`, `sparkle:minimumSystemVersion` `14.0`, `sparkle:releaseNotesLink` set to the GitHub Release page, and an `enclosure` with `sparkle:edSignature` and `length`.

- [ ] **Step 1: Failing test** `scripts/tests/make-appcast-test.sh`: with a fixture existing feed containing 0.1.0, generating 0.2.0 yields two items ordered 0.2.0 then 0.1.0, correct `url`, `length` and signature attributes, and `xmllint --noout` passes.
- [ ] **Step 2: Run** `make appcast-test`; expected FAIL.
- [ ] **Step 3: Implement** `make-appcast.sh` in plain shell with `xmllint`-valid output.
- [ ] **Step 4: Workflow edits.** After "Verify DMG": step "Sign update for Sparkle" runs Sparkle's `sign_update` (fetched at the pinned 2.6.4 tarball) with `SPARKLE_ED_PRIVATE_KEY` from secrets, capturing signature and length; after "Publish release": step "Publish appcast" reads the existing `media-grabber/appcast.xml` from the `gh-pages` branch, runs `make-appcast.sh`, and writes the result back to `media-grabber/appcast.xml` on `gh-pages`. Dry runs skip both publish steps and print the appcast instead.
- [ ] **Step 5: Sign inside-out.** Replace the single `codesign --force` in "Locate and sign the app" with: sign every executable and framework under `Contents/Frameworks`, `Contents/Resources/Tools` (present after Task 7), and `Contents/PlugIns`, then the app; end with `codesign --verify --deep --strict "$app"`.
- [ ] **Step 6: One-time setup (user).** Enable GitHub Pages on the repository from the `gh-pages` branch (create it empty first); add the `SPARKLE_ED_PRIVATE_KEY` secret. The task is not complete until the user confirms both.
- [ ] **Step 7: Verify.** `make appcast-test` passes; run the workflow with `dry_run` and read the log: DMG verified, signature produced, appcast printed, nothing published.
- [ ] **Step 8:** Update `CLAUDE.md` Release section: the appcast, Sparkle key handling, and that notarization remains unwired.

**Release point 1.** After Task 4 the app can be released to technical testers with Homebrew-installed tools, and the loop install → update → uninstall can be run by hand.

---

## Part B: Bundled tools

### Task 5: ManagedTools resolution and a Homebrew-free probe

**Files:**

- Create: `Sources/GrabberKit/Tools/ManagedTools.swift`, `Tests/GrabberKitTests/ManagedToolsTests.swift`
- Modify: `Sources/GrabberKit/Onboarding/EnvironmentProbe.swift`, `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` (line ~143), `Sources/GrabberKit/PotProvider/PotPluginInstaller.swift`, `Sources/App/About/AboutView.swift`, `Sources/App/AppModel.swift`, `Tests/TestSupport/` fakes (`FakeEnvironmentProbe`), every test constructing `EnvironmentReport(brew:...)`

**Interfaces:**

- Produces:
  - `public struct ManagedTools: Sendable { public init(resourceRoot: URL, supportDirectory: URL, versionOf: @escaping @Sendable (URL) -> String?, isExecutable: @escaping @Sendable (URL) -> Bool); public static func live() -> ManagedTools; public var ytDlp: URL?; public var ffmpeg: URL?; public var ffprobe: URL?; public var node: URL?; public var shieldServerEntry: URL?; public var shieldPluginArchive: URL? }`
  - `EnvironmentReport(ytDlp: ToolInfo?, ffmpeg: ToolInfo?, ffprobe: ToolInfo? = nil)`; the `brew` property is gone
  - `EnvironmentProbe.init(runner: ProcessRunning = ProcessRunner(), tools: ManagedTools = .live())`
- `resourceRoot` is `Bundle.main.resourceURL`; tools live at `Tools/<name>`; shield files at `Shield/server/build/main.js` and `Shield/bgutil-plugin.zip`; the updated yt-dlp at `<supportDirectory>/bin/yt-dlp`.

- [ ] **Step 1: Failing tests** (`ManagedToolsTests`): `test_ytDlp_bundledOnly`, `test_ytDlp_updatedNewer_wins`, `test_ytDlp_updatedOlder_bundledWins`, `test_ytDlp_updatedNotExecutable_bundledWins`, `test_ytDlp_updatedUnreadableVersion_bundledWins`, `test_ffmpeg_ignoresSupportDirectoryAndPath`, `test_missingBundle_returnsNil`. Probe tests: `test_probe_reportsBundledVersions`, `test_probe_neverSearchesPath`.
- [ ] **Step 2: Run** `make test ONLY=GrabberKitTests/ManagedToolsTests`; expected FAIL.
- [ ] **Step 3: Implement** `ManagedTools` (version comparison through the existing `DottedVersion`) and reduce `EnvironmentProbe` to ask `ManagedTools` for paths and run `--version` / `-version` through `runner`; delete `defaultSearchPaths`, `locate`, `parseBrew` and the `.local/bin` handling.
- [ ] **Step 4: Fix consumers.** `DownloadEngineProtocol` builds the engine with the new probe; `PotPluginInstaller.live()` takes `ManagedTools` instead of `searchPaths`; update `AboutView`'s `EnvironmentReport(...)` fallback and every fake and test call site.
- [ ] **Step 5: Verify.** `make lint`; `make test ONLY=GrabberKitTests`; `make test ONLY=AppUnitTests`; expected green.

### Task 6: Tool lock file and fetch script

**Files:**

- Create: `scripts/tools.lock`, `scripts/fetch-tools.sh`, `scripts/build-ffmpeg.sh`, `scripts/build-shield.sh`, `scripts/tests/fetch-tools-test.sh`
- Modify: `Makefile` (targets `tools`, `tools-test`), `Project.swift` (`resources:` gains `Resources/Tools/**` and `Resources/Shield/**`), `.gitignore` for `Resources/Tools` and `Resources/Shield` (fetched, never committed)

**Interfaces:**

- Produces: after `make tools`, `Resources/Tools/{yt-dlp,ffmpeg,ffprobe,node}` and `Resources/Shield/{server/build/main.js,server/node_modules,bgutil-plugin.zip}`, each executable ad-hoc signed and runnable with `--version`.
- `scripts/tools.lock` lines: `NAME VERSION URL SHA256`; `fetch-tools.sh` refuses any download whose SHA-256 differs from the lock.

- [ ] **Step 1: Failing test** `fetch-tools-test.sh`: a fixture lock with a deliberately wrong checksum makes `fetch-tools.sh` exit non-zero and leave nothing in `Resources/Tools`.
- [ ] **Step 2: Run** `make tools-test`; expected FAIL.
- [ ] **Step 3: Implement `fetch-tools.sh`** for yt-dlp (`yt-dlp_macos`, renamed `yt-dlp`) and node (extract the `node` executable only from the `darwin-arm64` tarball), verifying checksums from the lock; fill the lock with the current yt-dlp release and Node 22 LTS values, checksums taken from the publishers' own checksum files.
- [ ] **Step 4: Implement `build-ffmpeg.sh`**: download the pinned ffmpeg source tarball (checksum in the lock), configure `--disable-gpl --disable-nonfree --disable-autodetect --enable-libmp3lame --enable-static --disable-shared --disable-doc --disable-ffplay` with only the muxers/demuxers/protocols/filters yt-dlp's merge and extract paths need (mp4, ipod, matroska, mp3, mov, aac, concat, file, pipe, copy), build `ffmpeg` and `ffprobe`; `libmp3lame` is built from its pinned tarball first. Cache keyed by lock hash in CI.
- [ ] **Step 5: Implement `build-shield.sh`**: unpack the bgutil source at `ShieldInstaller.version`, run `npm ci --omit=dev`-equivalent build (`npm ci`, `npx tsc`, then prune to production dependencies) using the freshly fetched `node`, copy `server/` and the plugin zip into `Resources/Shield`.
- [ ] **Step 6: Signing spike (verifies the riskiest assumption).** Re-sign each fetched executable with `codesign --force --sign -`, run each with `--version`, then confirm `codesign --verify --deep --strict` on a built app containing them. If the PyInstaller `yt-dlp` fails to run after re-signing, stop and report; do not work around it silently.
- [ ] **Step 7: Verify.** `make tools-test` passes; `make tools` produces the files; each tool prints a version; `make` builds and `Contents/Resources/Tools` is in the built app.
- [ ] **Step 8: CI.** Add `make tools` to the release workflow before "Build Release" (ffmpeg build cached), and a "Smoke test bundled tools" step after signing that runs every executable inside the built app with `--version`.

### Task 7: yt-dlp updater from GitHub releases

**Files:**

- Modify: `Sources/GrabberKit/Diagnostics/YtDlpUpdater.swift`, `Sources/App/About/AboutView.swift`, `Sources/App/Preferences/DiagnosticsPane.swift`, `Sources/App/AppModel.swift`, `Sources/App/Preferences/Panes/UpdatesPane.swift`, existing updater fakes and tests
- Create: `Sources/GrabberKit/Diagnostics/YtDlpReleaseSource.swift`, `Tests/GrabberKitTests/YtDlpUpdaterTests.swift`

**Interfaces:**

- Consumes: `ManagedTools` (Task 5), `CanaryProbe.run(ytDlpPath:runner:)`
- Produces:
  - `public struct YtDlpRelease: Sendable, Equatable { public let version: String; public let binaryURL: URL; public let checksumsURL: URL }`
  - `public protocol YtDlpReleaseSource: Sendable { func latest() async throws -> YtDlpRelease; func fetch(_ url: URL) async throws -> Data }`; the live source reads `https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest`
  - `YtDlpUpdating.updateToLatest() async -> YtDlpUpdateResult` (replaces `reinstallToMinimum()`); `YtDlpUpdateResult` keeps `.success(newVersion:)` / `.failure(reason:)`
  - `YtDlpUpdater.init(source: YtDlpReleaseSource, tools: ManagedTools, supportDirectory: URL, runner: ProcessRunning)`

- [ ] **Step 1: Failing tests** with a `FakeReleaseSource`: `test_updatesWhenNewer_installsAndMarksExecutable`, `test_alreadyCurrent_returnsSuccessWithoutDownload`, `test_checksumMismatch_keepsPreviousCopy`, `test_truncatedDownload_keepsPreviousCopy_andNeverExecutesPartial`, `test_networkFailure_returnsPlainFailure`, `test_canaryFails_deletesUpdatedCopy_andBundledRemainsActive`, `test_installIsAtomic` (the file appears at `bin/yt-dlp` only via rename from `bin/yt-dlp.partial`).
- [ ] **Step 2: Run** `make test ONLY=GrabberKitTests/YtDlpUpdaterTests`; expected FAIL.
- [ ] **Step 3: Implement** `updateToLatest` per spec section 5: compare against `tools.ytDlp` version, download binary and `SHA2-256SUMS`, verify, write to `.partial`, `chmod 755`, `codesign --force --sign -` it, rename, run the canary; on failure remove the new file. User-facing failure strings are plain ("Couldn't download the update. Check your connection and try again.") with the raw reason kept for the diagnostics bundle only.
- [ ] **Step 4: Rename call sites** from `reinstallToMinimum` and delete `brewPath`; `AppModel` triggers a background update on launch when `prefs.autoCheckYtDlpUpdates` is on and the drift verdict says outdated, or once a day.
- [ ] **Step 5: Verify.** `make lint`; `make test ONLY=GrabberKitTests`; `make test ONLY=AppUnitTests`; expected green.

### Task 8: Sign-in helper runs from the bundle

**Files:**

- Modify: `Sources/GrabberKit/Onboarding/ShieldInstaller.swift`, `Sources/GrabberKit/PotProvider/PotPluginInstaller.swift`, `Sources/App/Shield/ShieldSetupController.swift`, `Sources/App/Shield/ShieldSetupSheet.swift`, `Tests/GrabberKitTests` shield and pot-installer tests, `Tests/AppUnitTests/AppModelShieldPromptTests.swift`

**Interfaces:**

- Consumes: `ManagedTools.node`, `.shieldServerEntry`, `.shieldPluginArchive`
- Produces:
  - `ShieldInstaller.install(onProgress:) async -> ShieldInstallOutcome` with `ShieldInstallOutcome` reduced to `.installed` / `.failed(detail:)`
  - `PotPluginInstaller.resolveServerLaunch(port:host:)` returns `node <bundled main.js> --host --port` or nil only when the bundle is damaged

- [ ] **Step 1: Failing tests:** `test_resolveServerLaunch_usesBundledNodeAndServer`, `test_resolveServerLaunch_ignoresSystemNodeAndPipx`, `test_install_copiesBundledPluginIntoSupportDirectory`, `test_install_idempotent`, `test_install_bundleDamaged_failsWithPlainReason`, `test_shieldSheet_hasNoHomebrewState` (the controller exposes no `needsHomebrew`).
- [ ] **Step 2: Run** the three suites; expected FAIL.
- [ ] **Step 3: Implement.** `ShieldInstaller` copies `shieldPluginArchive` to `Application Support/MediaGrabber/bgutil-plugin.zip` when missing; no downloads, no `npm`, no `brew`, no tar; remove `minimumNodeMajor`, `toolPath`, `ensureNode`, `download`, `run`. `PotPluginInstaller` drops the pipx and Application-Support-built-server lookups and `searchPaths`.
- [ ] **Step 4: UI.** Delete the `.needsHomebrew` cases in `ShieldSetupController` and `ShieldSetupSheet`; the sheet's states are installing, done, failed.
- [ ] **Step 5: Verify.** `make lint`; `make test ONLY=GrabberKitTests`; `make test ONLY=AppUnitTests`; with `make`, trigger the sign-in helper on a YouTube link and confirm the server starts from inside the app bundle (`ps` shows the bundled `node`).

### Task 9: First run without installs

**Files:**

- Modify: `Sources/GrabberKit/Onboarding/OnboardingInstaller.swift`, `Sources/App/Onboarding/OnboardingView.swift`, `Sources/App/AppModel.swift`, `Tests/AppUnitTests/AppModelOnboardingTests.swift`, `Tests/GrabberKitTests` onboarding tests

**Interfaces:**

- Produces: `OnboardingStepID` cases `botCheckShield`, `testRun` only; `HomebrewInstallInfo` and `openTerminalForHomebrew` no longer exist; `OnboardingInstaller.start()` runs the shield copy and the canary, nothing else.

- [ ] **Step 1: Failing tests:** `test_start_neverInvokesInstallers`, `test_firstRun_readyWithoutHomebrewOrNode`, `test_canaryFailure_showsPlainNetworkMessage_andRetryAction`, `test_onboardingStepsAreShieldAndTestRun`.
- [ ] **Step 2: Run** `make test ONLY=AppUnitTests/AppModelOnboardingTests`; expected FAIL.
- [ ] **Step 3: Implement** the reduced flow and the matching `OnboardingView` copy: heading "Getting ready", steps "Setting up the YouTube helper" and "Checking that downloads work", each with the existing running/done/failed treatments; remove the Homebrew rows and their helper text.
- [ ] **Step 4: Verify.** `make lint`; `make test`; with `make` and `-MGForceOnboarding`, run the flow on this machine and confirm no step touches Homebrew (a `brew` shim earlier on `PATH` that logs and exits 1 stays untouched).

---

## Part C: Notices, docs, gate

### Task 10: Third-party notices, README, development docs

**Files:**

- Create: `Resources/Notices/ThirdParty.md`, `docs/development.md`
- Modify: `README.md` (user-facing rewrite), `Sources/App/About/AboutView.swift` (Notices link), `Project.swift` (resource), `docs/architecture.md`, `CLAUDE.md`, `PRIVACY.md` (update checks and yt-dlp downloads are the only network calls the app itself makes beyond downloads)

**Interfaces:**

- Produces: `README.md` sections in this order: What it is, Download, Install, Updating, Uninstalling, Getting help; no build instructions.

- [ ] **Step 1: Notices.** `ThirdParty.md` lists yt-dlp (Unlicense), FFmpeg (LGPL-2.1+, exact configure line and a link to the pinned source tarball), LAME (LGPL), Node (MIT), bgutil provider (its license), Sparkle (MIT); AboutView gets a "Third-party notices" row that opens it.
- [ ] **Step 2: Move dev content.** Build/run/test/lint/debug-flag material from the current README goes to `docs/development.md`, with the same words, unwrapped paragraphs.
- [ ] **Step 3: Write the user README:** download button linking to the filtered release list, "Apple Silicon Macs, macOS 14 or later", the Open Anyway steps with screenshots (captured by the user from the first release build and added to `docs/images/`), update and uninstall paragraphs, how to share a diagnostic bundle. One paragraph per line, no hard wrapping.
- [ ] **Step 4:** Update `docs/architecture.md` (tool resolution, update path, uninstall footprint) and the `CLAUDE.md` Release and toolchain sections (`make tools`, `tools.lock`, Sparkle key).
- [ ] **Step 5: Verify.** `make lint`; open the README rendered and click every link.

### Task 11: Release gate (manual, user-run)

- [ ] **Step 1:** `make test` and `make lint` fully green.
- [ ] **Step 2:** Run the release workflow with `dry_run`; read the log: tools fetched with checksums, ffmpeg built, smoke test passed, `codesign --verify --deep --strict` passed, DMG verified, appcast printed.
- [ ] **Step 3:** User cuts `make release-minor`; confirm the Release carries the DMG and `SHA256SUMS` and the Pages appcast lists the version.
- [ ] **Step 4:** On a clean macOS user account with no Homebrew: download the DMG, drag to Applications, Open Anyway, paste a link, finish a download, an audio-only m4a and mp3 extraction, and a YouTube link that needs the sign-in helper.
- [ ] **Step 5:** Release a second version; on the same account confirm Check for Updates installs it in place and relaunches with no Gatekeeper prompt.
- [ ] **Step 6:** Press Uninstall; confirm the footprint directories are gone, the app is in the Trash, and the downloaded files remain.
- [ ] **Step 7:** Hand the DMG link and README to the first technical testers.
