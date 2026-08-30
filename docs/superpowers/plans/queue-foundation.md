# Queue Foundation and Window Chrome (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `DownloadEngine` own an ordered job list and a multi-slot scheduler, emit `Sendable` value events the UI binds to, and add the Downloads table, row-action bar, force-start, per-job raw logs, persistence across launches, graceful quit, a reusable confirmation dialog, and the `WarningBanner` / `HealthStrip` chrome shells.

**Architecture:** The engine is an actor that owns one ordered job list (active + terminal together). Nothing outside it reads engine state directly — a single `AsyncStream<QueueEvent>` is the only channel out; user intents are `async` calls in. State mutations happen only in synchronous non-`async` methods keyed by job id; async work (spawn, probe, deferral timers) re-enters through those methods and never holds mutable job state across an `await`. The App layer consumes the stream in one long-lived task, feeds `RowStore`, which turns events into identity-stable `@Observable` `RowModel`s the hand-rolled `DownloadsTable` binds to.

**Tech Stack:** Swift 6, macOS 14 deployment target, Tuist-generated project, SwiftUI (App target only), XCTest, `Foundation.Process` (via `ProcessRunner` only), yt-dlp / ffmpeg child processes.

**Spec:** `docs/superpowers/specs/queue-foundation.md` (source of truth — 16-step TDD build order in its "Build order" section). Parent design: `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12 / §12.2. Phase 1 (built): `docs/superpowers/specs/archived/core-download-pipeline.md`.

---

## Execution cadence (standing user requirement)

Tasks are gated. For **every** task in this plan the executing session MUST:

1. **Edit the checkbox** — change `- [ ]` to `- [x]` on the task line the moment that task's DoD passes.
2. **Wait for the user's explicit go-ahead** before starting the next task. Do not begin the next task in the same turn. Stop and report.

This is a two-part instruction (edit, then wait) and it is not optional. Clusters below group tasks that fit one working session, but the per-task gate still applies inside a cluster — the user may say "continue" once and mean the whole cluster, or may review each task. Ask if unsure.

## Global Constraints

Copied verbatim from the spec and `apps/media-grabber/CLAUDE.md`. Every task's requirements implicitly include this section.

- **No git.** This plan contains no `git init` / `git add` / `git commit` / `git tag` / any git subcommand. The user runs git manually. Do not add git steps.
- **Swift version:** `SWIFT_VERSION` 6.0. **Deployment target:** `MACOSX_DEPLOYMENT_TARGET` / `deploymentTargets` `macOS 14.0`. `Synchronization.Mutex` needs macOS 15 — banned. Use the `os_unfair_lock`-backed `LockedBox` for shared mutable state touched from `async` code. `NSLock.lock()` / `.unlock()` banned in async contexts.
- **Actors are reentrant across `await`.** An actor method that suspends does not hold the actor. To serialize, chain an internal `Task` (see `MetadataProbe.tail`). Actor isolation alone is not a queue.
- **Engine mutation invariant (Phase 2 onward):** `DownloadEngine` state changes happen only in synchronous, non-`async` methods. Async work (child spawn, metadata probe, deferral timers) runs outside actor isolation and re-enters through those sync methods, keyed by job id, never holding a reference to mutable job state across an `await`. Every sync mutation bumps `revision` and emits the appropriate `QueueEvent`.
- **`revision` is the authoritative ordering signal** — strictly increasing across both event kinds, session-scoped, starts at 0 each launch, never persisted or compared across sessions. `generatedAt` is display / diagnostics only, never used for ordering.
- **Progress is a delta; every other change is a full snapshot.** A progress line that also flips a job terminal emits `.snapshot`.
- **Code style:** single-line comments only, only to explain *why*, only when type/function names don't already carry it. No `///` doc comments. No stacked `//` blocks — if the "why" needs more than one line, restructure the code. `// MARK:` is fine.
- **Lint traps:** do not inline a multi-line `||` / `,` `if` condition — extract it into a named predicate function (`swiftformat` and `swiftlint` disagree on brace placement otherwise). `.swiftformat` has `--disable docComments` — keep it.
- **`ProcessRunner` is the ONLY place `Foundation.Process` is touched. `DownloadEngine` is the ONLY component that spawns download processes.**
- **No network in tests.** Real-network tests gated behind `MG_LIVE_TESTS=1`, off in CI. Network-failure stderr on macOS says "Failed to resolve … nodename nor servname provided" — keep macOS phrasing.
- **Shell fixture scripts that must die on SIGTERM use `exec`** so the signal reaches the real process.
- **`schemaVersion == 1`** for every Phase 2 persistence file.
- **`Preferences.maxConcurrentDownloads`** default **3**, clamped **1–6** on set. `DebugFlags.concurrencyCapOverride` wins over it.
- **In-memory terminal cap, `history.json` cap, and `JobLog` file cap are the same 200, all keyed on `finishedAt`** — one set, three stores in lockstep.
- **`JobSnapshot` is not `Codable`** (runtime only). `PersistedJob` is `Codable`.
- **After adding/removing files:** `mise exec -- tuist generate --no-open`.
- **Test command (debugging):** `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`. Single suite: append `-only-testing:GrabberKitTests/<SuiteName>` or `-only-testing:AppUnitTests/<SuiteName>`. Do **not** use `tuist test` when debugging (it hides compiler errors).
- **Lint:** `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict`.
- **Python (if needed for a bulk edit):** repo-root venv `/Users/shardul/Documents/Github/Tools/.venv/bin/python`. Never system `python3`.

---

## File Structure

All paths relative to `apps/media-grabber/`.

### GrabberKit (headless framework, no SwiftUI)

| Path | Responsibility |
|---|---|
| `Sources/GrabberKit/Download/JobSnapshot.swift` | The immutable per-job value + `JobState` (moved here from `DownloadJob.swift`), `RowAction`, `IntegrityVerdict`, `QueueHaltReason` |
| `Sources/GrabberKit/Download/QueueEvent.swift` | `QueueEvent`, `QueueSnapshot` |
| `Sources/GrabberKit/Download/SubmitResult.swift` | `SubmitResult`, `PersistedState`, `DeferReason` |
| `Sources/GrabberKit/Download/Scheduler.swift` | `SchedulerInput`, pure `nextDownloads(_:)` / `nextProbe(_:)` |
| `Sources/GrabberKit/Download/DownloadEngine.swift` | The actor: job list, sync mutations, `evaluateSchedule()`, detached launcher, intents, `DownloadEngineProtocol`, `EngineDependencies` |
| `Sources/GrabberKit/Download/DownloadJob.swift` | The demoted engine-internal reference model (actor-isolated, not `@MainActor`, not `@Observable`) |
| `Sources/GrabberKit/Download/MetadataProbe.swift` | Phase 1 probe; `MediaMetadata` gains `extractor: String?` |
| `Sources/GrabberKit/Logging/LogEvent.swift` | Phase 1 enum extended with the Phase 2 cases |
| `Sources/GrabberKit/Logging/JobLog.swift` | Per-job raw stdout/stderr log file, header block, §8.5 redaction, 200-file cap |
| `Sources/GrabberKit/Model/Persistence.swift` | `QueueFile` / `HistoryFile` / `ColumnsFile`, `PersistedJob`, debounced writers, `flushNow()`, load table, `QueuePersisting` protocol |
| `Sources/GrabberKit/Model/Preferences.swift` | Phase 1 model + `maxConcurrentDownloads` |
| `Sources/GrabberKit/App/QuitCoordinator.swift` | `QuitCoordinator(engine:persistence:confirmer:)` — first-class type; `Confirming` protocol + `ConfirmationRequest` live here so GrabberKit stays UI-free |

### App target (SwiftUI over GrabberKit)

| Path | Responsibility |
|---|---|
| `Sources/App/Rows/RowModel.swift` | `@Observable final class` per job id, cached display strings |
| `Sources/App/Rows/RowStore.swift` | Turns `QueueEvent` into `RowModel`s; owns `rows` / `visibleRows` / `groups` / `chipCounts`; `PlaylistGroup` type |
| `Sources/App/Rows/RequestBuilder.swift` | Pure `DownloadRequest` builder + `RunwayOverrides` |
| `Sources/App/Table/ColumnConfig.swift` | `Codable` column model + `ColumnID` enum + invariants |
| `Sources/App/Table/DownloadsTable.swift` | Hand-rolled table: synced 2-axis scroll, `LazyVStack` virtualised body, header drag-reorder, sort cycle |
| `Sources/App/Table/DownloadRow.swift` | One row: Status pill (+ queue badge), Progress bar, fixed-layout action bar |
| `Sources/App/Table/ColumnsMenu.swift` | The `⊞ Columns` dropdown (all 16) + filter chip row |
| `Sources/App/ConfirmationDialog.swift` | Skinned dialog host bound to `pendingConfirmation`; notice mode; suppression mechanism |
| `Sources/App/Chrome/WarningBanner.swift` | Docked bottom shell + `BannerContent` (nil this phase) |
| `Sources/App/Chrome/HealthStrip.swift` | Chip row + `HealthChip` / `ChipInteraction`; `HealthController` returning one static chip |
| `Sources/App/AppModel.swift` | Drops `job`, adds `rows` + consumer task + empty-table state + `pendingConfirmation` + `DebugFlags` |
| `Sources/App/AppDelegate.swift` | Thin `@NSApplicationDelegateAdaptor`; `applicationShouldTerminate` → `QuitCoordinator` |
| `Sources/App/DebugFlags.swift` | Parsed once in `MediaGrabberApp.init` from `CommandLine.arguments` |
| `Sources/App/Home/HomeView.swift` | Restructured: fixed header region + independently scrolling table body |
| `Sources/App/MainWindow.swift` | Hosts the dialog + banner + health strip; window minimums |
| `Sources/App/MediaGrabberApp.swift` | `DebugFlags` parse, launch resume (`restore`), window config |

### Tests

| Path | Responsibility |
|---|---|
| `Tests/TestSupport/**` | New framework target: `LockedBox`, `FakeClock`, `FakeProcessRunner`, `FakeMetadataProbe`, `FakeEnvironmentProbe`, `FakeEngine`, `EventCollector`, `FakeQueuePersisting`, `FakeConfirmer`, `Fixture` |
| `Tests/GrabberKitTests/**` | Rewritten `DownloadEngineTests`, new scheduler / intents / force-start / seam / actions / JobLog / persistence / wiring suites |
| `Tests/AppUnitTests/**` | `RowStore` / `RequestBuilder` / `ColumnConfig` / confirmation / table suites |

### Docs

| Path | Responsibility |
|---|---|
| `apps/media-grabber/docs/design-system.md` | New §4.8 (confirmation dialog) written in Task 13 |
| `apps/media-grabber/README.md`, `ticket-backlog.md`, `PRIVACY.md` | Updated in Task 16 for the Phase 2 surface |

---

## Clusters (one working session each)

| Cluster | Tasks | Theme |
|---|---|---|
| **A** | 1–3 | TestSupport target + value types + pure scheduler functions |
| **B** | 4 | Engine rebuild (alone — largest task; ported Phase 1 tests + new scheduler tests) |
| **C** | 5–7 | Intents / force-start / deferred-start seam + systemic halt + `revalidate` |
| **D** | 8–9 | `availableActions` + `JobLog` |
| **E** | 10–11 | `Persistence` + engine ⇄ persistence wiring + launch resume |
| **F** | 12 | `RowStore` + `RowModel` |
| **G** | 13–14 | Confirmation dialog + design-system §4.8 / `ColumnConfig` + `DownloadsTable` |
| **H** | 15–16 | `RequestBuilder` + Home restructure / `MainWindow` chrome + rewire + `QuitCoordinator` + smoke |

Cluster boundaries are the natural review checkpoints. The per-task checkbox gate (above) still applies within each cluster.

---

## Cluster A — TestSupport, value types, pure scheduler

### Task 1: `TestSupport` target

**Files:**
- Modify: `Project.swift` (add the `TestSupport` framework target; add it as a dependency of `GrabberKitTests` and `AppUnitTests`)
- Create: `Tests/TestSupport/LockedBox.swift` (the single canonical copy)
- Create: `Tests/TestSupport/FakeClock.swift`
- Create: `Tests/TestSupport/Fixture.swift`
- Move: `Tests/GrabberKitTests/Support/FakeProcessRunner.swift` → `Tests/TestSupport/FakeProcessRunner.swift` (strip its embedded `LockedBox` copy — it now imports the shared one)
- Move: `Tests/GrabberKitTests/Support/FakeMetadataProbe.swift` → `Tests/TestSupport/FakeMetadataProbe.swift`
- Move: `Tests/GrabberKitTests/Support/FakeEnvironmentProbe.swift` → `Tests/TestSupport/FakeEnvironmentProbe.swift`
- Delete: the `LockedBox` copy in `Tests/AppUnitTests/Support/AppFakes.swift` (import from `TestSupport` instead)

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - `TestSupport` is a `.framework` target with `@testable import GrabberKit`, depended on by `GrabberKitTests` and `AppUnitTests`.
  - `final class LockedBox<Value>: @unchecked Sendable` with `init(_:)`, `func read<T>(_ body: (Value) -> T) -> T`, `func mutate<T>(_ body: (inout Value) -> T) -> T` (exact signatures from the current `FakeProcessRunner.swift` copy).
  - `final class FakeClock: @unchecked Sendable` — `var now: Date` (get), `func advance(by: Duration)`, `func sleep(until: Date) async` (returns when `now >= until`, or when a later `advance` crosses it). Backed by `LockedBox`.
  - `enum Fixture { static func text(_ name: String) -> String; static func data(_ name: String) -> Data; static func url(_ name: String) -> URL }` — loads from `Tests/GrabberKitTests/Fixtures/` via `Bundle.module`.
  - `FakeProcessRunner`, `FakeMetadataProbe`, `FakeEnvironmentProbe` — same public API as today, now in `TestSupport`.

- [x] **Step 1: Write the failing test** — `Tests/TestSupport/FakeClockTests.swift` in `GrabberKitTests` (a `@testable import TestSupport` smoke suite):

```swift
@testable import TestSupport
import XCTest

final class FakeClockTests: XCTestCase {
    func test_advancePastDeadline_wakesSleeper() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let woke = LockedBox(false)
        let sleeper = Task {
            await clock.sleep(until: Date(timeIntervalSince1970: 10))
            woke.mutate { $0 = true }
        }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(woke.read { $0 })
        clock.advance(by: .seconds(10))
        await sleeper.value
        XCTAssertTrue(woke.read { $0 })
    }

    func test_fixtureLoadsCheckedInCorpus() {
        XCTAssertTrue(Fixture.text("ytdlp-J-video.json").contains("\"title\""))
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/FakeClockTests`
Expected: FAIL — `TestSupport` target does not exist / `FakeClock` not found.

- [x] **Step 3: Add the `TestSupport` target to `Project.swift`**

```swift
.target(
    name: "TestSupport",
    destinations: .macOS,
    product: .framework,
    bundleId: "app.mediagrabber.mac.testsupport",
    deploymentTargets: .macOS("14.0"),
    sources: ["Tests/TestSupport/**"],
    resources: ["Tests/GrabberKitTests/Fixtures/**"],
    dependencies: [.target(name: "GrabberKit")]
),
```

Add `.target(name: "TestSupport")` to the `dependencies` of both `GrabberKitTests` and `AppUnitTests`.

- [x] **Step 4: Move the three fakes and consolidate `LockedBox`**

Move `FakeProcessRunner.swift`, `FakeMetadataProbe.swift`, `FakeEnvironmentProbe.swift` into `Tests/TestSupport/`. Extract `LockedBox` into `Tests/TestSupport/LockedBox.swift` (copy the current implementation from `FakeProcessRunner.swift` verbatim — `os_unfair_lock`-backed, `read` / `mutate`). Delete the `LockedBox` definition from `FakeProcessRunner.swift` and from `AppFakes.swift`. Add `import TestSupport` where those files' consumers need it. Make every moved fake `public` (they cross a module boundary now) — `public` on the type, `public` on every member the tests call.

- [x] **Step 5: Write `FakeClock` and `Fixture`**

```swift
// Tests/TestSupport/FakeClock.swift
import Foundation

public final class FakeClock: @unchecked Sendable {
    private struct State { var now: Date; var waiters: [(deadline: Date, resume: () -> Void)] = [] }
    private let box: LockedBox<State>

    public init(now: Date = Date(timeIntervalSince1970: 0)) { box = LockedBox(State(now: now)) }

    public var now: Date { box.read { $0.now } }

    public func advance(by duration: Duration) {
        let fired: [() -> Void] = box.mutate { state in
            state.now += TimeInterval(duration.components.seconds)
            let due = state.waiters.filter { $0.deadline <= state.now }
            state.waiters.removeAll { $0.deadline <= state.now }
            return due.map(\.resume)
        }
        fired.forEach { $0() }
    }

    public func sleep(until deadline: Date) async {
        if box.read({ $0.now >= deadline }) { return }
        await withCheckedContinuation { cont in
            let alreadyDue = box.mutate { state -> Bool in
                if state.now >= deadline { return true }
                state.waiters.append((deadline, { cont.resume() }))
                return false
            }
            if alreadyDue { cont.resume() }
        }
    }
}
```

```swift
// Tests/TestSupport/Fixture.swift
import Foundation

public enum Fixture {
    public static func text(_ name: String) -> String {
        String(data: data(name), encoding: .utf8) ?? ""
    }
    public static func data(_ name: String) -> Data {
        (try? Data(contentsOf: url(name))) ?? Data()
    }
    public static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: (name as NSString).deletingPathExtension,
                                 withExtension: (name as NSString).pathExtension)!
    }
}
```

- [x] **Step 6: `tuist generate` and run the moved fakes' existing tests**

Run: `mise exec -- tuist generate --no-open`
Then: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/ProcessRunnerTests -only-testing:GrabberKitTests/MetadataProbeTests -only-testing:GrabberKitTests/EnvironmentProbeTests -only-testing:GrabberKitTests/FakeClockTests`
Expected: PASS — all four suites green.

- [x] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean.

**DoD:** `tuist generate` clean, both test targets build, the moved fakes' existing tests pass, `FakeClock` + `Fixture` work.

---

### Task 2: Value types

**Files:**
- Create: `Sources/GrabberKit/Download/JobSnapshot.swift`
- Create: `Sources/GrabberKit/Download/QueueEvent.swift`
- Create: `Sources/GrabberKit/Download/SubmitResult.swift`
- Modify: `Sources/GrabberKit/Download/MetadataProbe.swift` (add `extractor: String?` to `MediaMetadata`, decode `-J`'s `extractor` key)
- Modify: `Sources/GrabberKit/Download/DownloadJob.swift` (move `JobState` out into `JobSnapshot.swift`; leave `DownloadJob` itself for Task 4)
- Test: `Tests/GrabberKitTests/ValueTypesTests.swift`

**Interfaces:**
- Consumes: nothing new. `JobState` already exists (currently in `DownloadJob.swift`) — cases: `queued, probing, running, paused, waitingForNetwork, cooldown(until:), completed, cancelled, failed(ErrorClass)`. `Progress` (Phase 1). `ErrorClass` (Phase 1, full enum).
- Produces:

```swift
struct JobSnapshot: Sendable, Equatable, Identifiable {
  let id: UUID
  let url: String
  let title: String?
  let state: JobState
  let progress: Progress?
  let durationSeconds: Int?
  let extractor: String?
  let addedAt: Date
  let finishedAt: Date?
  let destFolder: URL
  let outputFiles: [URL]
  let sizeBytes: Int64?
  let actualQuality: String?          // nil until Phase 4
  let attempt: Int                    // 0 until Phase 4
  let cooldownUntil: Date?            // nil until Phase 6
  let playerClientUsed: String?       // nil until Phase 7
  let playlistGroupID: UUID?          // nil until Phase 8
  let integrityVerdict: IntegrityVerdict?  // nil until Phase 4
  let availableActions: Set<RowAction>
}

struct QueueSnapshot: Sendable, Equatable {
  let jobs: [JobSnapshot]
  let revision: UInt64
  let queueHalt: QueueHaltReason?
  let generatedAt: Date
}

enum QueueEvent: Sendable {
  case snapshot(QueueSnapshot)
  case progress([UUID: Progress], revision: UInt64)
}

enum IntegrityVerdict: Sendable, Equatable { case passed; case failed(reason: String); case skipped(reason: String) }
enum QueueHaltReason: Sendable, Equatable { case depMissing }   // Phase 6 adds .circuitOpen, .networkDown
enum RowAction: Sendable, Hashable {
  case pause, resume, cancel, remove, forceStart, reveal, openInBrowser
  case retry, retryWithCookies, showLog   // gated — never in the Phase 2 set
}
enum SubmitResult: Sendable, Equatable {
  case queued(UUID)
  case duplicateExists(existing: UUID, wasCompleted: Bool)
}
enum PersistedState: Sendable, Equatable {
  case queued, paused, completed, cancelled
  case failed(reason: String)
}
enum DeferReason: Sendable, Equatable {}   // no case a Phase 2 path can emit; Phase 4 adds .backoff(attempt:), Phase 6 .hostCooldown(host:)
```

`MediaMetadata` gains `let extractor: String?` (added to `init`, defaulted `nil` at call sites that don't have it).

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import TestSupport
import XCTest

final class ValueTypesTests: XCTestCase {
    private func snap(fraction: Double? = nil) -> JobSnapshot {
        JobSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            url: "https://archive.org/details/x", title: nil, state: .queued,
            progress: fraction.map { Progress(fraction: $0, downloadedBytes: 0) },
            durationSeconds: nil, extractor: nil, addedAt: Date(timeIntervalSince1970: 0),
            finishedAt: nil, destFolder: URL(fileURLWithPath: "/tmp"), outputFiles: [],
            sizeBytes: nil, actualQuality: nil, attempt: 0, cooldownUntil: nil,
            playerClientUsed: nil, playlistGroupID: nil, integrityVerdict: nil,
            availableActions: [.pause, .cancel, .forceStart, .remove, .openInBrowser]
        )
    }

    func test_progressChangeBreaksEquality() {
        XCTAssertNotEqual(snap(fraction: 0.25), snap(fraction: 0.60))
    }

    func test_allNilSnapshotIsValidAndEqual() {
        XCTAssertEqual(snap(), snap())
    }

    func test_queuedActionSet() {
        XCTAssertEqual(snap().availableActions,
                       [.pause, .cancel, .forceStart, .remove, .openInBrowser])
        XCTAssertFalse(snap().availableActions.contains(.retry))
    }

    func test_mediaMetadataDecodesExtractorFromJBlob() {
        // ytdlp-J-video.json is Big Buck Bunny / archive.org content and already
        // carries "extractor": "archive.org" — assert the fixture's real value,
        // don't rewrite honest fixture data.
        let meta = MetadataProbe.decodeForTest(Fixture.text("ytdlp-J-video.json"),
                                               sourceURL: "https://x")
        XCTAssertEqual(try meta.get().extractor, "archive.org")
    }
}
```

(`MetadataProbe.decode` is refactored from a private instance method to a `private static func` — it touches no actor state — and a `static func decodeForTest` internal wrapper is added in the same file so `@testable import` reaches it. `runProbe` calls `Self.decode`.)

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild … test -only-testing:GrabberKitTests/ValueTypesTests`
Expected: FAIL — types not defined.

- [x] **Step 3: Write the value types**

Create the three files with the exact declarations from the Interfaces block. Move `JobState` from `DownloadJob.swift` into `JobSnapshot.swift` (leave `DownloadJob` in place — Task 4 reworks it). Add `extractor` to `MediaMetadata` and its `init` (defaulted `nil`); in `MetadataProbe.decode`, add `let extractor: String?` to the `Payload` struct and pass `payload.extractor` through. The `ytdlp-J-video.json` fixture already carries `"extractor": "archive.org"` (its real value — the blob is archive.org content); leave it as-is and assert that value, rather than rewriting honest fixture data to `"youtube"`.

- [x] **Step 4: Run test to verify it passes**

Run: `xcodebuild … test -only-testing:GrabberKitTests/ValueTypesTests`
Expected: PASS.

- [x] **Step 5: Full GrabberKit build + existing suites**

Run: `xcodebuild … test -only-testing:GrabberKitTests`
Expected: PASS — existing suites unaffected (the `MediaMetadata` init change is source-compatible via the default).

- [x] **Step 6: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`

**DoD:** types compile; equality/identity asserted (progress change ≠ equal, all-nil snapshot valid); `RowAction` set membership asserted; `MediaMetadata` decodes `extractor` from the fixture.

---

### Task 3: `nextDownloads` + `nextProbe` + `SchedulerInput`

**Files:**
- Create: `Sources/GrabberKit/Download/Scheduler.swift`
- Test: `Tests/GrabberKitTests/SchedulerTests.swift`

**Interfaces:**
- Consumes: `JobSnapshot`, `JobState` (Task 2).
- Produces:

```swift
struct SchedulerInput: Sendable {
  var queued: [JobSnapshot]     // in queue order
  var running: [JobSnapshot]
  var cap: Int                  // maxConcurrentDownloads
  var deferredIDs: Set<UUID>
  var probeIdle: Bool
}

enum Scheduler {
  // probe-complete queued jobs, in order, minus deferredIDs, take max(0, cap - running.count)
  static func nextDownloads(_ input: SchedulerInput) -> [UUID]
  // head queued job that still needs metadata, iff probeIdle
  static func nextProbe(_ input: SchedulerInput) -> UUID?
}
```

"Probe-complete" = the job's `title` **and** `extractor` **and** `durationSeconds` are all non-nil (matches the restore rule). "Needs metadata" = any of those three is nil. `nextProbe` returns the **head** queued job needing metadata (queue order), regardless of `cap`.

- [x] **Step 1: Write the failing test**

Single-letter locals (`q`, `n`, `r`) are rejected by this repo's `swiftlint` `identifier_name` rule — the real suite uses `queue` / `index` / `running`.

```swift
@testable import GrabberKit
import XCTest

final class SchedulerTests: XCTestCase {
    private func job(_ index: Int, state: JobState = .queued, probed: Bool = true) -> JobSnapshot {
        JobSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
            url: "u\(index)", title: probed ? "t" : nil, state: state, progress: nil,
            durationSeconds: probed ? 10 : nil, extractor: probed ? "youtube" : nil,
            addedAt: Date(timeIntervalSince1970: TimeInterval(index)), finishedAt: nil,
            destFolder: URL(fileURLWithPath: "/tmp"), outputFiles: [], sizeBytes: nil,
            actualQuality: nil, attempt: 0, cooldownUntil: nil, playerClientUsed: nil,
            playlistGroupID: nil, integrityVerdict: nil, availableActions: []
        )
    }

    private func input(
        queued: [JobSnapshot] = [], running: [JobSnapshot] = [],
        cap: Int = 2, deferred: Set<UUID> = [], probeIdle: Bool = true
    ) -> SchedulerInput {
        SchedulerInput(
            queued: queued, running: running, cap: cap,
            deferredIDs: deferred, probeIdle: probeIdle
        )
    }

    func test_empty() {
        XCTAssertEqual(Scheduler.nextDownloads(input()), [])
        XCTAssertNil(Scheduler.nextProbe(input()))
    }

    func test_runningBelowCap_fillsInQueueOrder() {
        let queue = [job(1), job(2), job(3)]
        XCTAssertEqual(
            Scheduler.nextDownloads(input(queued: queue, cap: 2)),
            [queue[0].id, queue[1].id]
        )
    }

    func test_runningAtCap_downloadsEmpty_butProbeStillRuns() {
        let queue = [job(1, probed: false)]
        let running = [job(4, state: .running), job(5, state: .running)]
        XCTAssertEqual(
            Scheduler.nextDownloads(input(queued: queue, running: running, cap: 2)),
            []
        )
        XCTAssertEqual(
            Scheduler.nextProbe(input(queued: queue, running: running, cap: 2)),
            queue[0].id
        )
    }

    func test_deferredIdSkipped() {
        let queue = [job(1), job(2)]
        XCTAssertEqual(
            Scheduler.nextDownloads(input(queued: queue, cap: 2, deferred: [queue[0].id])),
            [queue[1].id]
        )
    }

    func test_unprobedJobNotInDownloads() {
        let queue = [job(1, probed: false), job(2)]
        XCTAssertEqual(Scheduler.nextDownloads(input(queued: queue, cap: 2)), [queue[1].id])
    }

    func test_probeNotIdle_noProbe() {
        let queue = [job(1, probed: false)]
        XCTAssertNil(Scheduler.nextProbe(input(queued: queue, probeIdle: false)))
    }

    func test_probeReturnsHeadNeedingMetadata() {
        let queue = [job(1), job(2, probed: false), job(3, probed: false)]
        XCTAssertEqual(Scheduler.nextProbe(input(queued: queue)), queue[1].id)
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild … test -only-testing:GrabberKitTests/SchedulerTests`
Expected: FAIL — `Scheduler` not defined.

- [x] **Step 3: Write the implementation**

```swift
enum Scheduler {
    static func nextDownloads(_ input: SchedulerInput) -> [UUID] {
        let slots = max(0, input.cap - input.running.count)
        guard slots > 0 else { return [] }
        return input.queued
            .filter { isDownloadReady($0, deferredIDs: input.deferredIDs) }
            .prefix(slots)
            .map(\.id)
    }

    static func nextProbe(_ input: SchedulerInput) -> UUID? {
        guard input.probeIdle else { return nil }
        return input.queued.first(where: needsMetadata)?.id
    }

    private static func isDownloadReady(_ job: JobSnapshot, deferredIDs: Set<UUID>) -> Bool {
        !needsMetadata(job) && !deferredIDs.contains(job.id)
    }

    private static func needsMetadata(_ job: JobSnapshot) -> Bool {
        job.title == nil || job.extractor == nil || job.durationSeconds == nil
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `xcodebuild … test -only-testing:GrabberKitTests/SchedulerTests`
Expected: PASS — every case.

- [x] **Step 5: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`

**DoD:** every case asserted (empty → `[]` / `nil`; `running < cap` fills in queue order; `running >= cap` → `[]` but `nextProbe` still returns an unprobed head; a deferred id skipped; an unprobed job not in `nextDownloads`; order preserved), no engine dependency.

---

## Cluster B — Engine rebuild

### Task 4: `DownloadEngine` rebuild — scheduler core + `EngineDependencies`

**Files:**
- Create: `Tests/TestSupport/EventCollector.swift`
- Rewrite: `Tests/GrabberKitTests/DownloadEngineTests.swift` + split the scheduler/cap scenarios into `DownloadEngineSchedulerTests.swift` and shared helpers into `DownloadEngineTestHelpers.swift` (this repo's `swiftlint --strict` enforces `type_body_length` 250 / `file_length` 400)
- Rewrite: `Sources/GrabberKit/Download/DownloadEngine.swift`; the protocol + `EngineDependencies` + `EngineDebugFlags` live in `DownloadEngineProtocol.swift`, the static helpers (`availableActions`, `errorClass`, `titleStem`, `resolveOutputFiles`) in `DownloadEngine+Helpers.swift`, and the scheduling section in a same-file `extension DownloadEngine` — again to stay under the length rules
- Rewrite: `Sources/GrabberKit/Download/DownloadJob.swift` (demoted model)
- Create: `Sources/GrabberKit/Model/PersistedJob.swift` — the protocol's `restore(active:history:)` references it, so its `Codable` shape (from § Persistence) is defined here; Task 10 builds the file wrappers + writers around it. `PersistedState` gains `Codable`.
- Modify: `Sources/GrabberKit/Model/Preferences.swift` (add `maxConcurrentDownloads`, default 3, clamp 1–6)
- Modify: `Sources/GrabberKit/Logging/LogEvent.swift` (add `jobStartedByScheduler`, `jobEnqueued`, `consumerStreamEnded` — the cases Task 4 emits; the rest arrive in later tasks)

**Interfaces:**
- Consumes: `Scheduler.nextDownloads` / `nextProbe` / `SchedulerInput` (Task 3); `JobSnapshot` / `QueueSnapshot` / `QueueEvent` / `SubmitResult` (Task 2); `MetadataProbing` / `MediaMetadata` (Phase 1); `ProcessRunning` / `ProcessLaunch` / `ProcessResult` (Phase 1); `YtDlpArguments.build` (Phase 1); `ProgressParser` (Phase 1).
- Produces:

```swift
protocol DownloadEngineProtocol: Sendable {
  var events: AsyncStream<QueueEvent> { get }
  func currentSnapshot() async -> QueueSnapshot
  func hasActiveJobs() async -> Bool

  func submit(_ request: DownloadRequest, force: Bool, prefetchedMetadata: MediaMetadata?) async -> SubmitResult
  func restore(active: [PersistedJob], history: [PersistedJob]) async     // Task 11 fills the body
  func revalidate() async                                                 // Task 7 fills the body

  func pause(_ id: UUID) async      // Task 5
  func resume(_ id: UUID) async     // Task 5
  func cancel(_ id: UUID) async     // Task 5
  func remove(_ id: UUID) async     // Task 5
  func forceStart(_ id: UUID) async // Task 6

  func shutdown() async
}

struct EngineDependencies: Sendable {
  var runner: ProcessRunning
  var probe: MetadataProbing
  var envProbe: EnvironmentProbing   // revalidate() (Task 7) re-runs it
  var ytDlpURL: URL
  var debugFlags: EngineDebugFlags   // { concurrencyCapOverride: Int? }
  var log: LogWriter?               // engine-authored queue-lifecycle events; nil = no logging
  static func live(ytDlpURL: URL, debugFlags: EngineDebugFlags = .init(), log: LogWriter? = nil) -> EngineDependencies
}
// No `clock` field here — GrabberKit cannot depend on TestSupport's FakeClock.
// Task 7 introduces a `Clock` protocol in GrabberKit and threads `any Clock` through.
// A private `setCap(_:)` test seam drives cap deterministically until then.

actor DownloadEngine: DownloadEngineProtocol {
  init(dependencies: EngineDependencies, preferences: Preferences)
}
```

Engine-internal `DownloadJob` (demoted): a plain actor-isolated `final class` (no `@MainActor`, no `@Observable`), mutable fields, `func snapshot() -> JobSnapshot`.

- Delete: `drain()`, `nextQueued()`, `ensureDraining()`, `drainTask`, `runningLineTask`, `queuedJobs`. Delete `submit`'s "second call waits FIFO in-actor" behaviour.
- Keep/adapt: `pump(_:)` → `launchDownload(id:)`'s line loop, `finish(_:)` → `recordExit`'s classification, `resolveOutputFiles`, `errorClass(for:)`, `titleStem`.
- `sizeBytes`: set from the current download process's first-reported `total_bytes`; re-set by a fresh process on resume/restart.
- The demoted `DownloadJob` is a plain `final class` (not `Sendable`), isolated to the actor; `snapshot(availableActions:)` maps every field.
- `availableActions` is computed to its final § JobSnapshot table now (Task 8 only adds tests).

- [x] **Step 1: Write `EventCollector`**

```swift
// Tests/TestSupport/EventCollector.swift
import Foundation
import GrabberKit

public final class EventCollector: @unchecked Sendable {
    private struct State { var events: [QueueEvent] = []; var lastSnapshot: QueueSnapshot? }
    private let box = LockedBox(State())
    private var task: Task<Void, Never>?

    public init(_ stream: AsyncStream<QueueEvent>) {
        task = Task { [box] in
            for await event in stream {
                box.mutate { state in
                    state.events.append(event)
                    if case let .snapshot(snap) = event { state.lastSnapshot = snap }
                }
            }
        }
    }

    public var all: [QueueEvent] { box.read { $0.events } }
    public var snapshots: [QueueSnapshot] { box.read { $0.events.compactMap { if case let .snapshot(s) = $0 { s } else { nil } } } }
    public func latestSnapshot() -> QueueSnapshot? { box.read { $0.lastSnapshot } }

    public func revisions() -> [UInt64] {
        box.read { $0.events.map { switch $0 { case let .snapshot(s): s.revision; case let .progress(_, r): r } } }
    }

    // Polls latestSnapshot until `predicate(job with id)` holds or timeout.
    public func waitForState(_ id: UUID, _ predicate: @escaping (JobState) -> Bool,
                             timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let job = latestSnapshot()?.jobs.first(where: { $0.id == id }), predicate(job.state) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    deinit { task?.cancel() }
}
```

- [x] **Step 2: Rewrite `DownloadEngineTests` — the failing scenarios**

Port every Phase 1 scenario to `QueueEvent` + `EventCollector`, and add the new scheduler scenarios. Full list (each a `func test_…`):

1. `test_submitReturnsQueuedImmediately` — `submit` → `.queued(id)`; no probe, no launch yet; first `.snapshot` has the job `.queued`.
2. `test_happyPath` — progress lines → `.progress` events with rising fractions; terminal → `.snapshot` with `.completed`, `title == "Clip"`, `finishedAt != nil`.
3. `test_stateSequence` — snapshots show `.queued → .probing → .running → .completed` for the job.
4. `test_nonZeroExit_networkStderr → .failed(.networkDown)`.
5. `test_nonZeroExit_noSignature → .failed(.unknown(raw:))` with raw containing the exit code.
6. `test_probeNetworkFailure_failsBeforeSpawn` — no launch; job `.failed(.networkDown)`.
7. `test_probeYtDlpMissing → .failed(.depMissing)`; no launch. (Halt behaviour is Task 7 — here the probe-missing path still just fails the job.)
8. `test_cancel_killsChild_setsCancelled` — `runner.cancelledCount == 1`, job `.cancelled`, `finishedAt != nil`.
9. `test_outputFilesResolvedOnCompletion` — `outputFiles` = `["Clip.mp4"]`.
10. `test_capOne_downloadsStrictlySequential` — `runner.maxConcurrent == 1` with `cap == 1`, both `.completed`.
11. `test_capTwo_twoConcurrent_thirdWaits` — with `cap == 2`, `runner.maxConcurrent == 2`; the third job stays `.queued` until a slot frees; **a probe may run alongside the two downloads**.
12. `test_burstOfThreeFreshURLs_pipelines` — 3 fresh URLs, `cap == 2`: assert the probe of B runs while A downloads (probe is not cap-gated), i.e. the pipeline is not stalled at 1. Assert via `probe.probedURLs` timing + `runner.launches` overlap.
13. `test_loweredCapKillsNothing` — start 2 at `cap == 2`, drop cap to 1 (test flag), both running jobs finish; no SIGTERM fired for a cap change.
14. `test_everyMutationRevisionStrictlyIncreases` — `collector.revisions()` is strictly increasing across the whole run.
15. `test_progressLinesAreProgressEvents_stateChangesAreSnapshots` — a `.progress` event carries only `[UUID: Progress]`; the terminal transition is a `.snapshot`.
16. `test_duplicateRequestInAnyState → .duplicateExists(existing:, wasCompleted:)` — submit twice (same `DownloadRequest`); second returns `.duplicateExists`, `wasCompleted` reflects whether the first is `.completed`; no second job created.
17. `test_forceTrue → .queued`, a distinct job (two rows, two ids).
18. `test_prefetchedMetadata_skipsProbing` — `submit(prefetchedMetadata: meta)` → job goes `.queued → .running`, no `.probing` snapshot, `probe.probedURLs` empty.
19. `test_sizeBytesFromFirstTotalBytes` — first progress line with a `total_bytes` sets `sizeBytes`; a later line with a different total does **not** change it within one process.

Use a `capOverride` on `EngineDebugFlags` (or a test-only `setCap(_:)` on the engine) to drive cap scenarios deterministically.

- [x] **Step 3: Run tests to verify they fail**

Run: `xcodebuild … test -only-testing:GrabberKitTests/DownloadEngineTests`
Expected: FAIL — new `DownloadEngine` API absent.

- [x] **Step 4: Rewrite `DownloadJob` (demoted model)**

```swift
// Sources/GrabberKit/Download/DownloadJob.swift
import Foundation

final class DownloadJob {          // actor-isolated to DownloadEngine; not Sendable, not @Observable
    let id: UUID
    var request: DownloadRequest
    var title: String?
    var extractor: String?
    var durationSeconds: Int?
    var state: JobState
    var progress: Progress?
    var sizeBytes: Int64?
    var attempt: Int
    var outputFiles: [URL]
    let addedAt: Date
    var finishedAt: Date?
    var startedAt: Date?           // for force-start victim selection (Task 6)

    init(request: DownloadRequest, id: UUID = UUID(), addedAt: Date = .now) { … }

    func snapshot(availableActions: Set<RowAction>) -> JobSnapshot { … }   // maps every field; defaulted ones as nil/0
}
```

- [x] **Step 5: Rewrite `DownloadEngine`**

Structure:
- `private var jobs: [DownloadJob]` — one ordered list (active + terminal).
- `private var revision: UInt64 = 0`.
- `private var queueHalt: QueueHaltReason?` (set in Task 7; declared now).
- `private var deferrals: [(id: UUID, notBefore: Date)] = []` (used in Task 7).
- `private let (eventStream, eventContinuation) = AsyncStream<QueueEvent>.makeStream()`; `nonisolated var events` returns the stored stream.
- `private var probeInFlight: Bool` + a serial `MetadataProbe` instance from deps (probing **not** cap-gated).
- **Sync mutation methods** (non-`async`, each ends with `bump()` + emit): `enqueue(_:)`, `markProbing(_:)`, `markRunning(_:)`, `recordProbeResult(_:_:)`, `recordProgress(_:_:)` (emits `.progress`), `recordExit(_:_:)`, `markCancelled(_:)`, `markPaused(_:)`, `markFailed(_:_:)`.
- `private func bump() { revision += 1 }`.
- `private func emitSnapshot()` / `private func emitProgress(_:)` — build from `jobs`, compute each job's `availableActions` (Task 8 refines; a first version inline here), send on the continuation.
- `func evaluateSchedule()` — build `SchedulerInput` from `jobs` + cap + `deferredIDs` + `probeInFlight`; for each id in `nextDownloads`, `markRunning` then hand the spawn to `launchDownload(id:)` (a detached `Task` outside isolation); if `nextProbe` returns an id and `!probeInFlight`, `markProbing` + `launchProbe(id:)`.
- `private nonisolated func launchDownload(id:)` — spawns via `runner`, streams lines, calls back into `self.recordProgress` / `self.recordExit` by id. Never captures a `DownloadJob`.
- `cap`: `dependencies.debugFlags.concurrencyCapOverride ?? preferences.maxConcurrentDownloads`.
- `submit`: duplicate check (skipped when `force`) — scan `jobs` for `$0.request == request`; if found → `.duplicateExists(existing: id, wasCompleted: state == .completed)`. Else create a `DownloadJob`, if `prefetchedMetadata` fill `title` / `extractor` / `durationSeconds` (so `Scheduler` sees it probe-complete and skips `.probing`), `enqueue`, log `jobEnqueued`, `evaluateSchedule()`, return `.queued(id)`.
- `currentSnapshot()` — build and return (does not emit).
- `hasActiveJobs()` — any job `.probing` or `.running`.
- `shutdown()` — SIGTERM every running child + cancel the in-flight probe `Task`, await reap, return. (Full body; Task 7 adds deferral-task cancellation, Task 11 adds a final flush hook.)
- Keep/adapt `pump` (now `launchDownload`'s line loop), `finish` (now `recordExit`'s classification), `resolveOutputFiles`, `errorClass(for:)`, `titleStem`.

- [x] **Step 6: Run tests to verify they pass**

Run: `xcodebuild … test -only-testing:GrabberKitTests/DownloadEngineTests`
Expected: PASS — all 19 scenarios.

- [x] **Step 7: Fix fallout in the App target and other suites**

`AppModel` calls `engine.submit(request)` → `DownloadJob`, reads `job.outputFiles` / `job.state`; `HomeView` / `MainWindow` bind a `DownloadJob` directly. Minimal bridging only (full rewire is Task 16):
- `AppModel`: drop `job: DownloadJob?`, add `lastSubmittedJobID: UUID?`; `grab()` calls `submit(_:force:prefetchedMetadata:)` and keeps the returned id; `reveal()` becomes a no-op call, `cancelJob()` cancels `lastSubmittedJobID`. No `#warning` needed — no stub return is unavoidable.
- `HomeView`: delete the Phase-1 `jobRow` / `rowAction` / `statusWord` / `statusColor` / `failureCopy` (they need `DownloadJob`); the layout gate reads `lastSubmittedJobID == nil`. `MainWindow.jobRunning` returns `false`. Task 15/16 rebuild this region as the Downloads table.
- `MediaGrabberApp` builds the engine with `.live(ytDlpURL:log:)`.
- `AppFakes.FakeEngine` conforms to the new protocol (records calls, canned `SubmitResult` via `stubNextResult`, an `AsyncStream` the tests can feed via `emit`). `AppModelTests` `test_reveal_callsWorkspaceWithOutputFiles` is `XCTSkip`ped — its premise depends on `RowStore`, not yet built.
- `DownloadEngineLiveTests` is rewritten to the new API + `EventCollector`.

Run: `xcodebuild … test -only-testing:GrabberKitTests -only-testing:AppUnitTests`
Expected: PASS — GrabberKit fully green; AppUnitTests green with the one tracked skip.

- [x] **Step 8: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`

**DoD:** the pipelined scheduler drives fake downloads to completion under a cap; Phase 1 behaviours hold, asserted via `QueueEvent`; `cap == 1` sequential, `cap == 2` two concurrent + a third waits while a probe runs alongside; a burst of 3 fresh URLs pipelines (not stall-at-1); a lowered cap kills nothing; every mutation's `revision` strictly increases; progress → `.progress`, state → `.snapshot`; duplicate → `.duplicateExists` with the right `wasCompleted`; `force: true` → `.queued` distinct job; prefetched metadata → no `.probing` hop, no probe spawned; `sizeBytes` re-set on a resume spawn.

---

## Cluster C — Intents, force-start, seam + halt

### Task 5: Intents — pause / resume / cancel / remove

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift`
- Modify: `Sources/GrabberKit/Logging/LogEvent.swift` (add `jobPaused(id:)`, `jobResumed(id:)`, `jobRemoved(id:, wasRunning:)`)
- Test: `Tests/GrabberKitTests/EngineIntentsTests.swift`

**Interfaces:**
- Consumes: the engine from Task 4; `JobLog` file effects are *specified* here but the `JobLog` type lands in Task 9 — `EngineDependencies.deleteJobLog: (@Sendable (UUID) -> Void)?` (nil default) is called by `remove(_:)` only, so Task 9 wires the real thing without touching intent code. (`cancel` keeps the log, so it never calls it.)
- Produces: `pause` / `resume` / `cancel` / `remove` bodies per spec § "Intent semantics":
  - `pause(id)` — running → SIGTERM child, `.part` kept, state `.paused`, job **leaves the pending queue** (scheduler ignores it, does not count against cap). Log `jobPaused`. Then `evaluateSchedule()` (a queued job takes the slot).
  - `resume(id)` — `.paused` → `.queued` **at the tail** (old position lost), no `.resuming` state. `.part` makes the eventual spawn resume. A fresh spawn re-sets `sizeBytes`. Log `jobResumed`. `evaluateSchedule()`.
  - `cancel(id)` — running → SIGTERM child, `.part` **kept**, state `.cancelled` (terminal), row stays visible, counts toward the 200 cap, `JobLog` file **kept**. `evaluateSchedule()`.
  - `remove(id)` — running → SIGTERM child, `.part` **deleted**, `JobLog` file **deleted**, job leaves the list entirely (purged from `history.json` on next write). Log `jobRemoved`. `evaluateSchedule()`.
  - `.part` path deletion: reuse `resolveOutputFiles`-style dir scan for `<stem>*.part` under `request.destFolder`.

- [x] **Step 1: Write the failing test** — `EngineIntentsTests` with (each `func test_…`):
  - `pauseRunningJob_freesSlotForQueued` — child SIGTERMed (`runner.cancelledCount == 1`), state `.paused`, a waiting queued job moves to `.running`.
  - `resumePausedJob_reEnqueuesAtTail` — job re-appended at the list tail (`[second, first]`), `sizeBytes` cleared on the resume snapshot.
  - `resumedJobResetsSizeBytesOnFreshSpawn` — a separate test: the re-run's completion snapshot carries the fresh process's `total_bytes`. (Split out because progress-only ticks emit `.progress`, not `.snapshot`, so mid-download `sizeBytes` is not observable through the snapshot stream.)
  - `cancelRunningJob_keepsPartAndLog` — `.cancelled`, `.part` file still on disk, `deleteJobLog` not called, child killed.
  - `removeRunningJob_deletesPartAndLog_leavesList` — child killed, `.part` file gone, `deleteJobLog` called with the id, absent from the next snapshot.
  - `removeTerminalJob_leavesList` — gone from the list and from `currentSnapshot()`.
  - Use real temp dirs + a fixture `.part` file written before the assertion.

- [x] **Step 2: Run to verify it fails**

Run: `xcodebuild … test -only-testing:GrabberKitTests/EngineIntentsTests`
Expected: FAIL.

- [x] **Step 3: Implement the four intents** in `DownloadEngine` (sync mutation methods + the detached SIGTERM handed off after the mutation returns; `.part` / log-file effects as file ops).

- [x] **Step 4: Run to verify it passes**

Run: `xcodebuild … test -only-testing:GrabberKitTests/EngineIntentsTests`
Expected: PASS.

- [x] **Step 5: Full GrabberKit suite + lint**

Run: `xcodebuild … test -only-testing:GrabberKitTests` then `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`

**DoD:** all four assert state, queue-membership, child-process, and file effects.

---

### Task 6: Force-start

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift`; the snapshot/emit + job-list helpers move to a new `DownloadEngine+State.swift` and the engine's stored properties become `internal` (so the split extensions reach them) — `swiftlint --strict` `file_length` 400 forces the split
- Modify: `Sources/GrabberKit/Logging/LogEvent.swift` (add `jobForceStarted(id:, evicted: UUID?)`)
- Test: `Tests/GrabberKitTests/EngineForceStartTests.swift`

**Interfaces:**
- Consumes: `DownloadJob.startedAt` (added in Task 4), the engine from Task 5.
- Produces: `forceStart(_ id: UUID) async` per spec § "Intent semantics" — **one atomic sync mutation**:
  1. within a single non-`await` method: move the forced job to the queue head; if `running == cap`, move the oldest-`startedAt` running job to `.queued` **at the tail** and mark the forced job `.running`; else just mark the forced job `.running`.
  2. bump `revision` **once**, emit **one** `.snapshot` (forced-running + victim-queued-at-tail simultaneously).
  3. `evaluateSchedule()` against that consistent state.
  4. *After* the sync method returns: hand the victim's child SIGTERM and the forced job's spawn to the detached launcher.
  - Not offered on a non-queued job (guard; `availableActions` in Task 8 also excludes it).

- [x] **Step 1: Write the failing test** — `EngineForceStartTests`:
  - `runningBelowCap → nothingEvicted` — forced job just marked + started, `evicted == nil` in the log event.
  - `runningAtCap → exactlyOneSnapshot` — capture `collector.snapshots`; find the single snapshot where the forced job flips to `.running`; assert in **that same snapshot** the victim is `.queued` and is last among non-terminal jobs; assert no snapshot shows `running == cap - 1` (no intermediate world); victim's `.part` file still present.
  - `twoRapidForceStarts_churnOnce_thenStabilise` — two `forceStart` calls back to back; the queue settles to exactly one `.running` + two `.queued` (no oscillation), asserted via `currentSnapshot()` + a short stabilization poll (the `EventCollector` async drain lags a direct read under full-suite load). `runner.maxConcurrent <= cap + 1` — a kill-and-replace handoff briefly overlaps the SIGTERM'd child with its replacement, on the fake and with real yt-dlp alike; the cap is a steady-state limit, not instantaneous.
  - `forceStartOnRunningJob_isNoOp` — `forceStart` on a `.running` job is a no-op, revision unchanged.
  - Wait for the forced/victim jobs to be **probe-complete** `.queued` (poll `probe.probedURLs.count`) before calling `forceStart` — a `waitForState(_, { $0 == .queued })` catches the pre-probe `.queued` too, and `forceStart` on a `.probing` job is (correctly) a no-op.

- [x] **Step 2: Run to verify it fails**

Run: `xcodebuild … test -only-testing:GrabberKitTests/EngineForceStartTests`
Expected: FAIL.

- [x] **Step 3: Implement `forceStart`** as the single sync mutation described.

- [x] **Step 4: Run to verify it passes**

Run: `xcodebuild … test -only-testing:GrabberKitTests/EngineForceStartTests`
Expected: PASS.

- [x] **Step 5: Full GrabberKit suite + lint**

**DoD:** exact, single-snapshot, thrash-free.

---

### Task 7: Deferred-start seam + systemic halt + `revalidate`

**Files:**
- Create: `Sources/GrabberKit/Download/Clock.swift` (`protocol Clock: Sendable { var now: Date { get }; func sleep(until: Date) async }`; a `SystemClock` struct for production; `FakeClock` in `TestSupport` gains `: Clock`)
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift`; the sync mutations move to `DownloadEngine+Mutations.swift` and the deferral seam to `DownloadEngine+Deferral.swift` (`swiftlint --strict` `type_body_length` 250); `cap` / `bump` become `internal`
- Modify: `DownloadEngineProtocol.swift` — `EngineDependencies.clock: any Clock` (default `SystemClock()`, so the Task 4–6 test helpers need no change)
- Modify: `Sources/GrabberKit/Download/MetadataProbe.swift` — add `MetadataError.launchFailed`; `classify` returns it on exit `127` + a `"launch failed:"` stderr line
- Modify: `Sources/GrabberKit/Logging/LogEvent.swift` (add `jobDeferred(id:, until: Date, reason: DeferReason)` — `DeferReason` has no emittable Phase 2 case; the `.fields` case is unreachable but keeps the switch exhaustive)
- Test: `Tests/GrabberKitTests/EngineDeferralTests.swift`, `Tests/GrabberKitTests/EngineHaltTests.swift`

**Interfaces:**
- Consumes: `FakeClock` (Task 1), `Scheduler.nextDownloads` (already skips `deferredIDs` — Task 3), `EnvironmentProbing` (Phase 1), `ProcessRunner`'s launch-failure signature (exit `127` + `"launch failed:"` stderr line, Phase 1).
- Produces:
  - `func deferStart(_ id: UUID, until: Date)` — inserts `(id, until)` into the sorted `deferrals` list; lazily creates a single sleep-`Task` that awaits `clock.sleep(until: earliestDeadline)`, then removes fired entries and calls `evaluateSchedule()`; re-arms for the next-earliest; suspends (nils the task) when the list empties. **No Phase 2 code calls `deferStart`** — it is the Phase 4/6 seam. Unit-tested via a `func deferStartForTest(_:until:)` passthrough.
  - `queueHalt` handling via `haltForDepMissing(offending:)`: a spawn (`recordExit` with a `"launch failed:"` stderr line **and** exit `127`) or probe (`recordProbeResult` with `.failure(.launchFailed)`) failure → set `queueHalt = .depMissing`, the offending job goes **back to `.queued`** (`progress`/`startedAt` cleared), the scheduler starts nothing while `queueHalt != nil` (`evaluateSchedule()` early-returns).
  - `revalidate() async` — re-runs `dependencies.envProbe.probe()`; if `report.isReadyForDownloads` → clear `queueHalt`, bump + emit, `evaluateSchedule()` (the requeued job re-probes then runs); else the halt stands.
  - `shutdown()` also cancels `deferralTask`.

- [x] **Step 1: Write the failing tests**
  - `EngineDeferralTests` — because a probe-complete `.queued` job auto-schedules, each test holds the single slot with a `heldRunner` "blocker" job (`cap: 1`), leaving the deferral target genuinely `.queued`; the multi-deferral test uses `setCap(0)` instead:
    - `deferredJobStartsOnlyAfterDeadline` — `deferStartForTest(target, until: now+10)`, cancel the blocker; the target stays `.queued`; `clock.advance(by: .seconds(10))`; it starts.
    - `earliestDeadlineWakesFirst` — two deferrals under `setCap(0)`; advancing to the nearer one starts only that one.
    - `nearerDeadlineReArms` — defer far, then defer near; the near one fires first.
    - `emptiedListSuspendsTask` — after the last deferral fires, a later `advance` bumps no revision.
    - `shutdownCancelsIt` — `shutdown()` with a pending far-future deferral returns well under a 3 s deadline.
  - `EngineHaltTests`:
    - `depMissingFailure_haltsQueue` — runner scripted to exit 127 + `"launch failed:"`; after the spawn attempt: `currentSnapshot().queueHalt == .depMissing`, the offending job `.queued`, no further launches.
    - `depMissingProbeFailure_classifiesSame`.
    - `revalidateWithDepsPresent_clearsHalt_resumesQueue` — inject an `EnvironmentProbing` returning ready; `await engine.revalidate()`; halt `nil`, the requeued job runs.
    - `revalidateWithDepsMissing_haltStands`.

- [x] **Step 2: Run to verify they fail**

Run: `xcodebuild … test -only-testing:GrabberKitTests/EngineDeferralTests -only-testing:GrabberKitTests/EngineHaltTests`
Expected: FAIL.

- [x] **Step 3: Implement** the `Clock` protocol, the sorted deferral list + lazy sleep-`Task`, `deferStart`, the `depMissing` classification + halt, and `revalidate`. Thread `any Clock` through `EngineDependencies` (`.live` uses `SystemClock`).

- [x] **Step 4: Run to verify they pass**

Run: `xcodebuild … test -only-testing:GrabberKitTests/EngineDeferralTests -only-testing:GrabberKitTests/EngineHaltTests`
Expected: PASS.

- [x] **Step 5: Full GrabberKit suite + lint** (the `EngineDependencies` clock change touches Task 4's tests — update their construction to pass a `FakeClock`).

**DoD:** the seam fires on a fake clock; the halt stops and `revalidate` resumes the scheduler.

---

## Cluster D — actions and per-job logs

### Task 8: `availableActions`

**Files:**
- Test: `Tests/GrabberKitTests/AvailableActionsTests.swift`

`DownloadEngine.availableActions(for:)` was already built to its final form in Task 4 (`DownloadEngine+Helpers.swift`) and is called from `buildSnapshot` for every job — this task is only the test.

**Interfaces:**
- Consumes: `JobState`, `RowAction` (Task 2).
- Produces: `availableActions(for:)` per the spec § "JobSnapshot" table:

| Job state | `availableActions` |
|---|---|
| `.queued` | pause, cancel, forceStart, remove, openInBrowser |
| `.probing` | cancel, remove, openInBrowser |
| `.running` | pause, cancel, remove, openInBrowser |
| `.paused` | resume, cancel, remove, openInBrowser |
| `.completed` | reveal, remove, openInBrowser |
| `.cancelled`, `.failed` | remove, openInBrowser |
| `.waitingForNetwork`, `.cooldown` | (Phase 6 — treat as `.running`-like: cancel, remove, openInBrowser for now) |

`retry` / `retryWithCookies` / `showLog` are **never** in the Phase 2 set.

- [x] **Step 1: Write the failing test** — `AvailableActionsTests`: one assertion per `JobState` → its exact `Set<RowAction>`; plus `transitionUpdatesTheSet` — drive a job `.queued → .running → .completed` through the engine and assert each snapshot's `availableActions` for that job matches the table.

- [x] **Step 2: Run to verify it fails**

Run: `xcodebuild … test -only-testing:GrabberKitTests/AvailableActionsTests`
Expected: FAIL (if Task 4 shipped an inline stub, the exact sets / `.probing`-has-no-`pause` case will differ).

- [x] **Step 3: Implement** `availableActions(for:)` and call it from the snapshot builder for every job.

- [x] **Step 4: Run to verify it passes** + full GrabberKit suite + lint.

**DoD:** every state asserted; a transition updates the set in the next snapshot.

---

### Task 9: `JobLog`

**Files:**
- Create: `Sources/GrabberKit/Logging/JobLog.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (write to `JobLog` from the line-pump; delete on `remove`; enforce the 200-file cap by `finishedAt` alongside the in-memory + `history` caps)
- Modify: `Sources/GrabberKit/Logging/LogEvent.swift` (no new case needed — `JobLog` is files, not `LogEvent`; but wire the Task 5 `jobLogSink` to `JobLog.delete(id:)`)
- Test: `Tests/GrabberKitTests/JobLogTests.swift`

**Interfaces:**
- Consumes: `LogRedaction.redact` (Phase 1, §8.5 — home paths → `~`, credentials stripped), `ProcessLine` (Phase 1).
- Produces:

```swift
final class JobLog: @unchecked Sendable {   // a single launcher task owns each instance, no lock needed
  init(id: UUID, request: DownloadRequest, ytDlpVersion: String, dir: URL = JobLog.defaultDir)
  func writeHeader() throws           // url, redacted request, start time, yt-dlp version
  func append(_ line: ProcessLine)    // raw stdout/stderr, redacted, one line
  func close()
  static func delete(id: UUID, dir: URL = defaultDir)
  static func evict(keepingNewestByFinishedAt jobs: [(id: UUID, finishedAt: Date?)], limit: Int = 200, dir: URL = defaultDir)
  static var defaultDir: URL          // ~/Library/Logs/MediaGrabber/jobs/
}
```

One file per job at `<dir>/<id>.log`. Eviction keyed on the **owning job's `finishedAt`** (not file mtime — a restored job's file has an old mtime but the job is fresh in memory), dropping the same 200 as the in-memory terminal cap and `history.json`.

`EngineDependencies` gains `ytDlpVersion: String` (`"unknown"` default) and `jobLogDir: URL` (`JobLog.defaultDir` default); `deleteJobLog` now defaults to `{ JobLog.delete(id: $0, dir: jobLogDir) }` instead of nil. The engine also enforces the **in-memory terminal cap** here — `enforceTerminalCap()` runs on every terminal transition, dropping oldest-`finishedAt` jobs from the list and deleting their log files in lockstep. Every engine test helper passes a scratch `jobLogDir` (temp) so the suite never writes to the real `~/Library/Logs`.

- [x] **Step 1: Write the failing test** — `JobLogTests` (unit) + `EngineJobLogTests` (integration):
  - `fakeRun_fileHasHeaderThenStreamedLines` — construct a `JobLog`, `writeHeader()`, `append` a few `.stdout` / `.stderr` lines; read the file: header block first, then the lines in order.
  - `redactionApplied` — append a line containing `/Users/alice/Movies/x` and `https://user:pass@host/`; file has `~/Movies/x` and `https://host/`.
  - `removeDeletesIt` — `JobLog.delete(id:)` removes the file.
  - `capEvictsOldestByFinishedAt` — 201 terminal job log files with ascending `finishedAt`; `JobLog.evict(...)` leaves 200; the dropped one is the oldest `finishedAt`.
  - `EngineJobLogTests`: a fake engine run writes header + streamed lines; `remove` deletes the file; 201 completed jobs → the oldest job **and its log** are gone (the in-memory `enforceTerminalCap`).

- [x] **Step 2: Run to verify it fails**

Run: `xcodebuild … test -only-testing:GrabberKitTests/JobLogTests`
Expected: FAIL.

- [x] **Step 3: Implement `JobLog`** and wire the engine: `launchDownload` opens a `JobLog` on spawn, `writeHeader()`, `append` every `ProcessLine`; on a terminal transition `enforceTerminalCap()` drops oldest-`finishedAt` jobs + their log files; `EngineDependencies.deleteJobLog` defaults to `JobLog.delete`.

- [x] **Step 4: Run to verify it passes** + full GrabberKit suite + lint.

**DoD:** per-job raw logs exist and the three caps evict the same set.

---

## Cluster E — persistence

### Task 10: `Persistence`

**Files:**
- Create: `Sources/GrabberKit/Model/Persistence.swift` — `final class Persistence` (protocol needs sync `saveX`) with a `Locked`-guarded synchronous pending stash + an inner `actor Writer` for file IO + the write-failure flag
- Create: `Sources/GrabberKit/Model/Locked.swift` — `os_unfair_lock` box, GrabberKit-internal (the `LockedBox` copy stays test-only in `TestSupport`)
- Create: `Sources/GrabberKit/Model/ColumnConfig.swift` — `ColumnID` (16 cases) + `ColumnConfig` **in GrabberKit, not App** (`Persistence` can't import App). Built to final form now: invariant enforcement (Actions pinned last + visible, Title visible, unknown dropped, missing appended), lenient `Codable`. Task 14's `DownloadsTable` consumes it.
- Modify: `Sources/GrabberKit/Model/PersistedJob.swift` — add `PersistedState.persisted(from: JobState)` (clamp), `PersistedState.restoredJobState`, `PersistedJob.isProbeComplete` (the engine uses these in Task 11)
- Modify: `Sources/GrabberKit/Logging/LogEvent.swift` (add the five `persistence*` cases, category `.persistence`)
- Create: `Tests/TestSupport/FakeQueuePersisting.swift`
- Test: `Tests/GrabberKitTests/PersistenceTests.swift`

**Interfaces:**
- Consumes: `DownloadRequest` (Phase 1, `Codable`), `PersistedState` (Task 2), `FakeClock` (Task 1). `ColumnConfig` is created here in full (it lives in GrabberKit, not App — see Files); Task 14 only adds the table UI on top.
- Produces:

```swift
struct QueueFile: Codable { var schemaVersion: Int; var jobs: [PersistedJob] }
struct HistoryFile: Codable { var schemaVersion: Int; var jobs: [PersistedJob] }
struct ColumnsFile: Codable { var schemaVersion: Int; var config: ColumnConfig }

struct PersistedJob: Codable {
  var id: UUID
  var request: DownloadRequest
  var title: String?
  var extractor: String?
  var durationSeconds: Int?
  var state: PersistedState
  var attempt: Int
  var playlistGroupID: UUID?
  var addedAt: Date
  var finishedAt: Date?
}

protocol QueuePersisting: Sendable {
  func saveQueue(_ jobs: [PersistedJob])       // debounced 500 ms
  func saveHistory(_ jobs: [PersistedJob])     // debounced 500 ms, ≤ 200 by finishedAt
  func saveColumns(_ config: ColumnConfig)     // debounced 500 ms
  func flushNow() async                        // cancel debounce, write all three synchronously
  func loadQueue() -> [PersistedJob]
  func loadHistory() -> [PersistedJob]
  func loadColumns() -> ColumnConfig?
}

final class Persistence: QueuePersisting {
  init(dir: URL = Persistence.defaultDir, clock: any Clock = SystemClock(), log: LogWriter, debug: PersistenceDebug = .init())
  // PersistenceDebug { resetState: Bool }
  // `saveX` stashes synchronously (Locked) then arms one debounce Task; the inner
  // `actor Writer` does the file IO, the unchanged-projection skip (by encoded bytes),
  // and holds `didFirstWriteFail`. `flushNow()` cancels the debounce and writes now.
}
```

Behaviour:
- `schemaVersion == 1`.
- On write: clamp `running` / `probing` → `queued`; `cooldown` / `waitingForNetwork` → `queued`.
- `failed` persists a **raw reason string** (`PersistedState.failed(reason:)`), not `ErrorClass`. On restore → `JobState.failed(.unknown(raw: reason))`.
- Debounced 500 ms via injected clock. `.progress` events never trigger a write. Before each write, compare the projected `[PersistedJob]` to the last written set; skip if unchanged.
- `history.json` capped at 200 by `finishedAt` (oldest evicted) — the same set as the in-memory + `JobLog` caps.
- Order preserved: `queue.json` stores non-terminal jobs **in engine list order**; `restore` rebuilds in exactly that order, **no `addedAt` re-sort**.
- Load table (spec § "Load behaviour"): `resetState` → skip all three; file absent → empty (no log); valid v1 → load + `persistenceLoaded`; `schemaVersion < 1` → migration chain (none exist); `schemaVersion > 1` → discard + `persistenceSchemaAhead`, do not parse; corrupt JSON → discard + `persistenceCorrupt`, never crash; unknown extra fields → ignored; missing new optional field → nil/default; `columns.json` unknown column → that entry dropped; `columns.json` omits a known column → appended at default visibility/position.
- Write failure → `persistenceWriteFailed(file:, error:)` every time; the **first** failure sets a flag (consumed by `AppModel` in Task 16 for the one-time notice); the flag clears on the next successful write → `persistenceRecovered` (no notice).

- [x] **Step 1: Write the failing test** — `PersistenceTests`, each `func test_…`:
  - `roundTripQueueFile` / `roundTripHistoryFile` / `roundTripColumnsFile`.
  - `downloadRequestFullRoundTripEquality` — video+height, audio+codec, container non-nil, deep folder path, custom template → `decoded == original` (asserts the § "Restore" round-trip fidelity claim).
  - `runningAndProbingClampToQueued` on write.
  - `queueOrderPreservedOnRestore` — jobs written out of `addedAt` order stay in that order after `loadQueue`.
  - `restoredFailedJob_becomesUnknownRaw` — `PersistedState.failed(reason: "boom")` → `JobState.failed(.unknown(raw: "boom"))` (via a `PersistedJob → DownloadJob` mapper the engine uses; test the mapper).
  - `corruptJSON_startsEmpty_logsCorrupt_noThrow`.
  - `schemaAhead_startsEmpty_logsSchemaAhead_doesNotParse`.
  - `progressOnlyChange_noWrite` — feed a projection identical except progress → `saveQueue` produces no file write (compare mtime / call count).
  - `historyCapAt200` — 201 terminal → oldest `finishedAt` dropped.
  - `columnsUnknownColumnDropped` / `columnsMissingColumnAppended`.
  - `changeWithinDebounceThenFlushNow_isWritten` — `saveQueue`, then `flushNow()` before 500 ms elapses (fake clock) → file on disk.
  - `writeThrow_logsWriteFailed_setsFlag_thenSuccess_logsRecovered` — inject a dir that rejects the first write.
  - `debugResetState_noLoads`.

- [x] **Step 2: Run to verify it fails**

Run: `xcodebuild … test -only-testing:GrabberKitTests/PersistenceTests`
Expected: FAIL.

- [x] **Step 3: Implement `Persistence`** + `FakeQueuePersisting` (records `saveQueue` / `saveHistory` / `saveColumns` call args, canned `load*` returns, a no-op `flushNow`).

- [x] **Step 4: Run to verify it passes** + full GrabberKit suite + lint.

**DoD:** every load-table row and the debounce / skip / cap / failure behaviours are fixture-covered.

---

### Task 11: Engine ⇄ Persistence wiring + launch resume

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (hold `any QueuePersisting` from deps; terminal transitions → history projection; other job-list changes → queue projection; both debounced. Implement `restore(active:history:)`.)
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` (add `persistence: any QueuePersisting` to `EngineDependencies`, default `NoopPersisting()`; `.live` takes `persistence:`; `MediaGrabberApp` builds a real `Persistence(log:)`)
- Test: `Tests/GrabberKitTests/EnginePersistenceWiringTests.swift`

The projection hook is a single `persistProjections()` call inside `emitSnapshot()` — every structural change reprojects (`saveQueue` active, `saveHistory` terminal); `emitProgress` never persists. `restore` exposes `producedJobsOnRestore` for the App's `hasGrabbedOnce` force.

**Interfaces:**
- Consumes: `Persistence` / `QueuePersisting` / `PersistedJob` (Task 10); the engine (Tasks 4–9).
- Produces:
  - After every sync mutation: if a job crossed to a terminal state, project the terminal jobs (≤ 200 by `finishedAt`) and call `persistence.saveHistory`; project the non-terminal jobs in list order and call `persistence.saveQueue`. (Both debounced inside `Persistence`; `.progress` events never call either.)
  - `restore(active: [PersistedJob], history: [PersistedJob]) async` — set `jobs` **from the on-disk order**: active jobs enter as `.queued`, terminal jobs inert (mapped `PersistedState → JobState`). A restored active job whose `PersistedJob` carries `title` **and** `extractor` **and** `durationSeconds` enters `.queued` **probe-complete** (the `Scheduler` takes it straight to download). Missing any of the three → re-probes when scheduled. `restore` returns a flag (or the engine exposes it) that any job was produced → the App forces `hasGrabbedOnce = true`. Then `evaluateSchedule()`.
  - `DownloadRequest` round-trips through `PersistedJob` with exact `Equatable` fidelity (asserted in Task 10; re-asserted end-to-end here) so a re-pasted restored link is still caught by the duplicate check.

- [x] **Step 1: Write the failing test** — `EnginePersistenceWiringTests`:
  - `terminalTransition_callsSaveHistoryAndSaveQueue` — a fake persisting layer records the calls; run a job to `.completed`; assert `saveHistory` got the terminal job and `saveQueue` got the remaining non-terminal set.
  - `restoreMixedSet_listAndFirstSnapshotMatch_orderPreserved` — `restore` with 2 active (out of `addedAt` order) + 1 terminal; `currentSnapshot().jobs` is in the supplied order, states correct.
  - `fullMetadataRestoredJob_noProbeSpawned_straightToDownload` — active `PersistedJob` with `title` + `extractor` + `durationSeconds`; after `restore` + `evaluateSchedule`, `probe.probedURLs` empty, a launch happens.
  - `partialMetadataRestoredJob_probeSpawned`.
  - `restoredActiveJobWithFakePart_resumesNotRestarts` — write a `<stem>.part` before `restore`; assert the spawn args target a resume (yt-dlp resumes automatically given the `.part`; assert the file is not deleted before the spawn).
  - `restoreProducedJobs_signalsHasGrabbedOnce`.

- [x] **Step 2: Run to verify it fails**

Run: `xcodebuild … test -only-testing:GrabberKitTests/EnginePersistenceWiringTests`
Expected: FAIL.

- [x] **Step 3: Implement** the wiring + `restore`.

- [x] **Step 4: Run to verify it passes** + full GrabberKit suite + lint.

**DoD:** a headless restore → resume → complete cycle passes, with and without re-probe.

---

## Cluster F — RowStore

### Task 12: `RowStore` + `RowModel`

**Files:**
- Create: `Sources/App/Rows/RowModel.swift`
- Create: `Sources/App/Rows/RowStore.swift`
- Create: `Tests/AppUnitTests/RowStoreTests.swift`

**Interfaces:**
- Consumes: `QueueEvent` / `QueueSnapshot` / `JobSnapshot` (GrabberKit); `DownloadKind` + `ColumnConfig` / `ColumnID` (all GrabberKit — created in Task 10). `JobSnapshot` gains `kind: DownloadKind` here (the type/quality derivation needs `request.kind` and `RowStore` only sees the snapshot). Also: the unused `enum GrabberKit` namespace in `Sources/GrabberKit/GrabberKit.swift` is deleted (it shadowed the module name, blocking `GrabberKit.Progress` disambiguation in App); a `public typealias DownloadProgress = Progress` replaces it for App call sites importing both `Foundation` and `GrabberKit`.
- Produces:

```swift
@Observable final class RowModel {
  // mirrors JobSnapshot + cached display strings:
  // statusText, speedText, etaText, formattedSize, formattedDuration,
  // siteLabel, typeLabel, qualityLabel, queueBadge
  // recomputed on patch only when the source field changed
}

struct PlaylistGroup {   // defined now, empty this phase
  let id: UUID; let title: String
  let totalCount, completedCount, failedCount: Int
  let rollupFraction: Double; var isCollapsed: Bool
}

@Observable final class RowStore {
  init(columnConfig: ColumnConfig)
  func apply(_ event: QueueEvent)
  func resync(_ snapshot: QueueSnapshot)
  private(set) var rows: [RowModel]            // all rows, stable identity, snapshot order
  private(set) var visibleRows: [RowModel]     // after chip + column filters + single active sort; computed over full rows
  private(set) var groups: [PlaylistGroup]     // empty this phase
  private(set) var chipCounts: ChipCounts      // All / Downloading / Done / Needs attention
  var activeChip: FilterChip                   // All default
}
```

- `type` / `quality` derived from `request.kind` (Audio/Video; the request selector `1080p` / `m4a` / …), cached on `RowModel`, never in a view body.
- `siteLabel` derived from `JobSnapshot.extractor` — **em-dash** before probed, the extractor label after. `youtube` / `youtu.be` / `m.youtube.com` collapse to one Site (`YouTube`) via an extractor→label map.
- Queue position (`#3`, 1-based) derived from snapshot order for `.queued` rows → `queueBadge`.
- `apply(.snapshot)` — keyed patch of `[UUID: RowModel]` (mutate only differing fields; create new, drop missing); rebuild `rows`; recompute `visibleRows` / `groups` / `chipCounts`. A `.snapshot` with no structural row change skips the filter/sort recompute **unless** the active sort column is `progress` / `speed` / `eta` / `size`.
- `apply(.progress)` — patch `progress` + `speedText` / `etaText` / `formattedSize` on the referenced `RowModel`s only; recompute `visibleRows` order only if the active sort column is `progress` / `speed` / `eta` / `size`.
- `resync(_:)` — treat the snapshot as ground truth: full rebuild, resume revision tracking from its `revision`.
- Sort rule: nil values sort **last** regardless of direction. Single active sort column.
- `chipCounts` "Needs attention" = `.failed` or `.cooldown`.

- [x] **Step 1: Write the failing test** — `RowStoreTests`:
  - `snapshotSequence_stableIdentities_onlyChangedFieldsMutate` — feed two snapshots differing in one job's `title`; the `RowModel` instance for each unchanged job is the same object; only the changed model's `statusText` etc. recompute (spy via a recompute counter).
  - `progressEvent_patchesProgress_keepsIdentityAndOrder` — with a non-progress sort active, a `.progress` event does not reorder `visibleRows`.
  - `chipFilter_plusColumnFilter_plusSort_composeInVisibleRows`.
  - `chipCounts_correct` incl. "Needs attention" = `.failed` + `.cooldown`.
  - `resync_rebuildsFromSnapshot`.
  - `siteLabel_emDashPreProbe_extractorLabelAfter` — `youtube` → `YouTube`.
  - `queueBadge_isOneBasedPositionForQueuedRows`.
  - `progressSortActive_progressEventReorders`.

- [x] **Step 2: Run to verify it fails**

Run: `xcodebuild … test -only-testing:AppUnitTests/RowStoreTests`
Expected: FAIL.

- [x] **Step 3: Implement** `RowModel` + `RowStore`.

- [x] **Step 4: Run to verify it passes** + `xcodebuild … test -only-testing:AppUnitTests` + lint.

**DoD:** fully driven and asserted headless, no SwiftUI.

---

## Cluster G — confirmation dialog and table

### Task 13: Confirmation dialog + design-system §4.8

**Files:**
- Modify: `apps/media-grabber/docs/design-system.md` (write §4.8; add it to the ToC after §4.7)
- Create: `Sources/GrabberKit/App/Confirming.swift` (`ConfirmationRequest`, `Confirming` — in GrabberKit so `QuitCoordinator` can use it UI-free; the *host view* is App-side)
- Create: `Sources/App/ConfirmationDialog.swift` (the skinned dialog host)
- Modify: `Sources/App/AppModel.swift` (add `pendingConfirmation: ConfirmationRequest?`, `func confirm(_:) async -> Bool`)
- Modify: `Sources/App/MainWindow.swift` (one dialog host bound to `pendingConfirmation`)
- Create: `Tests/TestSupport/FakeConfirmer.swift`
- Create: `Tests/AppUnitTests/ConfirmationTests.swift`

**Interfaces:**
- Consumes: `Skin` / `SkinEnvironment` / `Palette` (App theme, Phase 1); `AppStorage` for suppression.
- Produces:

```swift
struct ConfirmationRequest: Identifiable, Sendable {
  let id: UUID
  let title: String
  let message: String
  let confirmTitle: String
  let cancelTitle: String?        // nil → single-button notice
  let isDestructive: Bool
  let suppressionKey: String?     // non-nil → "Don't ask again" checkbox, persisted to AppStorage
}

protocol Confirming: Sendable { func confirm(_ request: ConfirmationRequest) async -> Bool }
```

- `AppModel.confirm(_:)` — sets `pendingConfirmation`, awaits the choice via a continuation, returns `Bool` (a notice returns `true` on dismiss; callers ignore it). If `suppressionKey` is set and previously suppressed → return `true` immediately without showing.
- One dialog host in `MainWindow` bound to `pendingConfirmation`.
- Visual per new §4.8: centered skinned sheet over a scrim (`--ground` ~60% alpha), max-width ~420px, skin card treatment (`--panel-solid`, skin border + radius + elevation). Layout: optional `warning` glyph (§3.4, destructive only) · title (`displayFont` 15 semibold) · message (`bodyFont` 13, `--dim`) · optional "Don't ask again" checkbox row · right-aligned buttons — Cancel (plain/`--panel`, omitted in notice mode) then Confirm (`--danger` fill when `isDestructive`, else `--accent` / skin `--go`). Motion `--dur`/`--ease`, disabled under reduce-motion. Return = confirm, Esc = cancel/dismiss; focus starts on Cancel for destructive, Confirm otherwise. VoiceOver: modal-alert semantics, focus trapped, message read.
- `FakeConfirmer` — returns canned answers (`func confirm(_:) async -> Bool` from a queue or a fixed value; records the requests it saw).

Suppression is an injected `SuppressionStore` protocol (App-side, `@MainActor`) with a `UserDefaults` impl — cleaner to fake than raw `@AppStorage`. `AppModel.confirm` awaits a `CheckedContinuation`; the host calls `AppModel.resolveConfirmation(_:suppressFutures:)`.

- [x] **Step 1: Write §4.8 in design-system.md** — a `### 4.8 Confirmation dialog` section covering the visual spec above, matching the doc's existing prose style; add `- [4.8 Confirmation dialog](#48-confirmation-dialog)` to the ToC after the 4.7 line.

- [x] **Step 2: Write the failing test** — `ConfirmationTests`:
  - `confirmResolvesToUserChoice` / `confirmResolvesFalse` — drive `resolveConfirmation` from a background task, assert the awaited return.
  - `suppressedKeyReturnsTrueWithoutShowing` — a suppressed key resolves `true`, `pendingConfirmation` never set.
  - `confirmWithSuppressCheckbox_persistsSuppression`.
  - `noticeMode_showsOneButton` / `hostReportsNoticeMode` — `cancelTitle == nil` → `showsCancel == false` on both the request and the host.
  - `dialogBuildsInBothSkins` — the host's `body` evaluates under `.tapeDeck` and `.aurora`.

- [x] **Step 3: Run to verify it fails**

Run: `xcodebuild … test -only-testing:AppUnitTests/ConfirmationTests`
Expected: FAIL.

- [x] **Step 4: Implement** `ConfirmationRequest` / `Confirming` / `AppModel.confirm` / the dialog host / `SuppressionStore` / `FakeConfirmer`.

- [x] **Step 5: Run to verify it passes** + `xcodebuild … test -only-testing:AppUnitTests` + lint.

**DoD:** the dialog works in both skins, both modes, and the suppression mechanism persists.

---

### Task 14: `ColumnConfig` + `DownloadsTable` + `DownloadRow` + `ColumnsMenu`

**Files:**
- Modify/replace: `Sources/App/Table/ColumnConfig.swift` (the full `Codable` model + `ColumnID` + invariants — replacing the minimal version from Task 10)
- Create: `Sources/App/Table/DownloadsTable.swift`
- Create: `Sources/App/Table/DownloadRow.swift`
- Create: `Sources/App/Table/ColumnsMenu.swift`
- Modify: `Sources/App/AppModel.swift` (hold `ColumnConfig` (`@Observable`); its `didSet` calls `Persistence.saveColumns(_:)`)
- Create: `Tests/AppUnitTests/ColumnConfigTests.swift`, `Tests/AppUnitTests/DownloadsTableTests.swift`

**Interfaces:**
- Consumes: `RowModel` / `RowStore` (Task 12); `RowAction` / `JobState` (GrabberKit); `Persistence.saveColumns` (Task 10); `Skin` tokens.
- Produces:

```swift
enum ColumnID: String, Codable, CaseIterable {
  case title, status, progress, speed, eta, type, quality, size, site,
       addedAt, finishedAt, duration, destination, attempt, clientUsed, actions
}

struct ColumnConfig: Codable, Equatable {
  var visibleColumns: Set<ColumnID>
  var columnOrder: [ColumnID]
  var sortColumn: ColumnID?
  var sortAscending: Bool
  var columnFilters: [ColumnID: Set<String>]   // checklist selections
  static var defaults: ColumnConfig            // visible: title,status,progress,speed,eta,type,quality,size ; actions pinned last
  // invariants enforced on load + mutate: actions pinned last + always visible + not movable; title always visible (movable)
}
```

- 16 columns, all in the `⊞ Columns` menu from Phase 2. Default-visible (8): `title, status, progress, speed, eta, type, quality, size`. Hidden by default (7): `site, addedAt, finishedAt, duration, destination, attempt, clientUsed`. Pinned: `actions`.
- `DownloadsTable` — hand-rolled (not SwiftUI `Table`): visible columns in order; **column headers draggable to reorder** (except Actions); **one active sort column** (`↕` cycles asc → desc → off; a new column's `↕` clears the previous); per-column filter (`▽` menu) per the §4.2.3 table; `progress` / `speed` / `eta` / `size` are sort-only. Synced **2-axis scroll** — vertical for rows, horizontal for columns, headers pinned vertically and moving horizontally with the body. `LazyVStack` virtualised body over `visibleRows`. ~80 px bottom inset reserved.
- `DownloadRow` — Status cell (plain-language state + leading dot per §4.2.3; a `.queued` row shows `queued · #3`; a failure shows its plain reason sentence); derived Progress bar (active rows only); Speed / ETA cells (blank on non-running); the **fixed-layout action bar** — every `RowAction` button in a fixed order; a button whose action is not in the job's `availableActions` renders **disabled** (`retry` / `retryWithCookies` / `showLog` therefore always disabled this phase).
- `ColumnsMenu` — the show/hide checklist (all 16); the filter chip row `All · Downloading · Done · Needs attention` ("Needs attention" count badge when > 0); a "Clear filters" text button appearing when the current chip + column filters hide every row (resets chip to `All`, clears column filters); the two empty-body lines — `No downloads — paste a link above.` (empty queue) vs `No downloads match this filter.` (filtered-empty).
- Persists via `ColumnConfig.didSet → Persistence.saveColumns`.

- [ ] **Step 1: Write the failing tests**
  - `ColumnConfigTests`: `actionsPinnedLastEnforcedOnLoad`; `actionsAlwaysVisible`; `titleAlwaysVisible`; `unknownColumnDroppedOnLoad`; `omittedKnownColumnAppendedAtDefault`; `sortColumnChangeClearsPrevious`; `roundTripCodable`.
  - `DownloadsTableTests` (headless — drive the view models, assert derived state, no on-screen rendering): `nilFieldRendersEmDash_columnStillSorts`; `actionBarEnabledDisabledPerState` (`.queued` → pause/cancel/forceStart/remove/openInBrowser enabled, rest disabled; `.completed` → reveal/remove/openInBrowser enabled); `filteredEmptyShowsCorrectLine`; `emptyQueueShowsCorrectLine`; `columnConfigChangeWithinDebounceThenFlushNow_isWritten` (fake clock + `FakeQueuePersisting`).

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild … test -only-testing:AppUnitTests/ColumnConfigTests -only-testing:AppUnitTests/DownloadsTableTests`
Expected: FAIL.

- [ ] **Step 3: Implement** `ColumnConfig` (full), `DownloadsTable`, `DownloadRow`, `ColumnsMenu`, and the `AppModel.columnConfig` `didSet` wiring.

- [ ] **Step 4: Run to verify it passes** + `xcodebuild … test -only-testing:AppUnitTests` + lint.

**DoD:** every column renders, all controls work, config survives a relaunch (headless round-trip; the on-screen UI check is Task 16's smoke).

---

## Cluster H — Home, chrome, wire, smoke

### Task 15: `RequestBuilder` + Home restructure

**Files:**
- Create: `Sources/App/Rows/RequestBuilder.swift`
- Modify: `Sources/App/Home/HomeView.swift` (restructure)
- Modify: `Sources/App/Home/RunwayView.swift` (surface Type / Format / Save-to as bindable `@State` the parent reads)
- Modify: `Sources/App/AppModel.swift` (`grab()` builds the request via `RequestBuilder`, passing runway state as `overrides` + `resolved` as `prefetchedMetadata`)
- Create: `Tests/AppUnitTests/RequestBuilderTests.swift`

**Interfaces:**
- Consumes: `MediaMetadata` (GrabberKit), `Preferences` (GrabberKit), `DownloadRequest` / `DownloadKind` (GrabberKit).
- Produces:

```swift
struct RunwayOverrides { var kind: DownloadKind?; var destFolder: URL? }   // nil = use the pref default

enum RequestBuilder {
  static func build(from resolved: MediaMetadata, prefs: Preferences, overrides: RunwayOverrides) -> DownloadRequest
  // a private per-item helper does the actual construction;
  // Phase 8's buildPlaylist(from:, selection:, prefs:, overrides:) -> [DownloadRequest] will reuse it
}
```

- Pure. `overrides.kind ?? prefs.defaultKind`; `overrides.destFolder ?? prefs.lastUsedDestFolder`; `container` from the kind (`mp4` for video, nil for audio — matches Phase 1 `containerForCurrentKind`); `outputTemplate` from `prefs.outputTemplate`.
- `HomeView` restructure: a **fixed header region** (paste field, runway when shown, filter chip row, `⊞ Columns` button, the column header row) + an **independently scrolling table body** filling the remaining height. First-run state (no table): the fixed region is just the paste field + hero + step cards, centered. Replaces Phase 1's single `ScrollView`.
- Wires the runway `@State` (Type / Format / Save-to) through `grab()` into `overrides` — closing the Phase 1 runway-not-applied gap.

- [ ] **Step 1: Write the failing test** — `RequestBuilderTests`:
  - `prefsOnly_noOverrides` — `RunwayOverrides()` → request matches `prefs.defaultKind` + `prefs.lastUsedDestFolder` + `prefs.outputTemplate`.
  - `fullOverride` — both `kind` and `destFolder` set → request uses them, not the prefs.
  - `partialOverride` — only `kind` set → request uses the override kind + the prefs folder.
  - Assert exact `DownloadRequest` equality in each.

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild … test -only-testing:AppUnitTests/RequestBuilderTests`
Expected: FAIL.

- [ ] **Step 3: Implement** `RequestBuilder` + the `HomeView` restructure + the runway wiring in `grab()`.

- [ ] **Step 4: Run to verify it passes** + `xcodebuild … test -only-testing:AppUnitTests` + lint.

**DoD:** the builder is pure and asserted; Home lays out with and without the table.

---

### Task 16: `MainWindow` chrome + shells + `AppModel` rewire + `QuitCoordinator` + `AppDelegate` + `DebugFlags` + leaf docs + smoke

**Files:**
- Create: `Sources/App/Chrome/WarningBanner.swift`
- Create: `Sources/App/Chrome/HealthStrip.swift`
- Create: `Sources/App/DebugFlags.swift`
- Create: `Sources/App/AppDelegate.swift`
- Create: `Sources/GrabberKit/App/QuitCoordinator.swift`
- Modify: `Sources/App/AppModel.swift` (drop `job`; add `rows` from `RowStore`; the guarded consumer task; the empty-table state; `pendingConfirmation`; `maxConcurrentDownloads` read; `DebugFlags`; `reveal()` filter-and-notice; the onboarding-completion → `engine.revalidate()` call)
- Modify: `Sources/App/MainWindow.swift` (host `WarningBanner` + `HealthStrip` + the dialog; reserved inset)
- Modify: `Sources/App/MediaGrabberApp.swift` (`DebugFlags` parse in `init`; `@NSApplicationDelegateAdaptor`; launch resume — load `queue.json` + `history.json` → `engine.restore`; load `columns.json`; window `minWidth: 820, minHeight: 560`, `.windowResizability(.contentMinSize)`, `.defaultSize` 980×720)
- Modify: `Sources/App/Home/HomeView.swift` (emptied-table state: table chrome stays, body shows `No downloads — paste a link above.`)
- Modify: `apps/media-grabber/README.md`, `apps/media-grabber/ticket-backlog.md`, `apps/media-grabber/PRIVACY.md`
- Modify: `Tests/AppUnitTests/AppModelTests.swift` (rewire to the new `AppModel`)
- Create: `Tests/AppUnitTests/QuitCoordinatorTests.swift`, `Tests/GrabberKitTests/QuitCoordinatorTests.swift` (whichever target `QuitCoordinator` lands testable in — it is GrabberKit)

**Interfaces:**
- Consumes: everything from Tasks 1–15.
- Produces:

```swift
struct BannerContent { var text: String; var buttonTitle: String; var action: @Sendable () async -> Void }   // nil this phase

struct HealthChip: Identifiable {
  let id: String; let label: String
  let dot: DotState                 // .ok (green) | .attention (amber)
  let interaction: ChipInteraction
}
enum ChipInteraction { case none; case refresh(@Sendable () async throws -> Void) }

struct DebugFlags {
  var forceOnboarding: Bool          // folds in Phase 1 -MGForceOnboarding
  var concurrencyCapOverride: Int?
  var resetState: Bool
  static func parse(_ argv: [String]) -> DebugFlags
}

final class QuitCoordinator: Sendable {
  init(engine: any DownloadEngineProtocol, persistence: any QueuePersisting, confirmer: any Confirming)
  func requestTerminate() async -> Bool   // true = proceed to quit
}
```

- `HealthController` (folded into `AppModel` or standalone) produces `[HealthChip]` — Phase 2 returns exactly one, the static "online" chip.
- `AppModel` consumer task (started in `onAppear`, never cancelled while the app lives):
  ```swift
  while !Task.isCancelled {
    for await event in engine.events { rowStore.apply(event) }
    log(.consumerStreamEnded)
    try? await Task.sleep(for: .seconds(1))          // spin guard
    await rowStore.resync(engine.currentSnapshot())
  }
  ```
- `grab()` — build the `DownloadRequest` via `RequestBuilder` (runway overrides + `resolved` as `prefetchedMetadata`), call `engine.submit(force: false, …)`. On `.duplicateExists(existing:, wasCompleted:)` → `await confirm(...)` with copy chosen by `wasCompleted` ("already in your queue" vs "you've already downloaded this"); if confirmed → `engine.submit(force: true, …)`; if cancelled and `wasCompleted` → scroll to the existing row. May keep the returned `UUID` transiently to scroll the new row into view.
- Row actions dispatch to `engine` by row id.
- `reveal()` — filter the row's `outputFiles` to paths that exist; reveal those via `RevealSink`; if none exist, present the "file no longer at that location" notice via `confirm` (notice mode) and log `.revealTargetMissing`.
- `QuitCoordinator.requestTerminate()`:
  1. if `await engine.hasActiveJobs()` **or** the latest snapshot's `queueHalt` is non-nil → `await confirm(.quitWithActiveJobs)` (copy notes the halt when present — "Downloads are paused — yt-dlp needs reinstalling. Quit anyway?"); on cancel → return `false`, stop. A non-empty but purely `.queued` queue with no halt does **not** prompt.
  2. `await persistence.flushNow()` — a failure here does **not** block quit; if the confirm dialog showed, its message notes the save failure.
  3. `await engine.shutdown()`.
  4. return `true`.
- `AppDelegate.applicationShouldTerminate` → `.terminateLater`, `Task { NSApp.reply(toApplicationShouldTerminate: await coordinator.requestTerminate()) }`.
- `MediaGrabberApp`: `DebugFlags.parse(CommandLine.arguments)` once in `init`; `resetState` → skip the persistence file loads; else load `queue.json` + `history.json` → `engine.restore(active:history:)`, load `columns.json` → `ColumnConfig` (or defaults). If `restore` produced any job → force `@AppStorage("mg.hasGrabbedOnce")` true.
- Leaf docs: `README.md` + `ticket-backlog.md` + `PRIVACY.md` (the per-job logs at `~/Library/Logs/MediaGrabber/jobs/`) updated for the Phase 2 surface; note the drag-reorder and multi-select deferrals in `ticket-backlog.md`.

- [ ] **Step 1: Write the failing tests**
  - `QuitCoordinatorTests` (fakes for engine, persistence, confirmer):
    - `activeJobs_promptsConfirm_cancelStopsQuit` — `hasActiveJobs → true`, confirmer → `false`; `requestTerminate()` returns `false`, `shutdown` not called.
    - `activeJobs_confirmProceeds_flushThenShutdownThenTrue` — order asserted (flush before shutdown).
    - `queueHaltNonNil_promptsEvenWithNoActiveJobs`.
    - `purelyQueuedNoHalt_noPrompt_flushShutdownTrue`.
    - `flushFailure_doesNotBlockQuit` — `flushNow` throws/records failure; `requestTerminate()` still returns `true`, `shutdown` still called.
  - `AppModelTests` (rewired):
    - `consumerTask_appliesEventsToRowStore`.
    - `grab_duplicateExists_promptsConfirm_confirmResubmitsForce` (with `FakeEngine` + `FakeConfirmer`).
    - `grab_duplicateCompleted_cancel_scrollsToExistingRow`.
    - `reveal_allFilesMissing_presentsNotice_logsRevealTargetMissing`.
    - `onboardingFinished_callsEngineRevalidate`.
    - `restoreProducedJobs_forcesHasGrabbedOnce`.
    - `debugResetState_skipsPersistenceLoads`.

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild … test -only-testing:AppUnitTests -only-testing:GrabberKitTests/QuitCoordinatorTests`
Expected: FAIL.

- [ ] **Step 3: Implement** the shells, `DebugFlags`, `AppDelegate`, `QuitCoordinator`, the `AppModel` rewire, the `MainWindow` hosting, the `MediaGrabberApp` launch resume + window config, the emptied-table state, and the leaf-doc updates.

- [ ] **Step 4: Run to verify it passes**

Run: `mise exec -- tuist generate --no-open` then the full suite: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`
Expected: PASS — every suite, both targets.

- [ ] **Step 5: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean.

- [ ] **Step 6: Manual smoke checklist (on a real machine)**

Work through the spec's Phase 2 smoke checklist in order:
  1. Queue three URLs → two download at `cap == 2` while a third probes, then downloads.
  2. Pause a running job → it stops, a queued one takes the slot.
  3. Resume it → runs at the tail.
  4. Force-start a queued job → a running one is evicted to the tail.
  5. Paste an already-queued URL + Grab → the duplicate dialog → "Download Again" → a second job + a `(1)` file.
  6. Cancel one → row stays, Done filter shows it.
  7. Remove one → row gone.
  8. Delete a completed job's file on disk, hit Reveal → the "file moved" notice.
  9. Quit with a job running → confirm sheet → children die → relaunch → the queue is back in order, the job resumes from its `.part`, restored jobs with full metadata do not re-probe.
  10. Rename `yt-dlp` away mid-session → the queue halts, Onboarding takes over → put it back, finish onboarding → the queue resumes.
  11. Hide / reorder / sort a column, relaunch → the column state persisted.
  12. Toggle a skin → the confirmation dialog restyles.

Record the result of each step. Any failure → fix before closing the phase.

**DoD:** *the phase is done* — the checklist passes on a real machine and every prior step's DoD still holds.

---

## Self-Review

*(Run against the spec after writing; issues fixed inline above.)*

**1. Spec coverage.** Every spec section maps to a task:
- Architecture / engine mutation invariant / scheduler → Tasks 3, 4, 7 + Global Constraints.
- Systemic halt / `revalidate` → Task 7. The two deliberate deletions → Task 4 (drain loop + `DownloadJob` demotion, stated as deliberate).
- `JobSnapshot` / enums / `DownloadEngineProtocol` / `EngineDependencies` → Tasks 2, 4.
- Intent semantics (submit/pause/resume/cancel/remove/forceStart) → Tasks 4, 5, 6. Restore → Task 11.
- App layer: `RowStore` → Task 12; `AppModel` changes → Tasks 13, 16; `RequestBuilder` → Task 15; Downloads table → Task 14; Window → Task 16; Confirmation dialog + §4.8 → Task 13; Graceful quit → Task 16.
- Persistence (files, `PersistedJob`, load table, launch resume, write failure) → Tasks 10, 11, 16.
- Logging (queue lifecycle, duplicate, persistence, misc) → spread across the tasks that emit each case (4, 5, 6, 7, 10); `JobLog` → Task 9.
- Chrome shells (`WarningBanner`, `HealthStrip`) → Task 16. `ErrorClass` (`diskFull` / `permissionDenied` / `incomplete` wiring) → **added to Task 4's `recordExit` classification** (see note below). Preferences (`maxConcurrentDownloads`) → Task 4 (model change) + Global Constraints.
- Test support target → Task 1.

**Gap found & fixed:** the spec's `ErrorClass` section (wire `diskFull` / `permissionDenied` / `incomplete` from the engine's terminal path) was not explicitly a numbered build step. It belongs in Task 4's `recordExit` / `finish` adaptation (the terminal classification path). **Task 4, Step 5** is hereby scoped to include: in the exit-classification path, map yt-dlp stderr / exit signalling a write failure to `.permissionDenied` (deleted/unwritable dest folder) or `.diskFull`, and a short-of-expected-size end to `.incomplete`; add a `test_diskFull_permissionDenied_incomplete_classification` case to `DownloadEngineTests` in Step 2.

**2. Placeholder scan.** No "TBD" / "add error handling" / "write tests for the above" / "similar to Task N" left. Every code step carries real code or an exact interface block. `FakeClock`, `EventCollector`, `Scheduler`, `JobLog`, `Persistence`, `QuitCoordinator` all have full signatures. The one soft spot — the confirmation-dialog host rendering assertions (Task 13, Step 2) — names concrete fallbacks (`showsCancel` computed property, `body` evaluation, `.accessibilityAddTraits(.isModal)`) rather than "test the UI".

**3. Type consistency.**
- `nextDownloads` / `nextProbe` / `SchedulerInput` named identically in Tasks 3, 4, 7.
- `EngineDependencies` gains fields across Tasks 4 (`runner`, `probe`, `clock`, `ytDlpURL`, `debugFlags`), 7 (`clock` → `any Clock`, `environmentProbe`), 11 (`persistence`) — additive, `.live` factory absorbs each, call sites using the factory unchanged (spec requirement).
- `QueuePersisting` method names (`saveQueue` / `saveHistory` / `saveColumns` / `flushNow` / `loadQueue` / `loadHistory` / `loadColumns`) identical in Tasks 10, 11, 16.
- `ColumnConfig` — minimal in Task 10, full (same field names: `visibleColumns`, `columnOrder`, `sortColumn`, `sortAscending`, `columnFilters`) in Task 14; `ColumnID` shared. **Note the ordering hazard:** Task 10 (spec step 10) needs `ColumnConfig` to be `Codable` for `ColumnsFile`, but Task 14 (spec step 14) owns it. Resolution (kept in spec order): Task 10 declares the full `ColumnConfig` struct + `ColumnID` enum (they are just data); Task 14 adds the invariant-enforcement logic and the views. This is called out in Task 10's Interfaces block and Task 14's file list ("replacing the minimal version").
- `Confirming` / `ConfirmationRequest` — defined in Task 13 (in GrabberKit so Task 16's `QuitCoordinator` consumes them); `FakeConfirmer` in Task 13.
- `DebugFlags` fields (`forceOnboarding`, `concurrencyCapOverride`, `resetState`) consistent between the spec's `AppModel changes` section and Task 16. `EngineDebugFlags { concurrencyCapOverride }` (Task 4) is the engine-side subset — named distinctly to avoid implying the App struct crosses into GrabberKit.
- `JobState` cases match Phase 1's existing enum (`queued, probing, running, paused, waitingForNetwork, cooldown(until:), completed, cancelled, failed(ErrorClass)`) — Task 2 moves it, does not redefine it.

**4. Task ordering.** Spec build order 1–16 preserved as Tasks 1–16. Cluster boundaries (A:1–3, B:4, C:5–7, D:8–9, E:10–11, F:12, G:13–14, H:15–16) match the spec's suggested session grouping. The one forward-reference (`ColumnConfig` needed in step 10, owned by step 14) is handled by splitting data (step 10) from behaviour+views (step 14), documented in both tasks.

**5. Non-executable DoDs.** Each task's final "Run: … Expected: PASS/FAIL" is a real command (`xcodebuild … -only-testing:<suite>`). Task 16's DoD ends in the manual smoke checklist with a per-step record requirement — executable by a human on a real machine, as the spec intends ("*the phase is done*").

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/queue-foundation.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — a fresh subagent per task, two-stage review between tasks, fast iteration.

**2. Inline Execution** — tasks executed in this session using executing-plans, batch execution with checkpoints.

Per the standing cadence at the top of this plan, whichever mode you pick: the previous task's checkbox is marked done, then the executor waits for your explicit go-ahead before the next task.

**Which approach?**
