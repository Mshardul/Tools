# MediaGrabber Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a launchable macOS app that takes one pasted URL, installs its
dependencies on first run if missing, resolves the title, downloads the file
with a live progress bar, and shows "saved" with a Reveal-in-Finder action.

**Architecture:** Two targets. `GrabberKit` is a headless SPM library — process
control, environment probing, argument building, output parsing, the download
engine, the data model, and structured logging — every piece unit-testable
without launching the app or touching the network. `App` is a thin SwiftUI
layer over it: a single window with Home (active), Preferences and Diagnostics
(present but empty), a full-window onboarding takeover, and the skin/palette
theming plumbing. The engine shells out to `yt-dlp`, one child process per
download, and parses its `--progress-template` output.

**Tech Stack:** Swift 6, SwiftUI, Swift Concurrency (actors, `AsyncStream`),
`@Observable`, `Foundation.Process`, `os.Logger`. Tuist for project generation,
mise for tool version pinning. SwiftFormat + SwiftLint. GitHub Actions on
`macos-14`. `yt-dlp` + `ffmpeg` are external runtime dependencies (Homebrew),
never bundled.

**Spec:** `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md`
(Phase 1 is §12.1). Visual design: `apps/media-grabber/docs/design-system.md`.
Living mockup: `apps/media-grabber/docs/mockups/screens.html`.

## Global Constraints

- **Leaf directory:** all work is under `apps/media-grabber/`. The root Python
  `.venv` / `requirements.txt` are untouched.
- **Working name:** `MediaGrabber` (product / directory name). Bundle ID
  `app.mediagrabber.mac`. Final name is deferred (spec §14); renaming later is
  a mechanical find-and-replace.
- **Min OS:** macOS 14.0 (`LSMinimumSystemVersion 14.0`).
- **Signing:** ad-hoc (`codesign -s -`), hardened runtime **OFF**, not
  sandboxed. No paid Apple Developer account. Bundles **no** helper Mach-O —
  `yt-dlp` / `ffmpeg` are always external.
- **Tuist:** committed — `Project.swift`, `Tuist/`, `.mise.toml`. Gitignored —
  `*.xcodeproj`, `*.xcworkspace`, `Derived/`, Xcode user state, all scoped to
  the leaf.
- **TDD throughout:** the test is written and seen to fail before the
  implementation, for every unit. Frequent commits — one per red→green cycle.
- **No network in tests.** Real-network integration tests are gated behind the
  `MG_LIVE_TESTS=1` environment variable and are off in CI.
- **`GrabberKit` imports no SwiftUI** and has no dependency on the `App` target.
- **Phase 1 skin:** Aurora / Mint & Iris only. No skin or palette picker UI, but
  the `Skin` / `Palette` / environment plumbing is real (not hardcoded literals
  in views).
- **Privacy (spec §8.5):** logs are local only, no telemetry, no network egress
  from logging. Redact in all logs: cookie contents, proxy credentials, any
  `--username` / `--password`, and absolute `/Users/<name>/…` paths rewritten to
  `~`. Logged in the clear: video URLs, titles, destination folder (as `~/…`).
- **Out of Phase 1:** queue, scheduler, persistence, resume, resilience /
  backoff / circuit breaker, `player_client` rotation, POT provider, cookies,
  playlists, add-flows beyond paste, Preferences UI, Diagnostics content,
  toasts, the warning banner.

---

## File Structure

```
apps/media-grabber/
  Project.swift                         # Tuist project: App + GrabberKit + GrabberKitTests
  Tuist/
    Config.swift                        # Tuist config
  .mise.toml                            # pins tuist
  .gitignore                            # leaf-scoped: *.xcodeproj, Derived/, etc.
  .swiftformat                          # SwiftFormat rules
  .swiftlint.yml                        # SwiftLint rules
  README.md                             # build steps + Gatekeeper "Open Anyway"
  PRIVACY.md                            # what the logs contain, all local
  ticket-backlog.md                     # leaf backlog
  docs/
    design-system.md                    # (exists)
    mockups/screens.html                # (exists)
  Sources/
    App/
      MediaGrabberApp.swift             # @main, single WindowGroup, window size restore
      AppModel.swift                    # @Observable: deps, job, page
      MainWindow.swift                  # brand row + health strip + nav + page switch
      Theme/
        Skin.swift                      # Skin enum: fonts, radii, border, elevation, motif
        Palette.swift                   # Palette enum + Color token struct
        SkinEnvironment.swift           # EnvironmentKey injecting resolved skin+palette
        MotifView.swift                 # conic-gradient orb, isActive, reduce-motion aware
      Onboarding/
        OnboardingView.swift            # full-window checklist, blocks Home
      Home/
        HomeView.swift                  # field + step cards / runway / one-row job list
        RunwayView.swift                # labelled slots + Grab button
    GrabberKit/
      Onboarding/
        ProcessRunner.swift             # async Process wrapper, line-streamed output
        EnvironmentProbe.swift          # locate + version brew, yt-dlp, ffmpeg
        OnboardingInstaller.swift       # first-run setup state machine
      Download/
        DownloadRequest.swift           # immutable request value
        DownloadJob.swift               # @Observable per-row state
        Progress.swift                  # progress value type
        ErrorClass.swift                # error classification enum
        YtDlpArguments.swift            # (DownloadRequest) -> [String], + redacted view
        ProgressParser.swift            # progress-template lines -> ProgressEvent; stderr -> ErrorClass
        MetadataProbe.swift             # yt-dlp -J -> title / duration / isPlaylist
        DownloadEngine.swift            # actor: submit one job, drive it to terminal
      Model/
        Preferences.swift              # @Observable, UserDefaults-backed
      Logging/
        LogWriter.swift                 # actor: JSON Lines + os.Logger mirror
        LogEvent.swift                  # event enum + schema + redaction helpers
  Tests/
    GrabberKitTests/
      Fixtures/                         # checked-in yt-dlp output samples
      ProcessRunnerTests.swift
      EnvironmentProbeTests.swift
      OnboardingInstallerTests.swift
      DownloadRequestTests.swift
      PreferencesTests.swift
      YtDlpArgumentsTests.swift
      ProgressParserTests.swift
      MetadataProbeTests.swift
      DownloadEngineTests.swift
      LogWriterTests.swift
      AppModelTests.swift               # AppModel logic with a fake engine
```

**Responsibilities.** `ProcessRunner` is the only place `Foundation.Process` is
touched. `DownloadEngine` is the only component that spawns download processes.
`ProcessRunner`, `EnvironmentProbe`, `YtDlpArguments`, `ProgressParser`,
`Progress`, `ErrorClass`, `Preferences` are pure or fixture-testable. The `App`
target holds only SwiftUI and reads everything else from `GrabberKit`.

---

## Task 1: Project skeleton — Tuist, CI, lint, a window that opens

**Files:**
- Create: `apps/media-grabber/.mise.toml`
- Create: `apps/media-grabber/Project.swift`
- Create: `apps/media-grabber/Tuist/Config.swift`
- Create: `apps/media-grabber/.gitignore`
- Create: `apps/media-grabber/.swiftformat`
- Create: `apps/media-grabber/.swiftlint.yml`
- Create: `apps/media-grabber/Sources/App/MediaGrabberApp.swift`
- Create: `apps/media-grabber/Sources/GrabberKit/GrabberKit.swift` (placeholder so the target compiles)
- Create: `apps/media-grabber/Tests/GrabberKitTests/SmokeTests.swift`
- Create: `.github/workflows/media-grabber.yml`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - A Tuist project at `apps/media-grabber/` with three targets:
    `MediaGrabber` (app, bundle ID `app.mediagrabber.mac`, deployment target
    macOS 14.0, `INFOPLIST_KEY_LSMinimumSystemVersion = 14.0`), `GrabberKit`
    (framework), `GrabberKitTests` (unit-test bundle for `GrabberKit`).
  - `tuist generate` produces a buildable workspace; `tuist build` and
    `tuist test` both succeed.
  - App target has `CODE_SIGN_IDENTITY = "-"`, `CODE_SIGN_STYLE = Manual`,
    `ENABLE_HARDENED_RUNTIME = NO`, `ENABLE_APP_SANDBOX = NO`.

- [x] **Step 1: Install the toolchain**

Run:
```bash
brew install mise
cd apps/media-grabber && mise use tuist@latest && mise install
```
Expected: `mise ls` shows `tuist`. `.mise.toml` now exists and pins the version.
Commit `.mise.toml` as-is.

- [x] **Step 2: Write `Tuist/Config.swift`**

```swift
import ProjectDescription

let config = Config(
    fullHandle: nil,
    generationOptions: .options()
)
```

- [x] **Step 3: Write `Project.swift`**

```swift
import ProjectDescription

let project = Project(
    name: "MediaGrabber",
    options: .options(
        automaticSchemesOptions: .enabled(),
        developmentRegion: "en"
    ),
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "MACOSX_DEPLOYMENT_TARGET": "14.0",
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        .target(
            name: "MediaGrabber",
            destinations: .macOS,
            product: .app,
            bundleId: "app.mediagrabber.mac",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "LSMinimumSystemVersion": "14.0",
                "CFBundleDisplayName": "MediaGrabber",
                "NSHumanReadableCopyright": "MIT",
            ]),
            sources: ["Sources/App/**"],
            resources: [],
            dependencies: [.target(name: "GrabberKit")],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "-",
                "CODE_SIGN_STYLE": "Manual",
                "ENABLE_HARDENED_RUNTIME": "NO",
                "ENABLE_APP_SANDBOX": "NO",
            ])
        ),
        .target(
            name: "GrabberKit",
            destinations: .macOS,
            product: .framework,
            bundleId: "app.mediagrabber.mac.kit",
            deploymentTargets: .macOS("14.0"),
            sources: ["Sources/GrabberKit/**"],
            dependencies: []
        ),
        .target(
            name: "GrabberKitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "app.mediagrabber.mac.kit.tests",
            deploymentTargets: .macOS("14.0"),
            sources: ["Tests/GrabberKitTests/**"],
            resources: ["Tests/GrabberKitTests/Fixtures/**"],
            dependencies: [.target(name: "GrabberKit")]
        ),
    ]
)
```

- [x] **Step 4: Write the leaf `.gitignore`**

```gitignore
# Tuist / Xcode generated — scoped to this leaf
*.xcodeproj
*.xcworkspace
Derived/
.build/
*.xcuserstate
xcuserdata/
```

- [x] **Step 5: Write `.swiftformat` and `.swiftlint.yml`**

`.swiftformat`:
```
--swiftversion 6.0
--indent 4
--maxwidth 100
--wraparguments before-first
--wrapparameters before-first
--self remove
--commas inline
--trimwhitespace always
```

`.swiftlint.yml`:
```yaml
included:
  - Sources
  - Tests
opt_in_rules:
  - empty_count
  - closure_spacing
  - explicit_init
line_length:
  warning: 100
  error: 140
identifier_name:
  min_length: 2
  excluded: [id, ok, to]
```

- [x] **Step 6: Write the `@main` app entry — a bare window**

`Sources/App/MediaGrabberApp.swift`:
```swift
import SwiftUI

@main
struct MediaGrabberApp: App {
    var body: some Scene {
        WindowGroup {
            Text("MediaGrabber")
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentSize)
    }
}
```

`Sources/GrabberKit/GrabberKit.swift`:
```swift
// GrabberKit — headless engine for MediaGrabber.
// Real types are added in later tasks.
public enum GrabberKit {
    public static let name = "GrabberKit"
}
```

- [x] **Step 7: Write the smoke test**

`Tests/GrabberKitTests/SmokeTests.swift`:
```swift
import XCTest
@testable import GrabberKit

final class SmokeTests: XCTestCase {
    func test_grabberKitName() {
        XCTAssertEqual(GrabberKit.name, "GrabberKit")
    }
}
```

- [x] **Step 8: Generate, build, test locally**

Run:
```bash
cd apps/media-grabber
tuist generate
tuist build
tuist test
```
Expected: generate creates `MediaGrabber.xcworkspace` (gitignored), build
succeeds, the smoke test passes, and running the app opens a window titled
"MediaGrabber".

- [x] **Step 9: Write the GitHub Actions workflow**

`.github/workflows/media-grabber.yml`:
```yaml
name: media-grabber
on:
  push:
    paths: ['apps/media-grabber/**', '.github/workflows/media-grabber.yml']
  pull_request:
    paths: ['apps/media-grabber/**', '.github/workflows/media-grabber.yml']
jobs:
  build-test:
    runs-on: macos-14
    defaults:
      run:
        working-directory: apps/media-grabber
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist generate --no-open
      - run: tuist build
      - run: tuist test
      - run: mise exec -- swiftformat --lint .
      - run: mise exec -- swiftlint lint --strict
```
Add `swiftformat` and `swiftlint` to `.mise.toml` (`mise use swiftformat@latest
swiftlint@latest`).

- [ ] **Step 10: Commit**

```bash
git add apps/media-grabber .github/workflows/media-grabber.yml
git commit -m "feat(media-grabber): Tuist project skeleton, CI, lint, bare window"
```
DoD: CI is green on the pushed branch; `tuist test` passes locally; launching
the app opens a window.

---

## Task 2: `ProcessRunner` — async, line-streamed child processes

The one wrapper over `Foundation.Process` in the codebase. Everything that
shells out (`EnvironmentProbe`, `OnboardingInstaller`, `MetadataProbe`,
`DownloadEngine`) goes through this.

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Onboarding/ProcessRunner.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/ProcessRunnerTests.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/Fixtures/emit3lines.sh` (a
  helper script: prints 3 lines with a 50ms gap between them, then exits 0)
- Create: `apps/media-grabber/Tests/GrabberKitTests/Fixtures/hang.sh` (sleeps
  60s — used for the cancellation test)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  ```swift
  public struct ProcessLaunch: Sendable {
      public var executableURL: URL
      public var arguments: [String]
      public var environment: [String: String]?   // nil = inherit
      public var currentDirectoryURL: URL?
      public init(executableURL: URL, arguments: [String],
                  environment: [String: String]? = nil,
                  currentDirectoryURL: URL? = nil)
  }

  public enum ProcessLine: Sendable {
      case stdout(String)
      case stderr(String)
  }

  public struct ProcessResult: Sendable {
      public let exitCode: Int32
      public let wasCancelled: Bool
  }

  public protocol ProcessRunning: Sendable {
      /// Streams stdout/stderr line by line as they arrive; the stream
      /// finishes when the process exits. Await `result()` for the exit code.
      func run(_ launch: ProcessLaunch) -> ProcessExecution
  }

  public struct ProcessExecution: Sendable {
      public let lines: AsyncStream<ProcessLine>
      public func result() async -> ProcessResult
  }

  public struct ProcessRunner: ProcessRunning {
      public init()
  }
  ```
  Cancellation: cancelling the `Task` that is awaiting `result()` (or iterating
  `lines`) sends `SIGTERM` to the child; `ProcessResult.wasCancelled == true`.
  Later tasks depend on the exact names `ProcessRunner`, `ProcessRunning`,
  `ProcessLaunch`, `ProcessLine`, `ProcessExecution`, `ProcessResult`.

- [x] **Step 1: Write the failing tests**

`ProcessRunnerTests.swift` — one test per behavior:
- `test_true_exitsZero` — `/usr/bin/true` → `exitCode == 0`, no lines.
- `test_false_exitsOne` — `/usr/bin/false` → `exitCode == 1`.
- `test_echo_emitsStdoutLine` — `/bin/echo hello` → exactly one
  `.stdout("hello")`, then the stream finishes, `exitCode == 0`.
- `test_stderr_isTaggedSeparately` — `/bin/sh -c "echo out; echo err 1>&2"` →
  one `.stdout("out")` and one `.stderr("err")` (order not asserted).
- `test_threeLines_arriveInOrder` — run `Fixtures/emit3lines.sh` → three
  `.stdout` lines in emission order.
- `test_cancellation_sendsSigtermAndReports` — run `Fixtures/hang.sh` inside a
  `Task`, cancel it after 100ms → `result()` returns with
  `wasCancelled == true` and returns within ~1s (not 60s).
- `test_environment_isPassedThrough` — `/bin/sh -c 'echo $MG_TEST'` with
  `environment: ["MG_TEST": "xyz"]` (merged onto the parent env) → `.stdout("xyz")`.

Make the two fixture scripts executable and add them to the test target's
`Fixtures/` resource bundle (Task 1 already wired `Fixtures/**` as resources).
Resolve them at test time via `Bundle.module.url(forResource:withExtension:)`.

- [x] **Step 2: Run the tests — verify they fail**

Run: `tuist test --test-targets GrabberKitTests/ProcessRunnerTests`
Expected: FAIL — `ProcessRunner` / the protocol types are not defined.

- [x] **Step 3: Implement `ProcessRunner`**

Sketch (executor fills the body):
- `run(_:)` builds a `Foundation.Process` + two `Pipe`s, starts it, and returns
  a `ProcessExecution` whose `lines` is an `AsyncStream` fed by
  `readabilityHandler`s that split incoming `Data` on `\n` (buffer partial
  lines; flush the buffer on EOF).
- `result()` awaits `process.waitUntilExit` bridged into async (a
  `withCheckedContinuation` in `terminationHandler`), then returns
  `ProcessResult(exitCode: process.terminationStatus, wasCancelled:)`.
- Wrap the await in `withTaskCancellationHandler`; on cancel call
  `process.terminate()` (SIGTERM) and record `wasCancelled = true`.
- `environment: nil` means "inherit" — pass `ProcessInfo.processInfo.environment`;
  a non-nil value is merged onto the parent environment, caller keys winning.
- Nothing throws out of `run` / `result`; a launch failure surfaces as a
  non-zero synthetic `exitCode` (e.g. `127`) plus a `.stderr` line.

- [x] **Step 4: Run the tests — verify they pass**

Run: `tuist test --test-targets GrabberKitTests/ProcessRunnerTests`
Expected: PASS (all 7).

- [ ] **Step 5: Commit**

```bash
git add apps/media-grabber/Sources/GrabberKit/Onboarding/ProcessRunner.swift \
        apps/media-grabber/Tests/GrabberKitTests/ProcessRunnerTests.swift \
        apps/media-grabber/Tests/GrabberKitTests/Fixtures/
git commit -m "feat(media-grabber): ProcessRunner — async line-streamed child processes"
```
DoD: every process-control path (exit 0, exit non-zero, stdout, stderr,
ordered multi-line, cancel→SIGTERM, env pass-through) is covered by a passing
fixture-backed test; no network.

---

## Task 3: `EnvironmentProbe` — locate and version brew, yt-dlp, ffmpeg

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Onboarding/EnvironmentProbe.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/EnvironmentProbeTests.swift`

**Interfaces:**
- Consumes: `ProcessRunning`, `ProcessLaunch`, `ProcessExecution` from Task 2.
- Produces:
  ```swift
  public struct ToolInfo: Sendable, Equatable {
      public let path: URL
      public let version: String        // parsed, e.g. "2025.09.26" or "8.0"
  }

  public struct EnvironmentReport: Sendable, Equatable {
      public let brew: ToolInfo?
      public let ytDlp: ToolInfo?
      public let ffmpeg: ToolInfo?
      /// true when both yt-dlp and ffmpeg are present.
      public var isReadyForDownloads: Bool { ytDlp != nil && ffmpeg != nil }
  }

  public struct EnvironmentProbe: Sendable {
      public init(runner: ProcessRunning = ProcessRunner(),
                  extraSearchPaths: [URL] = EnvironmentProbe.defaultSearchPaths)
      public func probe() async -> EnvironmentReport

      /// Homebrew locations + common installs, in priority order:
      /// /opt/homebrew/bin, /usr/local/bin, /usr/bin, ~/.local/bin,
      /// plus each entry of $PATH.
      public static var defaultSearchPaths: [URL] { get }
  }
  ```
  Later tasks (`OnboardingInstaller`, the App's `AppModel`) depend on
  `EnvironmentReport`, `ToolInfo`, `EnvironmentProbe`, and `isReadyForDownloads`.

**Version parsing rules (pin these — tests assert them):**
- `brew --version` → first line `Homebrew 4.3.0` → `"4.3.0"`.
- `yt-dlp --version` → the whole output is the version, e.g. `2025.09.26`.
- `ffmpeg -version` → first line `ffmpeg version 8.0 Copyright ...` → `"8.0"`
  (take the token after `version`, strip a leading `n`, keep up to the first
  space).
- Unparseable / empty output → treat the tool as **not found** (`nil`), never
  crash.

- [x] **Step 1: Write the failing tests**

Use a `FakeProcessRunner` (a `ProcessRunning` that returns scripted lines +
exit code per matched executable path — build it in this test file; later tasks
reuse it, so give it a small public-ish shape inside the test target).

- `test_allToolsPresent_parsesVersions` — fake returns the three version
  strings above → `report.brew?.version == "4.3.0"`, `ytDlp?.version ==
  "2025.09.26"`, `ffmpeg?.version == "8.0"`, `isReadyForDownloads == true`.
- `test_ytDlpMissing_reportsNilAndNotReady` — fake has no `yt-dlp` on any search
  path → `report.ytDlp == nil`, `isReadyForDownloads == false`.
- `test_ffmpegMalformedVersion_treatedAsMissing` — fake returns `garbage` for
  `ffmpeg -version` → `report.ffmpeg == nil`.
- `test_firstMatchOnSearchPathWins` — `yt-dlp` exists in both
  `/opt/homebrew/bin` and `/usr/local/bin`; the report's path is the
  `/opt/homebrew/bin` one.
- `test_noRealBrewOrNetwork` — the whole suite runs with the fake; assert the
  real `ProcessRunner` is never constructed (inject the fake).

- [x] **Step 2: Run the tests — verify they fail**

Run: `tuist test --test-targets GrabberKitTests/EnvironmentProbeTests`
Expected: FAIL — `EnvironmentProbe` undefined.

- [x] **Step 3: Implement `EnvironmentProbe`**

- `probe()` iterates each tool name over `extraSearchPaths`, `FileManager`
  `isExecutableFile` check for the first hit, then runs its version command via
  the injected `runner`, parses per the rules above, builds `ToolInfo`.
- All three tools probed concurrently (`async let` / task group); assemble the
  `EnvironmentReport`.
- Parsing helpers are private free functions, each unit-coverable through the
  public `probe()` behavior.

- [x] **Step 4: Run the tests — verify they pass**

Run: `tuist test --test-targets GrabberKitTests/EnvironmentProbeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/media-grabber/Sources/GrabberKit/Onboarding/EnvironmentProbe.swift \
        apps/media-grabber/Tests/GrabberKitTests/EnvironmentProbeTests.swift
git commit -m "feat(media-grabber): EnvironmentProbe — locate and version brew/yt-dlp/ffmpeg"
```
DoD: a correct `EnvironmentReport` is produced against fixtures with no real
brew and no network; a missing or malformed tool degrades to `nil` without
crashing.

---

## Task 4: Data types — request, job, progress, error class, preferences

The Phase 1 model surface. Pure value types plus one `@Observable` job and one
`@Observable` UserDefaults-backed `Preferences`. `ErrorClass` gets its full
spec §9 case list now (later phases fill in the classification logic); Phase 1
only ever produces `.unknown`, `.networkDown`, `.depMissing`.

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Download/DownloadRequest.swift`
- Create: `apps/media-grabber/Sources/GrabberKit/Download/Progress.swift`
- Create: `apps/media-grabber/Sources/GrabberKit/Download/ErrorClass.swift`
- Create: `apps/media-grabber/Sources/GrabberKit/Download/DownloadJob.swift`
- Create: `apps/media-grabber/Sources/GrabberKit/Model/Preferences.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/DownloadRequestTests.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/PreferencesTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  ```swift
  public enum AudioCodec: String, Codable, Sendable, CaseIterable { case m4a, mp3 }

  public enum DownloadKind: Codable, Sendable, Equatable {
      case video(maxHeight: Int)      // 1080, 720, 480, 360, 2160, 1440
      case audio(codec: AudioCodec)
  }

  public struct DownloadRequest: Codable, Sendable, Equatable {
      public var url: String
      public var destFolder: URL
      public var kind: DownloadKind
      public var container: String?        // "mp4" for video; nil = yt-dlp chooses
      public var outputTemplate: String    // default "%(title)s.%(ext)s"
      public init(url: String, destFolder: URL, kind: DownloadKind,
                  container: String? = nil,
                  outputTemplate: String = "%(title)s.%(ext)s")
  }

  public struct Progress: Sendable, Equatable {
      public var fraction: Double            // 0.0 ... 1.0
      public var speedBytesPerSec: Double?
      public var etaSeconds: Int?
      public var downloadedBytes: Int64
      public var totalBytes: Int64?
  }

  public enum ErrorClass: Sendable, Equatable {
      case rateLimited, botCheck, sabrGated, formatsMissing, cookieReadFailed
      case geoBlocked, `private`, unavailable, ageRestricted, networkDown
      case diskFull, permissionDenied, incomplete, depMissing, potProviderDown
      case unknown(raw: String)
  }

  public enum JobState: Sendable, Equatable {
      case queued, probing, running, paused, waitingForNetwork
      case cooldown(until: Date)
      case completed, cancelled
      case failed(ErrorClass)
  }

  @Observable
  public final class DownloadJob: Identifiable, @unchecked Sendable {
      public let id: UUID
      public let request: DownloadRequest
      public var title: String?
      public var state: JobState
      public var progress: Progress?
      public var attempt: Int
      public var playerClientUsed: String?
      public var outputFiles: [URL]
      public let addedAt: Date
      public var finishedAt: Date?
      public init(request: DownloadRequest, id: UUID = UUID(), addedAt: Date = .now)
      // starts: state = .queued, attempt = 0, everything else nil/empty
  }

  @Observable
  public final class Preferences: @unchecked Sendable {
      public var defaultDestFolder: URL          // default ~/Downloads
      public var lastUsedDestFolder: URL         // default = defaultDestFolder
      public var defaultKind: DownloadKind       // default .video(maxHeight: 1080)
      public var defaultMaxHeight: Int           // default 1080
      public var defaultAudioCodec: AudioCodec   // default .m4a
      public var outputTemplate: String          // default "%(title)s.%(ext)s"
      public var maxAutoAttempts: Int            // 1...5, default 5
      public var verboseLogging: Bool            // default false
      public var skin: SkinKind                  // default .aurora
      public var palette: PaletteKind            // default .auroraMintIris
      public init(defaults: UserDefaults = .standard)
      // each property is get/set-backed by `defaults` under key "mg.<name>"
  }
  ```
  `SkinKind` / `PaletteKind` are lightweight `String`-raw enums defined here
  (the App-side `Skin` / `Palette` in Task 7 map from them — `GrabberKit`
  imports no SwiftUI so it cannot hold `Color`/`Font`). `SkinKind` cases:
  `tapeDeck, aurora`. `PaletteKind` cases: `auroraMintIris, auroraLimeForest,
  auroraMagentaViolet, tapeDeckA, tapeDeckB, tapeDeckC` (Phase 1 only uses
  `auroraMintIris`).

  Later tasks depend on: `DownloadRequest`, `DownloadKind`, `AudioCodec`,
  `Progress`, `ErrorClass`, `JobState`, `DownloadJob`, `Preferences`,
  `SkinKind`, `PaletteKind`.

- [x] **Step 1: Write the failing tests**

`DownloadRequestTests.swift`:
- `test_defaultOutputTemplate` — a `DownloadRequest` built without
  `outputTemplate` has `"%(title)s.%(ext)s"`.
- `test_codableRoundTrip_video` — encode→decode a `.video(maxHeight: 720)`
  request → equal to the original.
- `test_codableRoundTrip_audio` — same for `.audio(codec: .mp3)`.
- `test_errorClass_unknownCarriesRaw` — `ErrorClass.unknown(raw: "boom")` is
  `Equatable` and keeps `"boom"`.
- `test_jobStartsQueued` — `DownloadJob(request:)` has `state == .queued`,
  `attempt == 0`, `title == nil`, `progress == nil`, `outputFiles == []`.

`PreferencesTests.swift` (use `UserDefaults(suiteName:)` throwaway suites, wiped
in `tearDown`):
- `test_defaults` — a fresh `Preferences` over an empty suite has
  `defaultMaxHeight == 1080`, `defaultAudioCodec == .m4a`, `outputTemplate ==
  "%(title)s.%(ext)s"`, `maxAutoAttempts == 5`, `verboseLogging == false`,
  `skin == .aurora`, `palette == .auroraMintIris`, and `defaultDestFolder`
  ends in `/Downloads`.
- `test_setPersistsToDefaults` — set `defaultMaxHeight = 720`; a new
  `Preferences` over the same suite reads `720`.
- `test_maxAutoAttemptsClampedTo1through5` — setting `0` stores `1`, setting
  `9` stores `5`.
- `test_lastUsedDefaultsToDefaultDest` — untouched, `lastUsedDestFolder ==
  defaultDestFolder`.

- [x] **Step 2: Run — verify fail**

Run: `tuist test --test-targets GrabberKitTests/DownloadRequestTests GrabberKitTests/PreferencesTests`
Expected: FAIL — types undefined.

- [x] **Step 3: Implement the types**

- Value types are plain structs; `DownloadKind` / `ErrorClass` / `JobState`
  hand-rolled `Codable` where associated values need it (`JobState` is not
  `Codable` in Phase 1 — no persistence yet — only `Equatable`/`Sendable`).
- `Progress.fraction` is clamped to `0...1` in an `init` or on set.
- `Preferences` — a small `@AppStorage`-free implementation: computed
  properties over `defaults.object(forKey:)` / `set(_:forKey:)`, keys
  `"mg.defaultMaxHeight"` etc.; `maxAutoAttempts` clamps on set; URL props
  stored as bookmark-free absolute path strings for Phase 1.

- [x] **Step 4: Run — verify pass**

Run: `tuist test --test-targets GrabberKitTests/DownloadRequestTests GrabberKitTests/PreferencesTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/media-grabber/Sources/GrabberKit/Download/DownloadRequest.swift \
        apps/media-grabber/Sources/GrabberKit/Download/Progress.swift \
        apps/media-grabber/Sources/GrabberKit/Download/ErrorClass.swift \
        apps/media-grabber/Sources/GrabberKit/Download/DownloadJob.swift \
        apps/media-grabber/Sources/GrabberKit/Model/Preferences.swift \
        apps/media-grabber/Tests/GrabberKitTests/DownloadRequestTests.swift \
        apps/media-grabber/Tests/GrabberKitTests/PreferencesTests.swift
git commit -m "feat(media-grabber): Phase 1 data model — request, job, progress, error class, preferences"
```
DoD: the types compile, `DownloadRequest` round-trips through `Codable` for
every kind, and `Preferences` defaults match the spec and persist across
instances.

---

## Task 5: `YtDlpArguments` — a `DownloadRequest` → argv, with a redaction seam

Pure. `(DownloadRequest) -> [String]`. Phase 1 subset of flags only. The
redacted view is identical to the real argv today — but the seam exists so
later phases (cookies, proxy creds) redact through it without a new call site.

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Download/YtDlpArguments.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/YtDlpArgumentsTests.swift`

**Interfaces:**
- Consumes: `DownloadRequest`, `DownloadKind`, `AudioCodec` from Task 4.
- Produces:
  ```swift
  public enum YtDlpArguments {
      /// The argv passed to yt-dlp (excludes the executable path itself).
      public static func build(for request: DownloadRequest) -> [String]
      /// Same shape, with secrets masked. Phase 1: identical to build(for:).
      public static func redacted(for request: DownloadRequest) -> [String]
  }
  ```
  Task 10 (`DownloadEngine`) calls `build(for:)`; Task 11's logging calls
  `redacted(for:)`.

**Argv contract (tests assert exact tokens & order):**
1. `["-P", <destFolder.path>]` — download root.
2. `["-o", <outputTemplate>]`.
3. Format selector:
   - `.video(maxHeight: h)` → `["-f", "bv*[height<=\(h)][ext=mp4]+ba[ext=m4a]/bv*[height<=\(h)]+ba/b[height<=\(h)]"]`
     then, if `container != nil`, `["--merge-output-format", container!]`
     (Phase 1 always passes `container: "mp4"` for video from the runway).
   - `.audio(codec: c)` → `["-x", "--audio-format", c.rawValue]`.
4. Progress plumbing, always:
   `["--newline", "--progress", "--progress-template",
     "download:MG|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s"]`
5. `["--no-playlist"]`.
6. `["--no-warnings"]`.
7. The URL, last: `[request.url]`.

- [x] **Step 1: Write the failing tests**

- `test_video1080_mp4` — a `.video(maxHeight: 1080)`, `container: "mp4"` request
  → the full argv snapshot matches the contract above, in order.
- `test_video720_noContainer` — `container: nil` → no `--merge-output-format`.
- `test_audio_m4a` and `test_audio_mp3` — `-x --audio-format m4a` / `mp3`.
- `test_customOutputTemplate` — a non-default template appears verbatim after
  `-o`.
- `test_urlIsLast` — the request URL is the final token.
- `test_progressTemplateIsExact` — the `--progress-template` string equals the
  literal in the contract (Task 6's parser is written against this exact
  format).
- `test_redactedEqualsBuild_phase1` — `redacted(for:) == build(for:)` for every
  request shape above.

- [x] **Step 2: Run — verify fail**

Run: `tuist test --test-targets GrabberKitTests/YtDlpArgumentsTests`
Expected: FAIL — `YtDlpArguments` undefined.

- [x] **Step 3: Implement**

A single `build(for:)` that appends tokens per the contract; `redacted(for:)`
returns `build(for:)` unchanged with a `// Phase 1: no secrets in the argv yet`
note.

- [x] **Step 4: Run — verify pass**

Run: `tuist test --test-targets GrabberKitTests/YtDlpArgumentsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/media-grabber/Sources/GrabberKit/Download/YtDlpArguments.swift \
        apps/media-grabber/Tests/GrabberKitTests/YtDlpArgumentsTests.swift
git commit -m "feat(media-grabber): YtDlpArguments — request to argv with a redaction seam"
```
DoD: snapshot tests pass for video (with/without container), audio m4a/mp3, a
custom template, URL-last ordering, and the exact progress-template string;
`redacted` equals `build` for Phase 1.

---

## Task 6: `ProgressParser` — yt-dlp output lines → events and errors

Pure and fixture-driven. Turns the `--progress-template` stdout lines (the
exact format from Task 5) into `ProgressEvent`s, and recognises a small set of
stderr signatures as `ErrorClass`. Phase 1 classifies only three error classes;
everything else is `.unknown(raw:)`.

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Download/ProgressParser.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/ProgressParserTests.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/Fixtures/ytdlp-video-run.txt`
  — a captured full run: `[download]` lines, the `MG|…` progress-template
  lines, a `[Merger]`/post-processing line, a final line. Capture this once
  from a real `yt-dlp` run during implementation (not in CI).
- Create: `apps/media-grabber/Tests/GrabberKitTests/Fixtures/ytdlp-network-error.txt`
- Create: `apps/media-grabber/Tests/GrabberKitTests/Fixtures/ytdlp-generic-error.txt`

**Interfaces:**
- Consumes: `Progress`, `ErrorClass` from Task 4; the progress-template string
  contract from Task 5.
- Produces:
  ```swift
  public enum ProgressEvent: Sendable, Equatable {
      case progress(Progress)
      case postProcessing        // merging / extracting audio
      case ignored               // a line we don't act on
  }

  public enum ProgressParser {
      /// Parse one stdout line.
      public static func parseStdout(_ line: String) -> ProgressEvent
      /// Scan an stderr line for a known failure signature.
      /// Returns nil when the line carries no error signal.
      public static func classifyStderr(_ line: String) -> ErrorClass?
  }
  ```
  Task 10 feeds every `ProcessLine` here and updates `job.progress` /
  `job.state` from the results.

**Parsing rules (tests pin these):**
- A line beginning `MG|` is a progress line: split on `|` →
  `[_, percentStr, speedStr, etaStr, downloadedBytes, totalBytes]`.
  - `percentStr` like ` 42.3%` → `fraction = 0.423` (strip `%`, trim, /100).
  - `speedStr` like `1.23MiB/s` or `Unknown B/s` → bytes/sec `Double?`
    (`nil` when it contains `Unknown`).
  - `etaStr` like `00:37` or `Unknown` → seconds `Int?` (`mm:ss` or `hh:mm:ss`).
  - `downloadedBytes` / `totalBytes` → `Int64`; `totalBytes` may be `NA` → `nil`.
  - → `.progress(Progress(...))`.
- A line containing `[Merger]`, `[ExtractAudio]`, or `Deleting original file`
  → `.postProcessing`.
- Anything else → `.ignored`.
- `classifyStderr`:
  - contains `Unable to download` + (`getaddrinfo` | `Network is unreachable`
    | `Temporary failure in name resolution` | `Connection reset`) → `.networkDown`
  - starts with `ERROR:` (any other) → `.unknown(raw: <the line>)`
  - no `ERROR:` and no network signature → `nil`
  - (`.depMissing` is raised by the engine when the executable itself is
    absent — not a stderr signature — so it is not produced here.)

- [x] **Step 1: Write the failing tests**

- `test_progressLine_midDownload` — `MG| 42.3%|1.23MiB/s|00:37|1290000|3050000`
  → `.progress` with `fraction ≈ 0.423`, `speedBytesPerSec ≈ 1_289_748`,
  `etaSeconds == 37`, `downloadedBytes == 1_290_000`, `totalBytes == 3_050_000`.
- `test_progressLine_unknownSpeedAndEta` — `MG|  0.0%|Unknown B/s|Unknown|0|NA`
  → `fraction == 0`, `speedBytesPerSec == nil`, `etaSeconds == nil`,
  `totalBytes == nil`.
- `test_progressLine_hundredPercent` — `MG|100.0%|…` → `fraction == 1.0`.
- `test_postProcessingLine` — `[Merger] Merging formats into "x.mp4"` →
  `.postProcessing`.
- `test_plainDownloadLine_ignored` — `[download] Destination: x.f137.mp4` →
  `.ignored`.
- `test_stderr_networkError` — a `getaddrinfo` line → `.networkDown`.
- `test_stderr_genericError` — `ERROR: Video unavailable` →
  `.unknown(raw: "ERROR: Video unavailable")`.
- `test_stderr_nonError_returnsNil` — `[info] Downloading 1 format(s): 137+140`
  → `nil`.
- `test_fixtureRun_producesExpectedEventSequence` — feed every line of
  `ytdlp-video-run.txt` through `parseStdout`; assert the sequence contains a
  monotonic run of `.progress` fractions ending at `1.0`, then a
  `.postProcessing`, and never crashes on any line.
- `test_malformedProgressLine_neverCrashes` — `MG|garbage` and `MG|` and
  `MG|||||` all return `.ignored` (or a best-effort `.progress` with safe
  defaults) without throwing.

- [x] **Step 2: Run — verify fail**

Run: `tuist test --test-targets GrabberKitTests/ProgressParserTests`
Expected: FAIL — `ProgressParser` undefined.

- [x] **Step 3: Implement**

Two static functions, small private helpers for the `mm:ss` and `1.23MiB/s`
parsing. No state. Defensive: any split/parse miss on a `MG|` line falls back
to `.ignored` rather than throwing.

- [x] **Step 4: Run — verify pass**

Run: `tuist test --test-targets GrabberKitTests/ProgressParserTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/media-grabber/Sources/GrabberKit/Download/ProgressParser.swift \
        apps/media-grabber/Tests/GrabberKitTests/ProgressParserTests.swift \
        apps/media-grabber/Tests/GrabberKitTests/Fixtures/ytdlp-*.txt
git commit -m "feat(media-grabber): ProgressParser — progress-template lines to events, stderr to ErrorClass"
```
DoD: fixture-driven tests cover start / mid / 100% / post-processing / ignored
/ network-error / generic-error / non-error lines, and malformed lines never
crash.

---

## Task 7: Skin / palette theming — real plumbing, Aurora hardcoded

The visual system. Built before any screen so the first views read colours and
fonts from the SwiftUI `Environment`, not literals. Phase 1 resolves to
Aurora / Mint & Iris only, but the `Skin` → tokens path is genuine — Phase 9
adds the pickers with no view changes.

Reference: `apps/media-grabber/docs/design-system.md` §2.2 (Aurora axes), §3.1
(spacing), §3.2 (type scale), §3.3 (motion), §5.1 (token list), §5.3 (Aurora /
Mint & Iris values).

**Files:**
- Create: `apps/media-grabber/Sources/App/Theme/Skin.swift`
- Create: `apps/media-grabber/Sources/App/Theme/Palette.swift`
- Create: `apps/media-grabber/Sources/App/Theme/SkinEnvironment.swift`
- Create: `apps/media-grabber/Sources/App/Theme/MotifView.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/ThemeTests.swift`
  — **wait:** theme types live in the `App` target, not `GrabberKit`. Add a new
  test target `AppUnitTests` (`product: .unitTests`, `dependencies:
  [.target(name: "MediaGrabber")]`, sources `Tests/AppUnitTests/**`) to
  `Project.swift` in this task, and put the test at
  `apps/media-grabber/Tests/AppUnitTests/ThemeTests.swift`.

**Interfaces:**
- Consumes: `SkinKind`, `PaletteKind` from Task 4.
- Produces:
  ```swift
  struct PaletteTokens {                 // one Color per design-system §5.1 token
      let ground, panelSolid, panel, panelHi, stroke, hair: Color
      let text, dim, faint, headline, onAccent: Color
      let accent, accent2, warn, danger: Color
      let goFillStart, goFillEnd: Color          // gradient stops (--go-fill)
      let orbStops: [Color]                       // --orb conic stops
      let barFillStart, barFillEnd: Color
      let bannerFillStart, bannerFillEnd: Color
      let glowA, glowB: Color
  }

  enum Skin {
      case tapeDeck, aurora
      init(_ kind: SkinKind)
      var displayFont: (CGFloat, Font.Weight) -> Font   // Sora for Aurora
      var bodyFont:    (CGFloat, Font.Weight) -> Font   // Inter
      var monoFont:    (CGFloat, Font.Weight) -> Font   // JetBrains Mono
      var windowRadius: CGFloat        // Aurora 18
      var cardRadius: CGFloat          // 14
      var controlRadius: CGFloat       // 9
      var pillRadius: CGFloat          // 20
      var chipRadius: CGFloat          // 7
      var hairlineWidth: CGFloat       // 1
      var motif: MotifKind             // .orb for Aurora
  }

  enum MotifKind { case reel, orb }

  func palette(for kind: PaletteKind) -> PaletteTokens   // Phase 1: only .auroraMintIris implemented; others may `fatalError("Phase 9")` or return the Mint & Iris set

  struct Spacing { static let s1: CGFloat = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 22, s6 = 30, s7 = 44 }

  // SwiftUI environment
  struct ResolvedTheme { let skin: Skin; let palette: PaletteTokens }
  extension EnvironmentValues { var theme: ResolvedTheme { get set } }  // default: Aurora / Mint & Iris
  extension View { func theme(_ t: ResolvedTheme) -> some View }

  struct MotifView: View {
      var isActive: Bool
      var size: CGFloat
      // conic-gradient orb from palette.orbStops; 6s linear spin when isActive
      // AND !accessibilityReduceMotion; otherwise static.
  }
  ```
  Fonts: register Sora / Inter / JetBrains Mono as bundled resources (add
  `Sources/App/Resources/Fonts/**` to the app target's `resources` in
  `Project.swift`, plus `ATSApplicationFontsPath` = `Fonts` in the Info.plist).
  If a face is missing at runtime, fall back to `.system` — never crash.

  Task 8 (Onboarding) and Task 11 (Home / MainWindow) read `@Environment(\.theme)`.

**Aurora / Mint & Iris values (design-system §5.3 — pin exactly):**
`ground #0C1013` · `panelSolid #0E1117` · `panel rgba(255,255,255,.05)` ·
`panelHi rgba(255,255,255,.08)` · `stroke rgba(255,255,255,.12)` ·
`hair rgba(255,255,255,.06)` · `text #EDF0F5` · `dim #9AA3B2` ·
`faint #6B7480` · `headline #F4F6FA` · `onAccent #07080B` · `accent #5EF2C8` ·
`accent2 #8B7BFF` · `warn #FFC24B` · `danger #FF7A6B` ·
`goFill #5EF2C8 → #8B7BFF` · `orb [#5EF2C8, #8B7BFF, #FF7A6B, #5EF2C8]` ·
`barFill #5EF2C8 → #8B7BFF` · `bannerFill #FF7A6B → #FFC24B` ·
`glowA rgba(94,242,200,.14)` · `glowB rgba(139,123,255,.16)`.

- [x] **Step 1: Add `AppUnitTests` target + write the failing tests**

Edit `Project.swift` to add the `AppUnitTests` unit-test target. Then
`ThemeTests.swift`:
- `test_auroraSkin_radii` — `Skin(.aurora).windowRadius == 18`, `cardRadius ==
  14`, `controlRadius == 9`, `pillRadius == 20`, `chipRadius == 7`.
- `test_auroraSkin_motifIsOrb` — `Skin(.aurora).motif == .orb`.
- `test_mintIrisPalette_keyTokens` — `palette(for: .auroraMintIris)` has
  `accent == Color(hex: "#5EF2C8")`, `danger == Color(hex: "#FF7A6B")`,
  `ground == Color(hex: "#0C1013")`, and `orbStops.count == 4`.
- `test_defaultEnvironmentTheme_isAuroraMintIris` — a bare
  `EnvironmentValues().theme.palette.accent` equals the Mint & Iris accent.
- `test_spacingScale` — `Spacing.s1 == 4 … Spacing.s7 == 44`.
- `test_motifView_staticUnderReduceMotion` — render `MotifView(isActive: true,
  size: 20)` in an environment with `accessibilityReduceMotion == true`; assert
  no animation is attached (snapshot the view's animation state, or expose an
  internal `isSpinning` for the test).

Add a small `Color(hex:)` helper (in `Palette.swift`) — tests and palette
definitions both use it.

- [x] **Step 2: Run — verify fail**

Run: `tuist test --test-targets MediaGrabber/AppUnitTests`
Expected: FAIL — theme types undefined / target missing.

- [x] **Step 3: Implement**

- `Skin` enum with the fixed Aurora axes; `tapeDeck` may return placeholder
  values (Phase 1 never selects it) but the shape is complete.
- `palette(for:)` returns the Mint & Iris `PaletteTokens` for `.auroraMintIris`;
  the other five cases return the same set for now with a `// Phase 9` note
  (do **not** `fatalError` — keeps the app launchable if a stale pref is read).
- `SkinEnvironment` — an `EnvironmentKey` whose `defaultValue` is
  `ResolvedTheme(skin: Skin(.aurora), palette: palette(for: .auroraMintIris))`.
- `MotifView` — `TimelineView`/`.rotationEffect` animation guarded by
  `@Environment(\.accessibilityReduceMotion)`.

- [x] **Step 4: Run — verify pass**

Run: `tuist test --test-targets MediaGrabber/AppUnitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/media-grabber/Sources/App/Theme/ \
        apps/media-grabber/Sources/App/Resources/Fonts/ \
        apps/media-grabber/Project.swift \
        apps/media-grabber/Tests/AppUnitTests/ThemeTests.swift
git commit -m "feat(media-grabber): skin/palette theming plumbing — Aurora/Mint & Iris"
```
DoD: views can read colours and fonts from `@Environment(\.theme)`; every
Aurora token resolves to the design-system value; `MotifView` is static under
reduce-motion.

---

## Task 8: Onboarding — the installer state machine and the blocking screen

First-run setup. `OnboardingInstaller` (GrabberKit) drives the steps;
`OnboardingView` (App) is the full-window checklist that blocks Home until
`yt-dlp` and `ffmpeg` are present. Reference: spec §5.8, design-system §4.5.

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Onboarding/OnboardingInstaller.swift`
- Create: `apps/media-grabber/Sources/App/Onboarding/OnboardingView.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/OnboardingInstallerTests.swift`

**Interfaces:**
- Consumes: `ProcessRunning`, `ProcessLaunch` (Task 2); `EnvironmentProbe`,
  `EnvironmentReport` (Task 3); `@Environment(\.theme)` (Task 7).
- Produces:
  ```swift
  public enum OnboardingStepID: Sendable, CaseIterable {
      case homebrew          // "Homebrew"
      case downloaderTools   // "Downloader + media tools" (brew install yt-dlp ffmpeg) — required
      case botCheckShield    // "Bot-check shield" (pipx install ...) — recommended, NOT blocking
      case testRun           // "Test run" — a canary probe (Phase 1: skipped/auto-pass, see note)
  }

  public enum OnboardingStepState: Sendable, Equatable {
      case pending
      case running(text: String)     // latest streamed line
      case done
      case failed(reason: String)
      case skipped                   // e.g. homebrew already present
  }

  public struct HomebrewInstallInfo: Sendable {
      public static let command =
        "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      // shown with a Copy button + "Open in Terminal"; NEVER auto-run.
  }

  @MainActor @Observable
  public final class OnboardingInstaller {
      public private(set) var steps: [OnboardingStepID: OnboardingStepState]
      /// true once yt-dlp AND ffmpeg are present (re-probed).
      public private(set) var canProceedToHome: Bool

      public init(probe: EnvironmentProbe = .init(),
                  runner: ProcessRunning = ProcessRunner())

      /// Probe, then run each actionable step in order. Homebrew missing →
      /// leaves `.homebrew` as `.failed` with the command in `reason`,
      /// stops, waits for `recheck()`. botCheckShield failing does not block.
      public func start() async
      /// Re-probe after the user installed Homebrew in Terminal, then resume.
      public func recheck() async
      /// Open Terminal.app at the Homebrew install command (App calls this).
      public func openTerminalForHomebrew()
  }
  ```
  **Phase 1 `testRun` note:** the real canary probe needs `MetadataProbe`
  (Task 9) and `DownloadEngine` (Task 10), which come later. In this task
  `testRun` is wired as a step that immediately reports `.done` when
  `canProceedToHome` is true. Task 11 replaces its body with a real probe of a
  known-stable URL. Leave a `// TODO(Task 11): real canary` marker.

  Task 11's `AppModel` owns an `OnboardingInstaller` and shows `OnboardingView`
  whenever `!installer.canProceedToHome`.

- [x] **Step 1: Write the failing tests**

Use the `FakeProcessRunner` from Task 3 and a fake/injected `EnvironmentProbe`
(add an `EnvironmentProbe` init seam or a `Probing` protocol — a
`protocol EnvironmentProbing { func probe() async -> EnvironmentReport }` that
both the real probe and a fake conform to; update Task 3's type to conform).

- `test_allPresent_skipsToProceed` — probe reports yt-dlp + ffmpeg + brew all
  present → after `start()`, `steps[.homebrew] == .skipped`,
  `steps[.downloaderTools] == .skipped` (or `.done`), `canProceedToHome ==
  true`.
- `test_toolsMissing_brewPresent_installsThenProceeds` — probe: brew present,
  yt-dlp + ffmpeg absent; fake `brew install yt-dlp ffmpeg` exits 0 and the
  re-probe now finds them → `steps[.downloaderTools]` walks
  `.pending → .running → .done`, `canProceedToHome == true`.
- `test_brewMissing_blocksWithCommand` — probe: brew absent → `start()` leaves
  `steps[.homebrew] == .failed`, its `reason` contains
  `HomebrewInstallInfo.command`, `canProceedToHome == false`, and no
  `brew install` was ever attempted.
- `test_recheck_afterBrewInstalled_resumes` — after the blocked state, the fake
  probe is swapped to "brew now present", `recheck()` → installs the tools →
  `canProceedToHome == true`.
- `test_botCheckShieldFailure_doesNotBlock` — `pipx install …` exits non-zero →
  `steps[.botCheckShield] == .failed` but `canProceedToHome == true` and
  `.downloaderTools == .done`.
- `test_downloaderInstallFailure_surfacesReasonAndBlocks` — `brew install`
  exits 1 → `steps[.downloaderTools] == .failed(reason:)` with the stderr tail,
  `canProceedToHome == false`.
- `test_streamedLineShowsInRunningState` — while `brew install` emits lines,
  `steps[.downloaderTools] == .running(text: <last line>)`.

- [x] **Step 2: Run — verify fail**

Run: `tuist test --test-targets GrabberKitTests/OnboardingInstallerTests`
Expected: FAIL — `OnboardingInstaller` undefined.

- [x] **Step 3: Implement the installer**

- `start()`: `await probe.probe()`. If `report.brew == nil` → set `.homebrew`
  `.failed(reason: HomebrewInstallInfo.command)`, return. Else `.homebrew` =
  `.skipped`.
- If `report.isReadyForDownloads` → `.downloaderTools = .skipped`; else run
  `brew install yt-dlp ffmpeg` via `runner`, mapping each `.stdout`/`.stderr`
  line to `.running(text:)`; on exit 0 re-probe and set `.done` (or `.failed`
  if the re-probe still misses them); on non-zero `.failed(reason:)` with the
  last ~5 stderr lines.
- `botCheckShield`: `pipx install bgutil-ytdlp-pot-provider` — same streaming,
  but failure sets `.failed` without touching `canProceedToHome`.
- `testRun`: if `canProceedToHome`, `.done`. (`// TODO(Task 11)`.)
- `canProceedToHome` recomputed after every probe: `report.isReadyForDownloads`.
- `openTerminalForHomebrew()`: `NSWorkspace.open` Terminal.app with the command
  on the clipboard, or an `osascript` `do script` — pick the simpler; it must
  not run the script itself, only place the user in Terminal ready to paste.
  (Guard behind `#if canImport(AppKit)`.)

- [x] **Step 4: Build `OnboardingView` (App)**

Not unit-tested (SwiftUI layout); verified in the Step 6 manual check.
- Full-window `ZStack` over `theme.palette.ground`, centred column, max width
  ~520.
- `MotifView(isActive: true, size: 20)` + "MediaGrabber" wordmark at top.
- Headline (display face, 26/1.05): "Let's get you set up".
- A vertical list of 4 rows, one per `OnboardingStepID`, each:
  state icon (`✓` done · number pending · spinner running · `!` failed in
  `theme.palette.danger`) + plain-language label + a subtitle line.
  - `.running(text:)` shows the streamed line in the mono face, `theme.palette.dim`,
    truncated.
  - `.homebrew` `.failed` expands: the exact command in a mono box, a **Copy**
    button, an **Open in Terminal** button (`installer.openTerminalForHomebrew`),
    and a **Re-check** button (`installer.recheck`).
  - `.downloaderTools` `.failed` shows the reason + a **Retry** button
    (`installer.start`).
- Nothing dismisses this view; it is replaced by Home when
  `installer.canProceedToHome` flips true (Task 11 owns that switch).
- Quality floor: every icon button has a VoiceOver label; buttons are keyboard-
  reachable; the spinner respects reduce-motion (use `ProgressView` which does).

- [ ] **Step 5: Run tests + generate + launch with deps faked absent**

Run: `tuist test --test-targets GrabberKitTests/OnboardingInstallerTests` → PASS.
Then add a debug launch argument `-MGForceOnboarding` that makes `AppModel`
(Task 11) treat the environment as not-ready — note this here; wire it in Task
11. For now, temporarily rename your `yt-dlp` on `PATH`, `tuist generate &&
open` the app, confirm onboarding appears and the install step runs; restore
`yt-dlp`.

- [ ] **Step 6: Commit**

```bash
git add apps/media-grabber/Sources/GrabberKit/Onboarding/OnboardingInstaller.swift \
        apps/media-grabber/Sources/App/Onboarding/OnboardingView.swift \
        apps/media-grabber/Tests/GrabberKitTests/OnboardingInstallerTests.swift
git commit -m "feat(media-grabber): onboarding — installer state machine + blocking checklist screen"
```
DoD: with `yt-dlp`/`ffmpeg` absent, onboarding shows and installs them via a
fake `ProcessRunner` in tests (and really, via brew, in the manual check);
with them present, onboarding is skipped; a missing Homebrew blocks with the
command shown and never auto-runs it; a failing bot-check shield does not block.

---

## Task 9: `MetadataProbe` — resolve a URL to a title

Serialized (one probe at a time), no network in tests. Runs
`yt-dlp -J --no-warnings --no-playlist <url>`, parses the JSON, returns the
title + duration + a definite `isPlaylist: false` (Phase 1 forces
`--no-playlist`). Failures become typed errors, never thrown into the UI.

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Download/MetadataProbe.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/MetadataProbeTests.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/Fixtures/ytdlp-J-video.json`
  — a real `yt-dlp -J` blob for one video, trimmed to the fields used
  (`title`, `duration`, `_type`, `id`, `webpage_url`). Capture during impl.
- Create: `apps/media-grabber/Tests/GrabberKitTests/Fixtures/ytdlp-J-unavailable.txt`
  — captured stderr of a probe against an unavailable video.

**Interfaces:**
- Consumes: `ProcessRunning`, `ProcessLaunch` (Task 2); `EnvironmentReport` /
  the resolved `yt-dlp` path (Task 3).
- Produces:
  ```swift
  public struct MediaMetadata: Sendable, Equatable {
      public let title: String
      public let durationSeconds: Int?
      public let isPlaylist: Bool          // Phase 1: always false
      public let sourceURL: String
  }

  public enum MetadataError: Error, Sendable, Equatable {
      case badURL                // yt-dlp: "is not a valid URL" / no extractor
      case unsupported           // no extractor for this site
      case unavailable           // private / removed / geo
      case network               // resolution / connection failure
      case ytDlpMissing          // the executable isn't where we expect
      case malformedOutput       // exit 0 but unparseable JSON
      case unknown(raw: String)
  }

  public actor MetadataProbe {
      public init(ytDlpURL: URL, runner: ProcessRunning = ProcessRunner())
      /// Serialized by the actor: concurrent callers queue.
      public func probe(_ url: String) async -> Result<MediaMetadata, MetadataError>
  }
  ```
  Task 10 calls `probe` to fill `job.title` before spawning the download.
  Task 11's `HomeView` calls it on paste to arm the runway.

**Mapping (tests pin):**
- exit 0 + valid JSON with `title` → `.success`. `duration` (a number) →
  `Int(rounded)`; absent → `nil`. `_type == "playlist"` never happens
  (`--no-playlist`), but if seen → `isPlaylist: true` (defensive).
- exit non-zero: scan stderr —
  `is not a valid URL` → `.badURL`;
  `Unsupported URL` → `.unsupported`;
  `Video unavailable` | `Private video` | `This video is not available` |
  `blocked it in your country` → `.unavailable`;
  `Unable to download webpage` + a network signature (reuse
  `ProgressParser.classifyStderr` → `.networkDown`) → `.network`;
  else → `.unknown(raw:)`.
- exit 0 but JSON parse fails → `.malformedOutput`.

- [x] **Step 1: Write the failing tests**

Fake runner scripts stdout (the fixture JSON) + exit code per case.
- `test_validVideo_returnsTitleAndDuration` — fixture JSON → `.success` with
  the fixture's `title`, `durationSeconds` matching, `isPlaylist == false`,
  `sourceURL == <input>`.
- `test_noDurationField_returnsNilDuration`.
- `test_badURL_mapsToBadURL` — stderr `'x' is not a valid URL` → `.failure(.badURL)`.
- `test_unavailable_mapsToUnavailable` — the unavailable-stderr fixture →
  `.failure(.unavailable)`.
- `test_networkFailure_mapsToNetwork` — `Unable to download webpage` +
  `getaddrinfo` → `.failure(.network)`.
- `test_exitZeroGarbageJSON_mapsToMalformed`.
- `test_serialization_secondCallWaits` — start two `probe` calls on a fake
  runner that records concurrent invocations; assert the runner is never
  entered twice at once.

- [x] **Step 2: Run — verify fail**

Run: `tuist test --test-targets GrabberKitTests/MetadataProbeTests`
Expected: FAIL — `MetadataProbe` undefined.

- [x] **Step 3: Implement**

- `probe`: build `ProcessLaunch(executableURL: ytDlpURL, arguments: ["-J",
  "--no-warnings", "--no-playlist", url])`; collect all `.stdout` into one
  buffer, all `.stderr` into another; `await result()`.
- exit 0 → `JSONDecoder` into a small `Decodable` (`title`, `duration`,
  `_type`, `webpage_url`); missing `title` → `.malformedOutput`.
- non-zero → the stderr mapping above.
- The actor's own serialization gives the "one at a time" guarantee — no extra
  lock.

- [x] **Step 4: Run — verify pass**

Run: `tuist test --test-targets GrabberKitTests/MetadataProbeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/media-grabber/Sources/GrabberKit/Download/MetadataProbe.swift \
        apps/media-grabber/Tests/GrabberKitTests/MetadataProbeTests.swift \
        apps/media-grabber/Tests/GrabberKitTests/Fixtures/ytdlp-J-*
git commit -m "feat(media-grabber): MetadataProbe — resolve a URL to a title, typed errors"
```
DoD: a fixture `-J` blob parses to `MediaMetadata`; each stderr signature maps
to its `MetadataError`; concurrent probes serialize. Optional live check
(`MG_LIVE_TESTS=1`, off in CI): a real URL returns the real title; a known-bad
URL returns a clean error.

---

## Task 10: `DownloadEngine` — one job, start to finish

An actor. `submit(DownloadRequest) -> DownloadJob`: probe for the title, spawn
one `yt-dlp`, stream its output through `ProgressParser`, push updates onto the
job on the main actor, resolve to `.completed` (exit 0) or `.failed(class)`
(non-zero). Cancellation → SIGTERM + `.cancelled`.

**`submit` contract — enqueue and return (final, not a Phase 1 shortcut).**
`submit` appends a `DownloadJob(.queued)` to an internal queue and returns it
**immediately** — no probe, no spawn, no waiting. A separate always-running
`drain()` task consumes the queue and moves each job
`.queued → .probing → .running → terminal`. In Phase 1 `drain()` runs one job
at a time, FIFO; from Phase 2 it grows into the real rate-limit-aware scheduler
(`AdaptiveConcurrency`, per-host `RateState`, `NetworkMonitor`) **without any
change to `submit`'s signature or to a single caller**. Everything the UI knows
about a job's fate — bad URL, network down, rate-limit, 404, done — arrives as
a `job.state` transition, never as a return value or a thrown error. This is
the correct end-state shape: for a queued job there is no caller waiting on it,
by construction (a playlist add drops N jobs in at once; nothing can await N
probes).

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/DownloadEngineTests.swift`

**Interfaces:**
- Consumes: `ProcessRunning`, `ProcessLine`, `ProcessResult` (Task 2); the
  resolved `yt-dlp` path (Task 3); `DownloadRequest`, `DownloadJob`, `JobState`,
  `Progress`, `ErrorClass` (Task 4); `YtDlpArguments.build` (Task 5);
  `ProgressParser` (Task 6); `MetadataProbe` (Task 9).
- Produces:
  ```swift
  public protocol DownloadEngineProtocol: Sendable {
      /// Enqueue and return immediately with a .queued job.
      @discardableResult
      func submit(_ request: DownloadRequest) async -> DownloadJob
      func cancel(_ jobID: UUID) async
  }

  public actor DownloadEngine: DownloadEngineProtocol {
      public init(ytDlpURL: URL,
                  runner: ProcessRunning = ProcessRunner(),
                  probe: MetadataProbing? = nil)   // nil → builds a MetadataProbe from ytDlpURL
      @discardableResult
      public func submit(_ request: DownloadRequest) async -> DownloadJob
      public func cancel(_ jobID: UUID) async
      /// Every job the engine knows about, in submit order. Phase 1: 0 or 1
      /// non-terminal at a time. The App observes these (@Observable).
      public private(set) var jobs: [DownloadJob]
  }
  ```
  Task 11's `AppModel` holds a `DownloadEngineProtocol`, calls `submit`, keeps
  the returned `DownloadJob`, and renders from `job.state` / `job.progress`
  (all `@Observable`). `submit` never blocks and never reports failure — the
  job's `state` does.

**Job lifecycle (`drain()` drives this; tests pin the timeline):**
1. `submit(request)` → `DownloadJob(request:)` (`state = .queued`), append to
   `jobs`, ensure `drain()` is running, **return the job now**. `await` here
   only hops the actor; it does not wait for work.
2. `drain()` pulls the oldest `.queued` job → `job.state = .probing` →
   `await probe.probe(request.url)`:
   - `.failure(.network)` → `job.state = .failed(.networkDown)`, `finishedAt`,
     next job.
   - `.failure(.ytDlpMissing)` → `.failed(.depMissing)`, next job.
   - other `.failure` → `.failed(.unknown(raw:))`, next job.
   - `.success(meta)` → `job.title = meta.title`, continue.
3. `job.state = .running` → `ProcessLaunch(executableURL: ytDlpURL, arguments:
   YtDlpArguments.build(for: request))`; iterate `execution.lines`:
   - `.stdout(l)` → `ProgressParser.parseStdout(l)`:
     `.progress(p)` → hop to `MainActor`, set `job.progress = p`;
     `.postProcessing` → leave a flag / no-op for Phase 1;
     `.ignored` → nothing.
   - `.stderr(l)` → `ProgressParser.classifyStderr(l)`; keep the *last*
     non-nil class seen in a local `var lastError`.
4. `await execution.result()`:
   - `wasCancelled` → `job.state = .cancelled`, `finishedAt`.
   - `exitCode == 0` → resolve `job.outputFiles` (Phase 1: glob
     `request.destFolder` for files whose name starts with the resolved title
     stem, newest first; if none found, leave `[]`), `job.state = .completed`,
     `job.finishedAt = .now`.
   - `exitCode != 0` → `job.state = .failed(lastError ?? .unknown(raw:
     "yt-dlp exited \(exitCode)"))`, `job.finishedAt = .now`.
   Then `drain()` continues to the next `.queued` job; when none remain it
   suspends until the next `submit` wakes it.
5. `cancel(jobID)` → find the job. If `.running`, cancel the `Task` running its
   line-loop (propagates to `ProcessRunner` → SIGTERM). If `.queued`, just set
   `.cancelled` so `drain()` skips it.

- [ ] **Step 1: Write the failing tests**

`FakeProcessRunner` is scripted with a `[ProcessLine]` sequence + a
`ProcessResult`. Add a `MetadataProbing` protocol (retro to Task 9) and inject
a fake conformer. Tests `await` a small helper that polls `job.state` until
terminal (or a timeout) — since `submit` returns instantly at `.queued`.

- `test_submitReturnsQueuedImmediately` — `submit` resolves with
  `state == .queued` before any probe/spawn happens (assert the fake runner and
  fake probe have not been touched yet).
- `test_happyPath_timeline` — fake probe → `.success(title: "Clip")`; fake
  runner emits three `MG|` progress lines (25%, 60%, 100%) then exits 0 →
  the job reaches `state == .completed`, `title == "Clip"`,
  `progress?.fraction == 1.0`, `finishedAt != nil`.
- `test_stateSequence` — record every `job.state` change → `[.queued, .probing,
  .running, .completed]`.
- `test_progressUpdatesAreObservable` — collect `job.progress?.fraction`
  changes; assert `[0.25, 0.60, 1.0]` in order.
- `test_nonZeroExit_withNetworkStderr_failsNetworkDown` — runner emits a
  `getaddrinfo` stderr line then exits 1 → `state == .failed(.networkDown)`.
- `test_nonZeroExit_noStderrSignature_failsUnknown` — exit 3, no recognised
  stderr → `.failed(.unknown(raw:))` mentioning `3`.
- `test_probeNetworkFailure_failsBeforeSpawning` — fake probe `.failure(.network)`
  → `state == .failed(.networkDown)` and the runner was never invoked.
- `test_cancel_killsChildAndSetsCancelled` — long-running fake; `cancel(job.id)`
  → `state == .cancelled`, and the fake records its stream Task was cancelled.
- `test_cancelQueuedJob_neverRuns` — submit two jobs; cancel the second while
  the first is still running → the second ends `.cancelled` and its request is
  never handed to the runner.
- `test_twoJobsRunFIFONoOverlap` — two `submit`s; the fake runner records
  start/stop timestamps; assert the second starts only after the first stops.
- `test_outputFilesResolvedOnCompletion` — point `destFolder` at a temp dir
  containing `Clip.mp4`; after `.completed`, `job.outputFiles == [<that URL>]`.

- [ ] **Step 2: Run — verify fail**

Run: `tuist test --test-targets GrabberKitTests/DownloadEngineTests`
Expected: FAIL — `DownloadEngine` undefined.

- [ ] **Step 3: Implement**

- Actor state: `jobs: [DownloadJob]`, `drainTask: Task<Void, Never>?`,
  `runningLineTask: Task<Void, Never>?` (the current job's line-loop, for
  `cancel`).
- `submit`: append `DownloadJob(.queued)`; if `drainTask == nil || drainTask
  finished`, start `drainTask = Task { await drain() }`; return the job.
- `drain()`: `while let job = nextQueued()` → run it through
  probe → spawn → line-loop → `result()` → terminal state. When `nextQueued()`
  is nil, set `drainTask = nil` and return (next `submit` restarts it). Skip
  jobs already `.cancelled`.
- All `job.*` mutations the UI observes happen on `@MainActor` — mark
  `DownloadJob` `@MainActor` (it's a UI-facing observable), and the engine
  hops in via `await MainActor.run { … }` for each transition.
- Output-file globbing: `FileManager.contentsOfDirectory`, filter by title
  stem (sanitised the way yt-dlp's `%(title)s` sanitises — strip `/` and
  control chars), sort by modification date descending.
- **Phase 2 seam:** `drain()`'s `while let job = nextQueued()` is exactly where
  the scheduler grows — `nextQueued()` becomes "next job whose host `RateState`
  is `.normal` and `running < AdaptiveConcurrency.current`", and the body runs
  jobs concurrently. `submit` / `cancel` / the job model do not change.

- [ ] **Step 4: Run — verify pass**

Run: `tuist test --test-targets GrabberKitTests/DownloadEngineTests`
Expected: PASS.

- [ ] **Step 5: Live smoke (local only, not CI)**

With `MG_LIVE_TESTS=1`, a hand-run test: `submit` a short real Creative-Commons
URL to a temp dir → the job reaches `.completed` and the file exists on disk.

- [ ] **Step 6: Commit**

```bash
git add apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine.swift \
        apps/media-grabber/Tests/GrabberKitTests/DownloadEngineTests.swift
git commit -m "feat(media-grabber): DownloadEngine — single job probe→download→terminal, actor"
```
DoD: `submit` returns a `.queued` job with zero work done; `drain()` carries it
probe → progress → exit 0 → `.completed` with resolved output files; non-zero
exit classifies; cancelling a running job kills the child and sets
`.cancelled`; cancelling a queued job means it never runs; two jobs run FIFO
with no overlap; a real run (live smoke) lands an actual video file.

---

## Task 11: Integration — `AppModel`, `MainWindow`, `HomeView`, `LogWriter` (closes Phase 1)

Wires every earlier piece into a working app. This is the phase-closing task:
its DoD is the Phase 1 DoD.

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Logging/LogWriter.swift`
- Create: `apps/media-grabber/Sources/GrabberKit/Logging/LogEvent.swift`
- Create: `apps/media-grabber/Sources/App/AppModel.swift`
- Create: `apps/media-grabber/Sources/App/MainWindow.swift`
- Create: `apps/media-grabber/Sources/App/Home/HomeView.swift`
- Create: `apps/media-grabber/Sources/App/Home/RunwayView.swift`
- Modify: `apps/media-grabber/Sources/App/MediaGrabberApp.swift` (host `AppModel`,
  window-frame autosave, wire `-MGForceOnboarding`)
- Create: `apps/media-grabber/Tests/GrabberKitTests/LogWriterTests.swift`
- Create: `apps/media-grabber/Tests/AppUnitTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `EnvironmentProbe`/`EnvironmentProbing` (T3), `Preferences` (T4),
  `DownloadRequest`/`DownloadKind`/`DownloadJob`/`JobState` (T4), theming (T7),
  `OnboardingInstaller` (T8), `MetadataProbe`/`MetadataProbing`/`MediaMetadata`/
  `MetadataError` (T9), `DownloadEngineProtocol` (T10).
- Produces:
  ```swift
  // GrabberKit/Logging
  public enum LogLevel: String, Sendable { case debug, info, warn, error }

  public enum LogEvent: Sendable {
      case appLaunched
      case probeCompleted(url: String, title: String?, ok: Bool)
      case jobStateChanged(jobID: UUID, from: String, to: String)
      case processLaunched(executable: String, argvRedacted: [String])
      case processExited(executable: String, code: Int32)
      // each maps to a stable `event` key + a `fields` dict (spec §8.1)
  }

  public actor LogWriter {
      public init(directory: URL = LogWriter.defaultDirectory,   // ~/Library/Logs/MediaGrabber
                  minLevel: LogLevel = .info,
                  clock: () -> Date = { Date() })
      public func log(_ event: LogEvent, level: LogLevel = .info) async
      public static var defaultDirectory: URL { get }
      // JSON Lines to app.log; os.Logger mirror (subsystem "app.mediagrabber.mac",
      // categories engine/scheduler/deps/ui/persistence); 5 files x 5 MB rotation.
      // Redaction (spec §8.5) applied in the line builder: /Users/<name>/ -> ~,
      // strip cookie/proxy-cred/username/password fields.
  }

  // App
  @MainActor @Observable
  final class AppModel {
      enum Page { case home, preferences, diagnostics }
      var page: Page
      private(set) var needsOnboarding: Bool
      let installer: OnboardingInstaller
      let prefs: Preferences
      private(set) var job: DownloadJob?          // Phase 1: the single job
      private(set) var resolved: MediaMetadata?   // last successful paste probe
      private(set) var probeError: String?

      init(engine: DownloadEngineProtocol,
           probe: MetadataProbing,
           installer: OnboardingInstaller,
           prefs: Preferences,
           log: LogWriter,
           forceOnboarding: Bool = false)

      func onAppear() async            // probe env, set needsOnboarding, log appLaunched
      func resolvePasted(_ url: String) async   // MetadataProbe -> resolved / probeError
      func clearResolved()
      func grab() async               // build DownloadRequest from resolved+prefs, engine.submit, keep job
      func reveal()                   // NSWorkspace.activateFileViewerSelecting(job.outputFiles)
      func cancelJob() async
  }
  ```

- [ ] **Step 1: `LogWriter` — failing tests**

`LogWriterTests.swift` (write to a temp dir; inject a fixed `clock`):
- `test_writesJSONLine_perEvent` — `log(.appLaunched)` → `app.log` has one line,
  valid JSON, keys `ts,level,category,event`, `event == "app.launched"`.
- `test_belowMinLevel_notWritten` — `minLevel: .info`, `log(x, level: .debug)`
  → file unchanged.
- `test_redactsUserPath` — an event whose fields contain
  `/Users/alice/Movies/x.mp4` → the written line has `~/Movies/x.mp4`.
- `test_redactsCredentials` — an event carrying a `proxy` field
  `http://u:p@host` → written as `http://host` (user/pass stripped, host kept).
- `test_rotation` — write >5 MB → `app.log.1` appears, `app.log` continues, at
  most 5 files.
- `test_concurrentWrites_noInterleaving` — 100 concurrent `log` calls → 100
  well-formed lines (the actor serialises).

Implement, verify green.

- [ ] **Step 2: `AppModel` — failing tests**

`AppModelTests.swift` uses a `FakeEngine` (`DownloadEngineProtocol` returning a
job it also lets the test drive) and a `FakeProbe` (`MetadataProbing`).
- `test_onAppear_depsPresent_noOnboarding` — fake env probe ready →
  `needsOnboarding == false`.
- `test_onAppear_depsMissing_needsOnboarding` — not ready → `true`.
- `test_forceOnboardingFlag_overrides` — `forceOnboarding: true` with deps
  present → `needsOnboarding == true`.
- `test_resolvePasted_success_setsResolved` — fake probe `.success` →
  `resolved?.title` set, `probeError == nil`.
- `test_resolvePasted_badURL_setsError` — `.failure(.badURL)` →
  `probeError != nil`, `resolved == nil`.
- `test_grab_buildsRequestFromPrefsAndResolved` — prefs default
  `.video(1080)`, dest `/tmp/x`; after `grab()` the `FakeEngine` received a
  `DownloadRequest` with `url == resolved.sourceURL`, `kind == .video(1080)`,
  `destFolder == /tmp/x`, `container == "mp4"`.
- `test_grab_keepsJobReference` — after `grab()`, `model.job != nil`.
- `test_reveal_callsWorkspaceWithOutputFiles` — inject a fake reveal sink;
  assert it got `job.outputFiles`.
- `test_cancelJob_callsEngineCancel`.

Implement, verify green.

- [ ] **Step 3: `MainWindow` (App, not unit-tested)**

- Brand row: `MotifView(isActive: <any job running>, size: 20)` + "MediaGrabber"
  wordmark (display face) left; nav `Home · Preferences · Diagnostics` right,
  active page gets a `theme.palette.panel` fill (spec §5.2 / design-system §4.1).
- Health strip: one static `online` chip only (green dot). No shield/engine/
  cooldown chips in Phase 1. Mono face, `theme.palette` colors.
- No warning banner in Phase 1.
- Page switch: `switch appModel.page` → `HomeView` / empty `PreferencesView`
  placeholder / empty `DiagnosticsView` placeholder.
- Window: `.frame(minWidth: 760)`, default 980×720, `.windowFrameAutosaveName`
  so size/position persist (spec §5.11).

- [ ] **Step 4: `HomeView` + `RunwayView` (App, not unit-tested)**

Follows design-system §4.2.1–4.2.2 and spec §5.3.
- **First-run state** (no download ever made — track with a
  `@AppStorage("mg.hasGrabbedOnce")` bool): kicker + hero headline
  (32/1.04, display face) + the paste field, then three step cards
  ("Paste a link", "Pick a format", "Press Grab"). No table, no runway.
- **Paste** → `appModel.resolvePasted`. While probing, a subtle spinner in the
  field's trailing area. On success: field shows inline `✓ <title>` (mono,
  `theme.palette.accent`); `RunwayView` appears attached below (field rounds
  top-only, runway rounds bottom-only — one unit).
- On probe failure: `theme.palette.danger` text with the reason; no runway.
- **`RunwayView`**: a row of labelled slots — `Link · Type · Format · Save to`.
  Each: filled dot `●` (`accent`) when set, hollow `○` (`faint`) when not.
  - `Link` — filled once `resolved != nil`.
  - `Type` — `Menu` (Video / Audio), seeded from `prefs.defaultKind`.
  - `Format` — contextual `Menu`: heights [2160,1440,1080,720,480,360] for
    Video, [m4a, mp3] for Audio. Seeded from prefs.
  - `Save to` — `Menu`: `prefs.lastUsedDestFolder`, plus "Choose…"
    (`NSOpenPanel`, directories only). Updates `prefs.lastUsedDestFolder`.
  - **Grab** button past a divider: disabled (opacity .3, grayscale) until all
    four slots set. Label `Grab`. Aurora `--go-fill` gradient
    (`theme.palette.goFillStart/End`). On tap → `appModel.grab()`, set
    `hasGrabbedOnce = true`.
- **After first Grab**: step cards gone permanently; a one-row job list renders
  below the field:
  - the row shows `job.title`, a progress bar (`theme.palette.barFill`
    gradient, `job.progress?.fraction`), and a status word from `job.state`
    (`Queued` / `Resolving…` / `Downloading` / `Saved` / `Failed — <reason>` /
    `Cancelled`).
  - `.running` → a small `MotifView(isActive: true, size: 14)` on the row.
  - `.completed` → a **Reveal** button → `appModel.reveal()`.
  - `.running` → a **Cancel** button → `appModel.cancelJob()`.
  - `.failed` → the human copy for the `ErrorClass` (Phase 1 set:
    `.networkDown` → "No internet connection.", `.depMissing` → "yt-dlp is
    missing — reopen setup.", `.unknown` → "Download failed." + the raw in a
    disclosure).
- Quality floor (spec §5.11): full keyboard nav, visible focus, VoiceOver
  labels on the Reveal/Cancel/Choose icon-buttons, reduce-motion honoured, the
  row list scrolls inside its own container, page never scrolls sideways.

- [ ] **Step 5: Wire `MediaGrabberApp` + compose the object graph**

- `MediaGrabberApp` builds the real graph at launch: resolve `yt-dlp` via
  `EnvironmentProbe`, construct `MetadataProbe(ytDlpURL:)`,
  `DownloadEngine(ytDlpURL:)`, `LogWriter()`, `OnboardingInstaller()`,
  `Preferences()`, then `AppModel(...)`. Hold it in `@State`.
- `-MGForceOnboarding` in `CommandLine.arguments` → `forceOnboarding: true`.
- Body: `if appModel.needsOnboarding { OnboardingView(installer:) } else {
  MainWindow() }`, both `.environment(\.theme, ResolvedTheme(... from prefs ...))`
  and `.environment(appModel)`.
- `.task { await appModel.onAppear() }`.
- After onboarding's installer flips `canProceedToHome`, `AppModel` re-probes
  (an `onChange` or the installer calling back) and clears `needsOnboarding`.

- [ ] **Step 6: Run the full suite + build**

Run: `cd apps/media-grabber && tuist test && tuist build`
Expected: all `GrabberKitTests` + `AppUnitTests` pass; app builds.

- [ ] **Step 7: Manual Phase-1 DoD walkthrough**

On a real machine:
1. (Deps present) launch → Home first-run state, `online` chip green.
2. Paste a normal video URL → `✓ <title>` appears, runway arms on defaults.
3. Press Grab → step cards vanish, the job row shows a live progress bar.
4. Bar reaches 100 % → row says **Saved**, **Reveal** opens Finder on the file
   in `~/Downloads`.
5. Quit `tuist generate`, rename `yt-dlp` on PATH, relaunch → onboarding takes
   over and blocks Home; restore `yt-dlp`, hit Re-check → Home returns.

- [ ] **Step 8: Commit**

```bash
git add apps/media-grabber/Sources/GrabberKit/Logging/ \
        apps/media-grabber/Sources/App/ \
        apps/media-grabber/Tests/GrabberKitTests/LogWriterTests.swift \
        apps/media-grabber/Tests/AppUnitTests/AppModelTests.swift
git commit -m "feat(media-grabber): Phase 1 integration — AppModel, MainWindow, Home, LogWriter"
git tag phase-1
```
DoD: **the phase is done.** Launch → (onboarding if needed) → paste a real URL
→ Grab on defaults → watch the bar → file in `~/Downloads` → "Saved" → Reveal
opens Finder. `tuist test` green. The manual smoke checklist (Task 12) passes.

---

## Task 12: Leaf docs + Phase-1 smoke checklist

**Files:**
- Create: `apps/media-grabber/README.md`
- Create: `apps/media-grabber/PRIVACY.md`
- Create: `apps/media-grabber/ticket-backlog.md`
- Modify: `BACKLOG.md` — **no change in Phase 1** (spec §14: T-002 and T-006
  rows unchanged, no new row until v1). Listed here only so the executor
  doesn't touch it.

**Interfaces:** none (documentation).

- [ ] **Step 1: `README.md`**

Sections: what it is (one paragraph); requirements (macOS 14+, Homebrew — the
app installs `yt-dlp` + `ffmpeg` for you on first run); build from source
(`brew install mise`, `mise install`, `tuist generate`, open, run); the
one-time Gatekeeper step for a downloaded build (System Settings → Privacy &
Security → **Open Anyway**, or `xattr -dr com.apple.quarantine
/Applications/MediaGrabber.app`); where files land (`~/Downloads` by default);
where logs live (`~/Library/Logs/MediaGrabber/`, all local — see PRIVACY.md);
Phase 1 scope + known gaps (no queue, no resume — a quit mid-download loses it).
License MIT.

- [ ] **Step 2: `PRIVACY.md`**

Per spec §8.5. What the logs contain in the clear (video URLs, titles, the
destination folder as `~/…`). What is always redacted (cookies, proxy
credentials, usernames/passwords, absolute `/Users/<name>/` paths). No
telemetry, no network egress from logging — ever. Logs never leave the machine
unless the user manually shares a bundle (not in Phase 1).

- [ ] **Step 3: `ticket-backlog.md`**

Seed the leaf backlog: Phase 2 (queue + real table), Phase 3 (persistence),
Phases 4–11 as one-liners from spec §12.2, plus any Phase-1 follow-ups the
build surfaced (e.g. "canary probe in onboarding still stubbed — Task 11 left
it auto-pass"). Note the deferred product-name decision (spec §14).

- [ ] **Step 4: Run the Phase-1 manual smoke checklist**

The full list (spec §11.3 / §12.1 step 12):
- fresh-machine onboarding installs the deps
- happy-path **video** download → Saved → Reveal
- happy-path **audio** (m4a) download → Saved → Reveal
- **bad URL** → clean inline error on the field, no crash, no row added
- **cancel** mid-download → row shows Cancelled, the `yt-dlp` child is gone
  (`pgrep yt-dlp` empty), the `.part` file may remain (documented)
- **quit** mid-download → the child is killed; on relaunch the job is gone
  (no resume yet — a documented Phase 1 gap)

Record pass/fail for each in the commit message.

- [ ] **Step 5: Commit**

```bash
git add apps/media-grabber/README.md apps/media-grabber/PRIVACY.md \
        apps/media-grabber/ticket-backlog.md
git commit -m "docs(media-grabber): Phase 1 leaf README, PRIVACY, backlog; smoke checklist passed"
```
DoD: the smoke checklist passes on a real machine and the result is recorded in
the commit.

---

## Self-Review

**Spec coverage (§12.1 build order → tasks):**
1 skeleton → T1 · 2 ProcessRunner → T2 · 3 EnvironmentProbe → T3 ·
4 data types → T4 · 5 YtDlpArguments → T5 · 6 ProgressParser → T6 ·
7 skin/palette → T7 · 8 OnboardingInstaller+View → T8 · 9 MetadataProbe → T9 ·
10 DownloadEngine → T10 · 11 HomeView+MainWindow+AppModel+LogWriter → T11 ·
12 leaf docs + smoke → T12. All twelve covered.

**Spec §5.3 / §5.8 / §5.11 UI requirements** → T7 (theme), T8 (onboarding UI),
T11 (Home first-run/runway/job-row, MainWindow chrome, window autosave, quality
floor). **§8.1 / §8.5 logging + redaction** → T11 (`LogWriter`). **§9 error
classes** → T4 (enum) + T6 (classification) + T11 (failure copy). **§10 signing**
→ T1 (ad-hoc, hardened-runtime-off, sandbox-off build settings). **§11 testing**
→ every task is TDD; live tests gated `MG_LIVE_TESTS=1` (T9, T10); manual smoke
in T12.

**Deviations from spec, all deliberate:**
- `DownloadEngine.submit` is enqueue-and-return (Option B), not the spec's
  implied "submit … waits FIFO in-actor". Rationale: it is the correct
  end-state once Phase 2 adds the scheduler; building it now avoids a rewrite.
  The FIFO behavior is preserved via `drain()`.
- `DownloadJob` drops `playlistGroupID` / `playlistProgress` for Phase 1
  (no playlists); re-added in Phase 7.
- Onboarding's `testRun` canary is stubbed auto-pass in T8, given a real body
  in T11 (it needs `MetadataProbe`, which lands in T9).
- `SkinKind` / `PaletteKind` string enums live in `GrabberKit` (for
  `Preferences`), the `Color`/`Font`-bearing `Skin` / `Palette` in `App`.

**Type consistency:** `ProcessRunning`/`ProcessLaunch`/`ProcessLine`/
`ProcessExecution`/`ProcessResult` (T2) used verbatim in T3, T8, T9, T10.
`EnvironmentProbing` added in T3, consumed T8, T11. `MetadataProbing` added in
T9, consumed T10, T11. `DownloadEngineProtocol` (T10) consumed T11.
`ResolvedTheme` / `@Environment(\.theme)` (T7) consumed T8, T11.
`ErrorClass` / `JobState` / `Progress` (T4) flow through T6, T10, T11.

**Placeholder scan:** no "TBD"/"implement later"/"add error handling" left; each
task carries its interface signatures, its test list, and a concrete DoD.
Implementation bodies are intentionally sketched (not full code) per the plan
owner's instruction — the pinned interfaces + test lists make each body
determinate under TDD.

---

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-08-29-media-grabber-phase-1.md`. Two execution
options:

1. **Subagent-Driven (recommended)** — a fresh subagent per task, review
   between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using
   `superpowers:executing-plans`, batched with review checkpoints.

Which approach?
