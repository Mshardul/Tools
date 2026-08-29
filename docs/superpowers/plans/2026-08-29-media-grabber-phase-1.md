# MediaGrabber Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Mark a task's steps done before starting the next; wait for the human's go-ahead between tasks. Commit cadence is the human's call, not a plan step.
>
> **Comments in code:** single-line only, only for *why*, only when the names don't already carry it. No `///` doc comments, no stacked `//` blocks. `.swiftformat` disables `docComments`; `.swiftlint.yml` disables `todo` (the one `// TODO(Task 11)` marker in `OnboardingInstaller` is deliberate).

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
`@Observable`, `Foundation.Process`, `os.Logger`. Tuist 4.205.0 for project
generation, mise for tool version pinning (tuist 4.205.0, swiftformat 0.62.1,
swiftlint 0.65.1 — all pinned exactly in `.mise.toml`). GitHub Actions on
`macos-14`; local builds run on the current Xcode. `yt-dlp` + `ffmpeg` are
external runtime dependencies (Homebrew), never bundled.

**Concurrency shape.** `GrabberKit` targets macOS 14, so `Synchronization.Mutex`
(macOS 15) is unavailable — internal locking uses a small `os_unfair_lock`
wrapper. Swift actors are reentrant across `await`, so an actor that must
serialize work through a suspension point (`MetadataProbe`) chains its calls on
an internal `Task`, not on actor isolation alone. `ProcessRunner` streams pipe
output on dedicated blocking reader threads rather than `readabilityHandler`s,
because the handler-plus-termination approach dropped lines under the test
suite's concurrent execution.

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
  implementation, for every unit.
- **No network in tests.** Real-network integration tests are gated behind the
  `MG_LIVE_TESTS=1` environment variable and are off in CI. Fixtures are
  captured once from real `yt-dlp` runs against Creative-Commons sources
  (`commons.wikimedia.org`, `archive.org`) — YouTube is unreachable without a
  POT provider, which is out of Phase 1.
- **`GrabberKit` imports no SwiftUI** and has no dependency on the `App` target.
- **Phase 1 skin:** Aurora / Mint & Iris only. No skin or palette picker UI, but
  the `Skin` / `Palette` / environment plumbing is real (not hardcoded literals
  in views). The Aurora typefaces (Sora / Inter / JetBrains Mono) are not
  bundled — `Skin`'s font accessors resolve the family if present and fall back
  to the system face otherwise. Bundling the faces is a tracked follow-up, not
  Phase 1.
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
  Project.swift                         # Tuist: MediaGrabber + GrabberKit + GrabberKitTests + AppUnitTests
  Tuist/
    Config.swift                        # Tuist config
  .mise.toml                            # pins tuist, swiftformat, swiftlint (exact versions)
  .gitignore                            # leaf-scoped: *.xcodeproj, *.xcworkspace, Derived/
  .swiftformat                          # --disable docComments; Derived/ excluded
  .swiftlint.yml                        # disabled_rules: [todo]; Derived/ excluded
  README.md                             # build steps + Gatekeeper "Open Anyway"
  PRIVACY.md                            # what the logs contain, all local
  ticket-backlog.md                     # leaf backlog (incl. bundle the Aurora fonts)
  docs/
    design-system.md                    # (exists)
    mockups/screens.html                # (exists)
  Sources/
    App/
      MediaGrabberApp.swift             # @main, single WindowGroup, -MGForceOnboarding
      AppModel.swift                    # @MainActor @Observable: deps, job, page
      MainWindow.swift                  # brand row + health strip + nav + page switch
      Theme/
        Skin.swift                      # Skin enum: font resolvers (system fallback), radii, motif; Spacing
        Palette.swift                   # PaletteTokens struct, palette(for:), Color(hex:)
        SkinEnvironment.swift           # @Entry EnvironmentValues.theme -> ResolvedTheme
        MotifView.swift                 # conic-gradient orb; isSpinning(reduceMotion:) for tests
      Onboarding/
        OnboardingView.swift            # full-window checklist, blocks Home
      Home/
        HomeView.swift                  # field + step cards / runway / one-row job list
        RunwayView.swift                # labelled slots + Grab button
    GrabberKit/
      Onboarding/
        ProcessRunner.swift             # async Process wrapper; blocking reader threads
        EnvironmentProbe.swift          # locate + version brew/yt-dlp/ffmpeg; EnvironmentProbing
        OnboardingInstaller.swift       # first-run setup state machine
      Download/
        DownloadRequest.swift           # immutable request value + AudioCodec / DownloadKind
        DownloadJob.swift               # @MainActor @Observable per-row state + JobState
        Progress.swift                  # progress value type, fraction clamped 0...1
        ErrorClass.swift                # error classification enum (full spec §9 case list)
        YtDlpArguments.swift            # build(for:) -> [String]; redacted(for:) seam
        ProgressParser.swift            # progress-template lines -> ProgressEvent; stderr -> ErrorClass
        MetadataProbe.swift             # yt-dlp -J -> title/duration; serialized via Task chain
        DownloadEngine.swift            # actor: submit enqueues, drain() drives each job to terminal
      Model/
        Preferences.swift               # @Observable, UserDefaults-backed; SkinKind / PaletteKind
      Logging/
        LogWriter.swift                 # actor: JSON Lines + os.Logger mirror
        LogEvent.swift                  # event enum + schema + redaction helpers
  Tests/
    GrabberKitTests/
      Support/
        FakeProcessRunner.swift         # ProcessRunning fake, os_unfair_lock LockedBox
        FakeEnvironmentProbe.swift      # EnvironmentProbing fake, scripted report sequence
      Fixtures/                         # checked-in real yt-dlp output samples + shell helpers
      SmokeTests.swift
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
    AppUnitTests/
      ThemeTests.swift
      AppModelTests.swift               # AppModel logic with a fake engine
```

**Responsibilities.** `ProcessRunner` is the only place `Foundation.Process` is
touched. `DownloadEngine` is the only component that spawns download processes.
`ProcessRunner`, `EnvironmentProbe`, `YtDlpArguments`, `ProgressParser`,
`Progress`, `ErrorClass`, `Preferences` are pure or fixture-testable. The `App`
target holds only SwiftUI and reads everything else from `GrabberKit`.

**Test doubles.** `FakeProcessRunner` and `FakeEnvironmentProbe` live in
`Tests/GrabberKitTests/Support/` and are shared across every suite that needs
them. `FakeProcessRunner` matches scripts by executable path (full path, then
last component), records launches, tracks peak concurrency, and takes an
optional per-run delay to widen concurrency windows. Its state sits behind a
`LockedBox` (`os_unfair_lock`), since Swift 6 forbids `NSLock` in async
contexts and `Mutex` needs macOS 15. `FakeEnvironmentProbe` returns a scripted
sequence of `EnvironmentReport`s, one per `probe()` call (the last repeats), so
"install, then re-probe finds the tools" is deterministic without timing.

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
- Create: `apps/media-grabber/Tests/GrabberKitTests/Fixtures/` (dir; populated in later tasks)
- Create: `.github/workflows/media-grabber.yml`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - A Tuist project at `apps/media-grabber/` with four targets: `MediaGrabber`
    (app, bundle ID `app.mediagrabber.mac`, deployment target macOS 14.0,
    `LSMinimumSystemVersion 14.0`), `GrabberKit` (framework), `GrabberKitTests`
    (unit tests for `GrabberKit`), `AppUnitTests` (unit tests for `MediaGrabber`
    — added in Task 7).
  - `tuist generate` produces `MediaGrabber.xcworkspace` (gitignored); the
    `MediaGrabber-Workspace` scheme builds and tests both test bundles.
  - App target has `CODE_SIGN_IDENTITY = "-"`, `CODE_SIGN_STYLE = Manual`,
    `ENABLE_HARDENED_RUNTIME = NO`, `ENABLE_APP_SANDBOX = NO`.

**Build & test commands.** `mise exec -- tuist generate --no-open` after adding
or removing files. Build and test through xcodebuild on the generated
workspace, not `tuist test` — `tuist test`'s output filtering hides compiler
errors:
```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' test
```
Lint: `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict`.

- [x] **Step 1: Pin the toolchain**

```bash
brew install mise
cd apps/media-grabber
mise use tuist@latest swiftformat@latest swiftlint@latest
mise install
```
Then rewrite `.mise.toml` to pin exact versions (mise writes `latest`; CI needs
determinism). `swiftformat` needs `no_app = true` on macOS:
```toml
[tools]
tuist = "4.205.0"
swiftformat = { version = "0.62.1", no_app = true, rename_exe = "swiftformat" }
swiftlint = "0.65.1"
```

- [x] **Step 2: Write `Tuist/Config.swift`**

```swift
import ProjectDescription

let config = Config(
    fullHandle: nil,
    generationOptions: .options()
)
```
(Tuist warns this path is deprecated in favour of `Tuist.swift` at the leaf
root; the deprecated path still works and the plan keeps it for now.)

- [x] **Step 3: Write `Project.swift`**

Four targets. `AppUnitTests` is added here in the file structure even though its
first test lands in Task 7, so `Project.swift` is not re-edited mid-plan.

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
            "MACOSX_DEPLOYMENT_TARGET": "14.0"
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release")
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
                "NSHumanReadableCopyright": "MIT"
            ]),
            sources: ["Sources/App/**"],
            resources: [],
            dependencies: [.target(name: "GrabberKit")],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "-",
                "CODE_SIGN_STYLE": "Manual",
                "ENABLE_HARDENED_RUNTIME": "NO",
                "ENABLE_APP_SANDBOX": "NO"
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
        .target(
            name: "AppUnitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "app.mediagrabber.mac.tests",
            deploymentTargets: .macOS("14.0"),
            sources: ["Tests/AppUnitTests/**"],
            dependencies: [.target(name: "MediaGrabber")]
        )
    ]
)
```

- [x] **Step 4: Write the leaf `.gitignore`**

```gitignore
*.xcodeproj
*.xcworkspace
Derived/
.build/
*.xcuserstate
xcuserdata/
```

- [x] **Step 5: Write `.swiftformat` and `.swiftlint.yml`**

`.swiftformat` — `docComments` is disabled (it promotes single-line `//` above a
declaration to `///`, which the comment rule forbids); `Derived/` is excluded so
Tuist's generated bundle sources don't fail the lint:
```
--swiftversion 6.0
--exclude Derived,Tuist/.build,.build
--indent 4
--maxwidth 100
--wraparguments before-first
--wrapparameters before-first
--self remove
--commas inline
--trimwhitespace always
--disable docComments
```

`.swiftlint.yml` — `todo` is disabled (Task 8 leaves an intentional
`// TODO(Task 11)` marker); `Derived/` excluded:
```yaml
included:
  - Sources
  - Tests
excluded:
  - Derived
  - .build
  - Tuist/.build
disabled_rules:
  - todo
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
Task 11 replaces this body with the real `AppModel` graph.

`Sources/GrabberKit/GrabberKit.swift` — a placeholder so the framework compiles
before its real types exist:
```swift
public enum GrabberKit {
    public static let name = "GrabberKit"
}
```

- [x] **Step 7: Write the smoke test**

`Tests/GrabberKitTests/SmokeTests.swift`:
```swift
@testable import GrabberKit
import XCTest

final class SmokeTests: XCTestCase {
    func test_grabberKitName() {
        XCTAssertEqual(GrabberKit.name, "GrabberKit")
    }
}
```

- [x] **Step 8: Generate, build, test locally**

```bash
cd apps/media-grabber
mise exec -- tuist generate --no-open
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' test
mise exec -- swiftformat --lint .
mise exec -- swiftlint lint --strict
```
Expected: workspace generates (gitignored), the smoke test passes, lint is
clean, and running the app opens a window titled "MediaGrabber".

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

DoD: `tuist generate` + the xcodebuild test command pass locally; lint is
clean; launching the app opens a window. The CI runner uses `macos-14` / an
older Xcode than local — nothing in the code assumes a specific Xcode beyond
`SWIFT_VERSION = 6.0` and the macOS 14 deployment target.

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
- Create: `apps/media-grabber/Tests/GrabberKitTests/Fixtures/hang.sh`
  (`exec sleep 60` — `exec` so a SIGTERM reaches `sleep` directly instead of
  orphaning it under the shell; used for the cancellation test)

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
      public init(exitCode: Int32, wasCancelled: Bool)
  }

  public protocol ProcessRunning: Sendable {
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
  `lines` streams stdout/stderr as they arrive and finishes when the process
  exits; `result()` then yields the exit code. Cancelling the `Task` that
  awaits `result()` (or iterates `lines`) sends `SIGTERM` to the child and sets
  `ProcessResult.wasCancelled == true`. Later tasks depend on the exact names
  `ProcessRunner`, `ProcessRunning`, `ProcessLaunch`, `ProcessLine`,
  `ProcessExecution`, `ProcessResult`, and on `ProcessResult`'s public
  memberwise init (the fakes construct it directly).

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
  `Task`, cancel it after 100ms → `result()` returns `wasCancelled == true`
  within ~5s (not 60s). Build the `ProcessLaunch` before the `Task` and capture
  only `Sendable` values into it — an `XCTestCase` instance is not `Sendable`,
  so a helper method that builds the launch cannot be called from inside the
  `Task` under Swift 6.
- `test_environment_isPassedThrough` — `/bin/sh -c 'echo $MG_TEST'` with
  `environment: ["MG_TEST": "xyz"]` (merged onto the parent env) → `.stdout("xyz")`.

Make the two fixture scripts executable and add them to the test target's
`Fixtures/` resource bundle. Resolve them at test time via
`Bundle.module.url(forResource:withExtension:)`.

- [x] **Step 2: Run the tests — verify they fail**

```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' -only-testing:GrabberKitTests/ProcessRunnerTests test
```
Expected: FAIL — `ProcessRunner` / the protocol types are not defined.

- [x] **Step 3: Implement `ProcessRunner`**

- `run(_:)` builds a `Foundation.Process` + two `Pipe`s and starts it. Each
  pipe is drained on its own dedicated blocking-`read` thread; a `LineSplitter`
  per pipe buffers partial lines and flushes the tail at EOF. A 2-count latch
  finishes the `AsyncStream` only once *both* reader threads have hit EOF, so no
  line is dropped. (`readabilityHandler` + a `terminationHandler` drain was
  tried first and dropped stdout under the concurrently-run test suite.)
- A third thread calls `process.waitUntilExit()` and publishes the
  `ProcessResult` through a small `@unchecked Sendable` box that supports one
  producer and many awaiters.
- `result()` wraps the await in `withTaskCancellationHandler`; on cancel it
  calls `process.terminate()` (SIGTERM) and records `wasCancelled = true`.
- `environment: nil` inherits `ProcessInfo.processInfo.environment`; a non-nil
  value is merged onto the parent, caller keys winning.
- Nothing throws out of `run` / `result`; a launch failure surfaces as
  `exitCode == 127` plus a `.stderr` line.
- Internal locking uses `os_unfair_lock`, not `NSLock` (Swift 6 forbids
  `NSLock.lock()` in async contexts) and not `Mutex` (macOS 15). Decode pipe
  bytes with `String(bytes:encoding:)` (swiftlint's
  `optional_data_string_conversion`), with an ISO-Latin-1 fallback.

- [x] **Step 4: Run the tests — verify they pass**

Same command as Step 2. Expected: PASS (all 7). Run the full suite too — the
line-drop bug only showed under concurrent execution.

DoD: every process-control path (exit 0, exit non-zero, stdout, stderr, ordered
multi-line, cancel→SIGTERM, env pass-through) is covered by a passing
fixture-backed test; the full suite is stable across repeated runs; no orphan
child processes remain (`pgrep` the fixture is empty after the cancel test); no
network.

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
      public init(path: URL, version: String)
  }

  public struct EnvironmentReport: Sendable, Equatable {
      public let brew: ToolInfo?
      public let ytDlp: ToolInfo?
      public let ffmpeg: ToolInfo?
      public var isReadyForDownloads: Bool { ytDlp != nil && ffmpeg != nil }
      public init(brew: ToolInfo?, ytDlp: ToolInfo?, ffmpeg: ToolInfo?)
  }

  public protocol EnvironmentProbing: Sendable {
      func probe() async -> EnvironmentReport
  }

  public struct EnvironmentProbe: EnvironmentProbing {
      public init(runner: ProcessRunning = ProcessRunner(),
                  extraSearchPaths: [URL] = EnvironmentProbe.defaultSearchPaths,
                  isExecutable: @escaping @Sendable (URL) -> Bool =
                      { FileManager.default.isExecutableFile(atPath: $0.path) })
      public func probe() async -> EnvironmentReport

      // /opt/homebrew/bin, /usr/local/bin, /usr/bin, ~/.local/bin, then $PATH.
      public static var defaultSearchPaths: [URL] { get }
  }
  ```
  `EnvironmentProbing` is the seam `OnboardingInstaller` (Task 8) and `AppModel`
  (Task 11) test against. `isExecutable` is injectable so a fake can "find"
  executables at paths that don't exist on disk — `FileManager.isExecutableFile`
  can't be pointed at a fixture. `ToolInfo` / `EnvironmentReport` carry public
  memberwise inits (the fakes build them). Later tasks depend on
  `EnvironmentReport`, `ToolInfo`, `EnvironmentProbe`, `EnvironmentProbing`,
  `isReadyForDownloads`.

**Version parsing rules (tests assert them):**
- `brew --version` → first line `Homebrew <version>` → the second token.
- `yt-dlp --version` → the whole first non-empty line is the version; reject it
  (tool "not found") if it doesn't start with a digit or `v`, so an error blob
  isn't mistaken for a version.
- `ffmpeg -version` → first line `ffmpeg version 8.0 Copyright ...` → the token
  after `version`, leading `n` stripped, must start with a digit.
- Unparseable / empty output → the tool is **not found** (`nil`), never a crash.
- These match real `brew` / `yt-dlp` / `ffmpeg` output on macOS — verify against
  the installed tools during implementation.

- [x] **Step 1: Build `FakeProcessRunner` and write the failing tests**

`Tests/GrabberKitTests/Support/FakeProcessRunner.swift` — a `ProcessRunning`
returning a scripted `[ProcessLine]` + exit code per matched executable path
(full path first, then last component, so `["brew"]` matches
`/opt/homebrew/bin/brew`). It records `launches`, tracks `maxConcurrent`, and
takes a `perRunDelay`. State sits behind an `os_unfair_lock` `LockedBox`
(`NSLock.lock()` is banned in async contexts; `Mutex` needs macOS 15). Add
`Script.stdout(_:)` / `Script.stderr(_:)` helpers that split a blob on
newlines.

`EnvironmentProbeTests.swift` — inject the fake plus a fake `isExecutable`
predicate (a `Set<String>` of "present" paths):
- `test_allToolsPresent_parsesVersions` — the three version strings →
  `brew?.version`, `ytDlp?.version`, `ffmpeg?.version` parsed, `isReadyForDownloads`.
- `test_ytDlpMissing_reportsNilAndNotReady`.
- `test_ffmpegMalformedVersion_treatedAsMissing` — `garbage` for `ffmpeg -version`.
- `test_firstMatchOnSearchPathWins` — `yt-dlp` present in both
  `/opt/homebrew/bin` and `/usr/local/bin`; the report's path is the first.
- `test_noRealBrewOrNetwork` — every recorded launch is under a search-path
  directory; the real `ProcessRunner` is never constructed.

- [x] **Step 2: Run the tests — verify they fail**

```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' -only-testing:GrabberKitTests/EnvironmentProbeTests test
```
Expected: FAIL — `EnvironmentProbe` undefined.

- [x] **Step 3: Implement `EnvironmentProbe`**

- `probe()` runs all three tools concurrently (`async let`). For each: walk
  `searchPaths`, take the first `isExecutable` hit, run its version command
  through the injected `runner`, parse.
- Parsing helpers are `private static` functions on `EnvironmentProbe`,
  exercised through the public `probe()` behavior.

- [x] **Step 4: Run the tests — verify they pass**

Same command as Step 2. Expected: PASS.

DoD: a correct `EnvironmentReport` against fixtures with no real brew and no
network; a missing or malformed tool degrades to `nil` without crashing; the
parsers match the real installed tools' output.

---

## Task 4: Data types — request, job, progress, error class, preferences

The Phase 1 model surface. Pure value types plus one `@MainActor @Observable`
job and one `@Observable` UserDefaults-backed `Preferences`. `ErrorClass` gets
its full spec §9 case list now (later phases fill in the classification logic);
Phase 1 only ever produces `.unknown`, `.networkDown`, `.depMissing`.

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
      public var fraction: Double            // clamped 0.0 ... 1.0, in init and on set
      public var speedBytesPerSec: Double?
      public var etaSeconds: Int?
      public var downloadedBytes: Int64
      public var totalBytes: Int64?
      public init(fraction: Double, speedBytesPerSec: Double? = nil,
                  etaSeconds: Int? = nil, downloadedBytes: Int64,
                  totalBytes: Int64? = nil)
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

  @MainActor @Observable
  public final class DownloadJob: Identifiable {
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
      public var defaultKind: DownloadKind       // derived from the fields below
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
  `DownloadJob` is `@MainActor` (a UI-facing observable — Task 10's engine hops
  to the main actor for every mutation the UI reads). Tests that touch it are
  `@MainActor`.

  `Preferences.defaultKind` is computed from a stored `"mg.defaultKindSelector"`
  (`video` / `audio`) plus `defaultMaxHeight` / `defaultAudioCodec`, so there is
  no separate stored `defaultKind` to fall out of sync. URL props are stored as
  absolute path strings (no security-scoped bookmarks in Phase 1).

  `SkinKind` / `PaletteKind` are `String`-raw enums defined here (the App-side
  `Skin` / `Palette` in Task 7 map from them — `GrabberKit` imports no SwiftUI
  so it cannot hold `Color`/`Font`). `SkinKind`: `tapeDeck, aurora`.
  `PaletteKind`: `auroraMintIris, auroraLimeForest, auroraMagentaViolet,
  tapeDeckA, tapeDeckB, tapeDeckC` (Phase 1 uses only `auroraMintIris`).

  Later tasks depend on: `DownloadRequest`, `DownloadKind`, `AudioCodec`,
  `Progress` (+ its memberwise init), `ErrorClass`, `JobState`, `DownloadJob`,
  `Preferences`, `SkinKind`, `PaletteKind`.

- [x] **Step 1: Write the failing tests**

`DownloadRequestTests.swift`:
- `test_defaultOutputTemplate` — a `DownloadRequest` built without
  `outputTemplate` has `"%(title)s.%(ext)s"`.
- `test_codableRoundTrip_video` — encode→decode a `.video(maxHeight: 720)`
  request → equal to the original.
- `test_codableRoundTrip_audio` — same for `.audio(codec: .mp3)`.
- `test_errorClass_unknownCarriesRaw` — `ErrorClass.unknown(raw: "boom")` is
  `Equatable` and keeps `"boom"`.
- `test_jobStartsQueued` (`@MainActor`) — `DownloadJob(request:)` has
  `state == .queued`, `attempt == 0`, `title == nil`, `progress == nil`,
  `outputFiles == []`.
- `test_progressClampsFraction` — `Progress(fraction: 1.5, …).fraction == 1.0`
  and `-0.2 → 0.0`.

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

```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' \
  -only-testing:GrabberKitTests/DownloadRequestTests \
  -only-testing:GrabberKitTests/PreferencesTests test
```
Expected: FAIL — types undefined.

- [x] **Step 3: Implement the types**

- Value types are plain structs; `DownloadKind` needs a hand-rolled `Codable`
  for its associated values. `JobState` / `ErrorClass` are `Equatable` /
  `Sendable` only (no persistence in Phase 1).
- `Progress.fraction` is clamped `0...1` in the init *and* the `didSet`.
- `Preferences` — computed properties over `defaults.object(forKey:)` /
  `set(_:forKey:)`, keys `"mg.<name>"`; `maxAutoAttempts` clamps on set;
  `defaultKind` reads the selector + the two format fields; URL props are
  absolute path strings.
- `DownloadJob` is `@MainActor @Observable` (see the interface note).

- [x] **Step 4: Run — verify pass**

Same command as Step 2. Expected: PASS.

DoD: the types compile, `DownloadRequest` round-trips through `Codable` for
every kind, `Progress.fraction` clamps, and `Preferences` defaults match the
spec and persist across instances.

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
      public static let progressTemplate: String     // the exact --progress-template value
      public static func build(for request: DownloadRequest) -> [String]
      public static func redacted(for request: DownloadRequest) -> [String]
  }
  ```
  `build` is the argv (no executable path). `redacted` masks secrets; Phase 1
  has none in the argv, so it returns `build` unchanged. `progressTemplate` is
  exposed so Task 6's parser and Task 5's tests reference one literal. Task 10
  calls `build`; Task 11's logging calls `redacted`.

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

```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' -only-testing:GrabberKitTests/YtDlpArgumentsTests test
```
Expected: FAIL — `YtDlpArguments` undefined.

- [x] **Step 3: Implement**

`build(for:)` appends tokens per the contract; the video format selector's
selector string is assembled from `+`-joined fragments for line width but the
result equals the contract literal exactly. `redacted(for:)` returns `build`.
Run the built argv against the real `yt-dlp` with `--simulate` during
implementation to confirm no flag is rejected (a `yt-dlp` extractor error is
fine — a *flag parse* error is not).

- [x] **Step 4: Run — verify pass**

Same command as Step 2. Expected: PASS.

DoD: snapshot tests pass for video (with/without container), audio m4a/mp3, a
custom template, URL-last ordering, and the exact progress-template string;
`redacted` equals `build`; real `yt-dlp` accepts the flags.

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
  — a real run captured once from `yt-dlp` (audio-extract of a Wikimedia CC
  file): `[download] Destination`, the `MG|…` lines, `[ExtractAudio]` and
  `Deleting original file` post-processing lines. (Wikimedia has no separate
  a/v streams, so there's no real `[Merger]` line — a synthetic test covers
  that string.)
- Create: `apps/media-grabber/Tests/GrabberKitTests/Fixtures/ytdlp-network-error.txt`
  — a real DNS-failure stderr (`Failed to resolve … nodename nor servname
  provided`).
- Create: `apps/media-grabber/Tests/GrabberKitTests/Fixtures/ytdlp-generic-error.txt`
  — a real 404 (`Unable to download webpage: HTTP Error 404`).

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
  - contains `Unable to download` + a network signature → `.networkDown`. The
    signature list covers both Linux and macOS resolver phrasing: `getaddrinfo`,
    `Network is unreachable`, `Temporary failure in name resolution`,
    `Connection reset`, `Failed to resolve`, `nodename nor servname provided`,
    `Could not connect to server`, `The Internet connection appears to be offline`.
    (macOS says "Failed to resolve … nodename nor servname provided", not
    "getaddrinfo" — omitting these misclassifies a real offline failure.)
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

Also test: `test_progressLine_hoursEta` (`01:53:10` → 6790), and fixture-driven
`test_fixtureNetworkError_classifiesNetworkDown` /
`test_fixtureGenericError_classifiesUnknown` (the 404 must *not* classify as
network).

- [x] **Step 2: Run — verify fail**

```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' -only-testing:GrabberKitTests/ProgressParserTests test
```
Expected: FAIL — `ProgressParser` undefined.

- [x] **Step 3: Implement**

Two static functions, small `private static` helpers for `mm:ss` / `hh:mm:ss`
and `1.23MiB/s` parsing. No state. Any split/parse miss on a `MG|` line →
`.ignored`, never a throw. Split the post-processing check into its own
predicate rather than an inline multi-line `||` — swiftformat and swiftlint
disagree on where the opening brace of a wrapped `if` condition goes.

- [x] **Step 4: Run — verify pass**

Same command as Step 2. Expected: PASS.

DoD: fixture-driven tests cover start / mid / 100% / post-processing / ignored
/ network-error / generic-error / non-error / hours-ETA lines; malformed lines
never crash; the 404 fixture classifies as `.unknown`, not `.networkDown`.

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
- Create: `apps/media-grabber/Tests/AppUnitTests/ThemeTests.swift`

The `AppUnitTests` target is already declared in `Project.swift` (Task 1) — this
is the task that first fills it. Its first test failing because the target has no
sources is expected. Adding the first source under `Tests/AppUnitTests/` and
re-running `tuist generate` also makes the `MediaGrabber` scheme appear
(`AppUnitTests` depends on it).

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
      var displayFont: (CGFloat, Font.Weight) -> Font   // Sora, system fallback
      var bodyFont:    (CGFloat, Font.Weight) -> Font   // Inter, system fallback
      var monoFont:    (CGFloat, Font.Weight) -> Font   // JetBrains Mono, .monospaced fallback
      var windowRadius: CGFloat        // Aurora 18
      var cardRadius: CGFloat          // 14
      var controlRadius: CGFloat       // 9
      var pillRadius: CGFloat          // 20
      var chipRadius: CGFloat          // 7
      var hairlineWidth: CGFloat       // 1
      var motif: MotifKind             // .orb for Aurora
  }

  enum MotifKind { case reel, orb }

  func palette(for kind: PaletteKind) -> PaletteTokens

  enum Spacing { static let s1: CGFloat = 4; static let s2: CGFloat = 8; /* … s7 = 44 */ }

  struct ResolvedTheme {
      let skin: Skin
      let palette: PaletteTokens
      init(skin: Skin, palette: PaletteTokens)
      init(skinKind: SkinKind, paletteKind: PaletteKind)   // used by Task 11
      static let auroraMintIris: ResolvedTheme
  }
  extension EnvironmentValues { @Entry var theme: ResolvedTheme = .auroraMintIris }
  extension View { func theme(_ t: ResolvedTheme) -> some View }

  struct MotifView: View {
      var isActive: Bool
      var size: CGFloat
      func isSpinning(reduceMotion: Bool) -> Bool   // isActive && !reduceMotion; tested
  }
  ```
  `palette(for:)` returns the Mint & Iris `PaletteTokens` for every case in
  Phase 1 — the other five carry a `// Phase 9` note and the same values, so a
  stale preference never crashes or blanks the UI. Never `fatalError`.

  `EnvironmentValues.theme` uses the `@Entry` macro; its default is
  `ResolvedTheme.auroraMintIris`.

  **Fonts are not bundled.** `Skin`'s font accessors call `NSFont(name:)` and
  fall back to `Font.system` (`.monospaced` design for the mono face) when the
  family is absent — the running app uses system faces. Bundling Sora / Inter /
  JetBrains Mono under `Sources/App/Resources/Fonts/**` with
  `ATSApplicationFontsPath` is a leaf-backlog item, not Phase 1.

  `MotifView` uses `TimelineView(.animation(paused:))` gated on
  `isSpinning(reduceMotion:)`, which reads `@Environment(\.accessibilityReduceMotion)`.

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

- [x] **Step 1: Write the failing tests**

`Tests/AppUnitTests/ThemeTests.swift` (`@testable import MediaGrabber`):
- `test_auroraSkin_radii` — `windowRadius == 18`, `cardRadius == 14`,
  `controlRadius == 9`, `pillRadius == 20`, `chipRadius == 7`.
- `test_auroraSkin_motifIsOrb`.
- `test_mintIrisPalette_keyTokens` — `palette(for: .auroraMintIris)` has
  `accent == Color(hex: "#5EF2C8")`, `danger == "#FF7A6B"`, `ground == "#0C1013"`,
  `orbStops.count == 4`.
- `test_defaultEnvironmentTheme_isAuroraMintIris` —
  `EnvironmentValues().theme.palette.accent` equals the Mint & Iris accent.
- `test_spacingScale` — `Spacing.s1 == 4 … Spacing.s7 == 44`.
- `test_motifView_staticUnderReduceMotion` (`@MainActor`) —
  `MotifView(isActive: true, size: 20).isSpinning(reduceMotion: true) == false`,
  `isSpinning(reduceMotion: false) == true`.

`Color(hex:)` lives in `Palette.swift` (`#RRGGBB` / `#RRGGBBAA`; `.clear` on a
malformed string) — tests and the palette definitions both use it.

- [x] **Step 2: Run — verify fail**

```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' -only-testing:AppUnitTests test
```
Expected: FAIL — theme types undefined.

- [x] **Step 3: Implement**

- `Skin` — fixed Aurora axes; `tapeDeck` carries placeholder geometry (never
  selected in Phase 1) so the shape is complete. Font accessors resolve the
  family or fall back to the system face.
- `palette(for:)` — Mint & Iris for every case (Phase 9 note on the rest).
- `SkinEnvironment` — `@Entry var theme: ResolvedTheme = .auroraMintIris`. Refer
  to `PaletteTokens.auroraMintIris` (a static) rather than calling `palette(for:)`
  inside the `ResolvedTheme` static — the free function name-collides with the
  stored `palette` property.
- `MotifView` — `TimelineView(.animation(paused:))` gated on
  `isSpinning(reduceMotion:)`.

- [x] **Step 4: Run — verify pass**

Same command as Step 2. Expected: PASS.

DoD: views can read colours and fonts from `@Environment(\.theme)`; every Aurora
token resolves to the design-system value; `MotifView` is static under
reduce-motion; the app builds and `swiftlint`/`swiftformat` are clean.

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
- Consumes: `ProcessRunning`, `ProcessLaunch` (Task 2); `EnvironmentProbing`,
  `EnvironmentReport` (Task 3); `@Environment(\.theme)` (Task 7).
- Produces:
  ```swift
  public enum OnboardingStepID: Sendable, CaseIterable {
      case homebrew
      case downloaderTools    // brew install yt-dlp ffmpeg — required
      case botCheckShield     // pipx install … — recommended, NOT blocking
      case testRun            // canary probe — Phase 1: auto-pass, see note
  }

  public enum OnboardingStepState: Sendable, Equatable {
      case pending
      case running(text: String)
      case done
      case failed(reason: String)
      case skipped
  }

  public enum HomebrewInstallInfo: Sendable {
      public static let command =
        "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  }

  @MainActor @Observable
  public final class OnboardingInstaller {
      public private(set) var steps: [OnboardingStepID: OnboardingStepState]
      public private(set) var canProceedToHome: Bool

      public init(probe: EnvironmentProbing = EnvironmentProbe(),
                  runner: ProcessRunning = ProcessRunner())

      public func start() async
      public func recheck() async         // re-probe, then resume the flow
      public func openTerminalForHomebrew()
  }
  ```
  `start` / `recheck` both run one shared flow: probe → if `brew` missing, leave
  `.homebrew` `.failed(reason: HomebrewInstallInfo.command)` and stop; else run
  each actionable step in order. A `.downloaderTools` failure blocks; a
  `.botCheckShield` failure does not.

  `HomebrewInstallInfo.command` is shown with a Copy button and an "Open in
  Terminal" button — the app never runs it.

  **Phase 1 `testRun`:** the real canary needs `MetadataProbe` (Task 9) and
  `DownloadEngine` (Task 10). Here it reports `.done` when `canProceedToHome`,
  with a `// TODO(Task 11): real canary` marker. Task 11 gives it a real body.

  Task 11's `AppModel` owns an `OnboardingInstaller` and shows `OnboardingView`
  whenever `!installer.canProceedToHome`.

- [x] **Step 1: Build `FakeEnvironmentProbe` and write the failing tests**

`Tests/GrabberKitTests/Support/FakeEnvironmentProbe.swift` conforms to
`EnvironmentProbing` and returns a *scripted sequence* of `EnvironmentReport`s,
one per `probe()` call (the last repeats), plus a `setReports(...)` to swap the
remaining sequence. This models "install, then re-probe finds the tools"
deterministically — no `Task.sleep`. An `EnvironmentReport.with(brew:ytDlp:ffmpeg:)`
helper builds a report from booleans.

`OnboardingInstallerTests.swift` (`@MainActor`), fake probe + `FakeProcessRunner`:
- `test_allPresent_skipsToProceed` — all present → `.homebrew == .skipped`,
  `.downloaderTools == .skipped` or `.done`, `canProceedToHome`.
- `test_toolsMissing_brewPresent_installsThenProceeds` — probe sequence
  `[brew only, all present]`; `brew install` exits 0 → `.downloaderTools == .done`,
  `canProceedToHome`.
- `test_brewMissing_blocksWithCommand` — brew absent → `.homebrew == .failed`
  with `HomebrewInstallInfo.command` in the reason, `canProceedToHome == false`,
  no `brew install` attempted.
- `test_recheck_afterBrewInstalled_resumes` — start blocked; `setReports([brew,
  all present])`; `recheck()` → `canProceedToHome`.
- `test_botCheckShieldFailure_doesNotBlock` — `pipx` fails → `.botCheckShield`
  not `.done` but `canProceedToHome` and `.downloaderTools == .done`.
- `test_downloaderInstallFailure_surfacesReasonAndBlocks` — `brew install` exits
  1 → `.downloaderTools == .failed(reason:)` with the stderr tail,
  `canProceedToHome == false`.

(`FakeProcessRunner` delivers all scripted lines in one burst, so there is no
deterministic test for observing a *specific* intermediate `.running(text:)`
line — the `.running` transition is exercised, just not snapshot mid-stream.)

- [x] **Step 2: Run — verify fail**

```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' -only-testing:GrabberKitTests/OnboardingInstallerTests test
```
Expected: FAIL — `OnboardingInstaller` undefined.

- [x] **Step 3: Implement the installer**

- One private `runFlow()` behind both `start()` and `recheck()`.
- Probe. `report.brew == nil` → `.homebrew = .failed(reason:
  HomebrewInstallInfo.command)`, return. Else `.homebrew = .skipped`.
- `report.isReadyForDownloads` → `.downloaderTools = .skipped`; else stream
  `brew install yt-dlp ffmpeg`, each line → `.running(text:)`; on exit 0
  re-probe and set `.done` (or `.failed` if the tools still aren't found); on
  non-zero `.failed` with the last ~5 stderr lines. A failure returns early.
- `botCheckShield`: `pipx install bgutil-ytdlp-pot-provider`, same streaming;
  its result is written straight to `steps[.botCheckShield]` and never touches
  `canProceedToHome`.
- `runStreaming` returns an `OnboardingStepState` directly (`.done` / `.failed`)
  — there is no separate outcome type.
- `testRun`: `canProceedToHome ? .done : .pending`, `// TODO(Task 11)`.
- `openTerminalForHomebrew()`: put the command on the pasteboard and
  `NSWorkspace.open` Terminal.app — never run the script. Guard `#if canImport(AppKit)`.

- [x] **Step 4: Build `OnboardingView` (App)**

Not unit-tested (SwiftUI layout).
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
- `@Bindable var installer` on the view. `@Bindable`, not `@ObservedObject` —
  `OnboardingInstaller` is `@Observable`.
- Nothing dismisses this view; Task 11's `AppModel` swaps in Home when
  `installer.canProceedToHome` flips true.
- Quality floor: every icon button has a VoiceOver label; buttons are
  keyboard-reachable; the spinner (`ProgressView`) respects reduce-motion.

- [x] **Step 5: Run the suite**

```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' test
```
Expected: full suite PASS; app builds; lint clean.

The live check — rename `yt-dlp` on `PATH`, launch, see onboarding take over,
restore, Re-check → Home — happens in **Task 11**, once `MediaGrabberApp` hosts
the real `AppModel` and the `-MGForceOnboarding` flag. Task 11's manual
walkthrough covers it. Nothing in this task launches the app.

DoD: with `yt-dlp` / `ffmpeg` absent, onboarding installs them via the fake
runner in tests; with them present, onboarding is skipped; a missing Homebrew
blocks with the command shown and never auto-runs it; a failing bot-check
shield does not block.

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
  — a real `yt-dlp -J` blob (archive.org CC video), trimmed to `id`, `title`,
  `duration`, `_type`, `webpage_url`.
- Create: `apps/media-grabber/Tests/GrabberKitTests/Fixtures/ytdlp-J-unavailable.txt`
  — real stderr from a probe against an unavailable video.

**Interfaces:**
- Consumes: `ProcessRunning`, `ProcessLaunch` (Task 2); a resolved `yt-dlp`
  `URL` (Task 3); `ProgressParser.classifyStderr` (Task 6).
- Produces:
  ```swift
  public struct MediaMetadata: Sendable, Equatable {
      public let title: String
      public let durationSeconds: Int?
      public let isPlaylist: Bool          // Phase 1: always false
      public let sourceURL: String
      public init(title: String, durationSeconds: Int?, isPlaylist: Bool, sourceURL: String)
  }

  public enum MetadataError: Error, Sendable, Equatable {
      case badURL, unsupported, unavailable, network, ytDlpMissing, malformedOutput
      case unknown(raw: String)
  }

  public protocol MetadataProbing: Sendable {
      func probe(_ url: String) async -> Result<MediaMetadata, MetadataError>
  }

  public actor MetadataProbe: MetadataProbing {
      public init(ytDlpURL: URL, runner: ProcessRunning = ProcessRunner())
      public func probe(_ url: String) async -> Result<MediaMetadata, MetadataError>
  }
  ```
  `MetadataProbing` is the seam Task 10's `DownloadEngine` and Task 11's
  `AppModel` test against. Task 10 calls `probe` to fill `job.title` before
  spawning the download; Task 11's `HomeView` calls it on paste.

**Serialization.** Swift actors are *reentrant* across `await`, and `probe`
suspends on its output stream — so actor isolation alone lets a second call
start mid-first-probe. Serialize explicitly: hold the previous probe's `Task` in
an actor-isolated `tail`; each new probe `await`s `tail` before doing its work
and installs itself as the new `tail`.

**Mapping (tests pin):**
- exit 0 + valid JSON with `title` → `.success`. `duration` → `Int(rounded)`,
  absent → `nil`. `_type == "playlist"` → `isPlaylist: true` (defensive; can't
  happen with `--no-playlist`).
- exit 0, no `title` or unparseable JSON → `.malformedOutput`.
- exit non-zero, empty stderr → `.ytDlpMissing`.
- exit non-zero, scan stderr:
  `is not a valid URL` → `.badURL`;
  `Unsupported URL` → `.unsupported`;
  `Video unavailable` | `This video is unavailable` | `This video is not
  available` | `Private video` | `blocked it in your country` | `The web client
  only works when logged-in` → `.unavailable`;
  `Unable to download` + `ProgressParser.classifyStderr(errorLine) == .networkDown`
  → `.network`;
  else, first `ERROR:` line → `.unknown(raw:)`.

- [x] **Step 1: Write the failing tests**

`FakeProcessRunner` scripts stdout (fixture JSON) + exit code per case:
- `test_validVideo_returnsTitleAndDuration` — fixture → `.success` with its
  `title`, `durationSeconds` (`596.46 → 596`), `isPlaylist == false`,
  `sourceURL == <input>`.
- `test_noDurationField_returnsNilDuration`.
- `test_badURL_mapsToBadURL` — `'x' is not a valid URL` → `.badURL`.
- `test_unsupported_mapsToUnsupported` — `Unsupported URL: …` → `.unsupported`.
- `test_unavailable_mapsToUnavailable` — the unavailable-stderr fixture.
- `test_networkFailure_mapsToNetwork` — `Unable to download webpage` + a macOS
  resolver phrase → `.network`.
- `test_exitZeroGarbageJSON_mapsToMalformed`, `test_exitZeroNoTitle_mapsToMalformed`.
- `test_ytDlpMissing_mapsToYtDlpMissing` — no script for `yt-dlp` → fake exits
  127, empty stderr → `.ytDlpMissing`.
- `test_serialization_secondCallWaits` — `runner.perRunDelay = .milliseconds(60)`;
  two overlapping `probe` calls → `runner.maxConcurrent == 1`.

- [x] **Step 2: Run — verify fail**

```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' -only-testing:GrabberKitTests/MetadataProbeTests test
```
Expected: FAIL — `MetadataProbe` undefined.

- [x] **Step 3: Implement**

- `probe`: chain on `tail` (see Serialization), then `runProbe`.
- `runProbe`: `ProcessLaunch(executableURL: ytDlpURL, arguments: ["-J",
  "--no-warnings", "--no-playlist", url])`; buffer `.stdout` / `.stderr`
  separately; `await result()`.
- exit 0 → `JSONDecoder` into a small `Decodable` (`title`, `duration`,
  `_type`); no `title` → `.malformedOutput`.
- non-zero → the stderr mapping above; the network check factored into a
  predicate so swiftformat/swiftlint don't fight over the wrapped `if`.

- [x] **Step 4: Run — verify pass**

Same command as Step 2. Expected: PASS.

DoD: a fixture `-J` blob parses to `MediaMetadata`; each stderr signature maps
to its `MetadataError`; concurrent probes serialize (`maxConcurrent == 1`).
Live check is optional (`MG_LIVE_TESTS=1`, off in CI).

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
- Consumes: `ProcessRunning`, `ProcessLine`, `ProcessResult` (Task 2); a
  resolved `yt-dlp` `URL` (Task 3); `DownloadRequest`, `@MainActor DownloadJob`,
  `JobState`, `Progress`, `ErrorClass` (Task 4); `YtDlpArguments.build` (Task 5);
  `ProgressParser` (Task 6); `MetadataProbing` / `MetadataProbe` (Task 9).
- Produces:
  ```swift
  public protocol DownloadEngineProtocol: Sendable {
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
      public private(set) var jobs: [DownloadJob]   // submit order; Phase 1: ≤1 non-terminal
  }
  ```
  `submit` enqueues and returns immediately with a `.queued` job — it never
  blocks and never reports failure; the job's `state` does. `DownloadJob` is
  `@MainActor`, so every mutation `drain()` makes to a job hops to the main
  actor (`await MainActor.run { … }`); the tests that read `job.state` /
  `job.progress` are `@MainActor` and poll until the job reaches a terminal
  state. Task 11's `AppModel` holds a `DownloadEngineProtocol`, keeps the
  returned job, and renders from it.

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

- [x] **Step 1: Write the failing tests**

`FakeProcessRunner` (from `Support/`) is scripted with `[ProcessLine]` + a
`ProcessResult`. Add a `FakeMetadataProbe` (`MetadataProbing`) in `Support/`.
Tests are `@MainActor` and `await` a helper that polls `job.state` until
terminal (or a timeout) — `submit` returns instantly at `.queued`.

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

- [x] **Step 2: Run — verify fail**

```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' -only-testing:GrabberKitTests/DownloadEngineTests test
```
Expected: FAIL — `DownloadEngine` undefined.

- [x] **Step 3: Implement**

- Actor state: `jobs: [DownloadJob]`, `drainTask: Task<Void, Never>?`,
  `runningLineTask: Task<Void, Never>?` (the current job's line-loop, for `cancel`).
- `submit`: append `DownloadJob(.queued)` (constructed on the main actor); start
  `drainTask` if not running; return the job.
- `drain()`: `while let job = nextQueued()` → probe → spawn → line-loop →
  `result()` → terminal state. When `nextQueued()` is nil, clear `drainTask` and
  return (next `submit` restarts it). Skip jobs already `.cancelled`.
- Every `job.*` mutation hops to the main actor (`DownloadJob` is `@MainActor`).
- Output-file globbing: `FileManager.contentsOfDirectory`, filter by the
  title stem (sanitised as yt-dlp sanitises `%(title)s` — strip `/` and control
  chars), newest first.
- **Phase 2 seam:** `nextQueued()` is where the rate-limit-aware scheduler
  grows; `submit` / `cancel` / the job model don't change.

- [x] **Step 4: Run — verify pass**

Same command as Step 2. Expected: PASS. Run the full suite too.

- [x] **Step 5: Live smoke (local only, not CI)**

With `MG_LIVE_TESTS=1`, a hand-run test: `submit` a short real Creative-Commons
URL (Wikimedia / archive.org — not YouTube) to a temp dir → the job reaches
`.completed` and the file exists.

DoD: `submit` returns a `.queued` job with zero work done; `drain()` carries it
probe → progress → exit 0 → `.completed` with resolved output files; non-zero
exit classifies; cancelling a running job kills the child and sets `.cancelled`;
cancelling a queued job means it never runs; two jobs run FIFO with no overlap;
the live smoke lands an actual file.

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
- Consumes: `EnvironmentProbe` / `EnvironmentProbing` (T3), `Preferences` (T4),
  `DownloadRequest` / `DownloadKind` / `@MainActor DownloadJob` / `JobState` (T4),
  `ResolvedTheme(skinKind:paletteKind:)` (T7), `OnboardingInstaller` (T8),
  `MetadataProbing` / `MediaMetadata` / `MetadataError` (T9),
  `DownloadEngineProtocol` (T10). The `-MGForceOnboarding` launch argument
  (noted in T8) is read here.
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

Test doubles for this task: `FakeEngine` (`DownloadEngineProtocol`) and
`FakeMetadataProbe` (`MetadataProbing`, reused from T10) in
`Tests/AppUnitTests/`, plus a reveal sink so `reveal()` is assertable without
touching Finder. All `AppModel` tests are `@MainActor`.

- [x] **Step 1: `LogWriter` — failing tests**

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

- [x] **Step 2: `AppModel` — failing tests**

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

- [x] **Step 3: `MainWindow` (App, not unit-tested)**

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

- [x] **Step 4: `HomeView` + `RunwayView` (App, not unit-tested)**

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

- [x] **Step 5: Wire `MediaGrabberApp` + compose the object graph**

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

- [x] **Step 6: Run the full suite + build**

```bash
cd apps/media-grabber
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' test
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber build
mise exec -- swiftformat --lint .
mise exec -- swiftlint lint --strict
```
Expected: all `GrabberKitTests` + `AppUnitTests` pass; app builds; lint clean.

- [ ] **Step 7: Manual Phase-1 DoD walkthrough**

On a real machine, launch via `mise exec -- tuist generate --no-open` then
`open` the built app:
1. (Deps present) launch → Home first-run state, `online` chip green.
2. Paste a normal video URL → `✓ <title>`, runway arms on defaults.
3. Press Grab → step cards vanish, the job row shows a live progress bar.
4. Bar reaches 100% → row says **Saved**, **Reveal** opens Finder on the file.
5. Rename `yt-dlp` on `PATH`, relaunch → onboarding takes over and blocks Home;
   restore `yt-dlp`, hit Re-check → Home returns. (This is the launch check
   Task 8 deferred to here.)
6. Relaunch with `-MGForceOnboarding` → onboarding shows even with deps present.

DoD: **the phase is done.** Launch → (onboarding if needed) → paste a real URL
→ Grab on defaults → watch the bar → file in `~/Downloads` → "Saved" → Reveal
opens Finder. Full suite green, lint clean. The Task 12 smoke checklist passes.

---

## Task 12: Leaf docs + Phase-1 smoke checklist

**Files:**
- Create: `apps/media-grabber/README.md`
- Create: `apps/media-grabber/PRIVACY.md`
- Create: `apps/media-grabber/ticket-backlog.md`

**Interfaces:** none (documentation).

- [x] **Step 1: `README.md`**

Sections: what it is (one paragraph); requirements (macOS 14+, Homebrew — the
app installs `yt-dlp` + `ffmpeg` for you on first run); build from source
(`brew install mise`, `mise install`, `mise exec -- tuist generate`, open the
workspace, run); the one-time Gatekeeper step for a downloaded build (System
Settings → Privacy & Security → **Open Anyway**, or `xattr -dr
com.apple.quarantine /Applications/MediaGrabber.app`); where files land
(`~/Downloads` by default); where logs live (`~/Library/Logs/MediaGrabber/`,
all local — see PRIVACY.md); Phase 1 scope + known gaps (no queue, no resume — a
quit mid-download loses it; the Aurora fonts aren't bundled yet so the UI uses
system faces). License MIT.

- [x] **Step 2: `PRIVACY.md`**

Per spec §8.5. What the logs contain in the clear (video URLs, titles, the
destination folder as `~/…`). What is always redacted (cookies, proxy
credentials, usernames/passwords, absolute `/Users/<name>/` paths). No
telemetry, no network egress from logging — ever. Logs never leave the machine
unless the user manually shares a bundle (not in Phase 1).

- [x] **Step 3: `ticket-backlog.md`**

Seed the leaf backlog: Phase 2 (queue + real table), Phase 3 (persistence),
Phases 4–11 as one-liners from spec §12.2, plus the Phase-1 follow-ups the
build surfaced:
- **Bundle the Aurora typefaces** (Sora / Inter / JetBrains Mono) under
  `Sources/App/Resources/Fonts/**` with `ATSApplicationFontsPath`; the app
  currently falls back to system faces.
- **Real onboarding canary** — `testRun` is auto-pass; give it a real
  `MetadataProbe` of a known-stable URL.
- Deferred product-name decision (spec §14).

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

Record pass/fail for each.

DoD: the smoke checklist passes on a real machine and the result is recorded.

**`BACKLOG.md` (repo root) is not touched in Phase 1** (spec §14: T-002 / T-006
rows unchanged, no new row until v1) — noted so the executor leaves it alone.

---

## Spec coverage

**§12.1 build order → tasks:** 1 skeleton → T1 · 2 ProcessRunner → T2 ·
3 EnvironmentProbe → T3 · 4 data types → T4 · 5 YtDlpArguments → T5 ·
6 ProgressParser → T6 · 7 skin/palette → T7 · 8 OnboardingInstaller+View → T8 ·
9 MetadataProbe → T9 · 10 DownloadEngine → T10 ·
11 HomeView+MainWindow+AppModel+LogWriter → T11 · 12 leaf docs + smoke → T12.

**§5.3 / §5.8 / §5.11 UI** → T7 (theme), T8 (onboarding UI), T11 (Home
first-run/runway/job-row, MainWindow chrome, window autosave, quality floor).
**§8.1 / §8.5 logging + redaction** → T11 (`LogWriter`). **§9 error classes** →
T4 (enum) + T6 (classification) + T11 (failure copy). **§10 signing** → T1
(ad-hoc, hardened-runtime-off, sandbox-off). **§11 testing** → every task is
TDD; live tests gated `MG_LIVE_TESTS=1` (T9, T10); manual smoke in T12.

## Where this plan differs from the spec (by design)

- `DownloadEngine.submit` enqueues and returns; a `drain()` task moves each job
  to a terminal state. This is the end-state shape once Phase 2 adds the
  scheduler — a queued job has no caller to return a result to. The spec's
  implied "submit waits FIFO in-actor" is not built.
- `DownloadJob` omits `playlistGroupID` / `playlistProgress` (no playlists in
  Phase 1; re-added in Phase 7).
- Onboarding's `testRun` is auto-pass in T8 and gets a real `MetadataProbe`
  body in T11.
- `SkinKind` / `PaletteKind` (string enums) live in `GrabberKit` for
  `Preferences`; the `Color`/`Font`-bearing `Skin` / `PaletteTokens` live in
  the `App` target, which `GrabberKit` cannot import.
- Aurora typefaces are resolved-or-system-fallback, not bundled (leaf-backlog
  item).

## Cross-task type contracts

`ProcessRunning` / `ProcessLaunch` / `ProcessLine` / `ProcessExecution` /
`ProcessResult` (T2) — used verbatim in T3, T8, T9, T10; `ProcessResult` has a
public memberwise init for the fakes. `EnvironmentProbing` (T3) — consumed by
T8, T11. `MetadataProbing` (T9) — consumed by T10, T11. `DownloadEngineProtocol`
(T10) — consumed by T11. `ResolvedTheme` / `@Environment(\.theme)` (T7) —
consumed by T8, T11. `ErrorClass` / `JobState` / `Progress` (T4) — flow through
T6, T10, T11. `@MainActor DownloadJob` (T4) — the engine (T10) hops to the main
actor for every mutation; UI tests that read it are `@MainActor`.

## Toolchain notes for the executor

- Build/test through `xcodebuild` on the generated `MediaGrabber-Workspace`
  scheme, not `tuist test` (its output filtering hides compiler errors).
- `.swiftformat` disables `docComments`; `.swiftlint.yml` disables `todo`. When
  the two disagree on a wrapped `if` condition's brace, extract the condition
  into a named predicate.
- Internal locking: `os_unfair_lock` (not `NSLock` in async contexts, not
  `Mutex` — macOS 15).
- Live fixtures come from `commons.wikimedia.org` / `archive.org`; YouTube needs
  a POT provider (out of Phase 1).
