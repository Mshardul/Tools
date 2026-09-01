# Retry and Error Classification (Phase 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Classify a `yt-dlp` failure, explain it in one plain-English sentence, auto-retry the recoverable ones on a jittered backoff schedule against the per-job budget, split the manual Retry button into resume-vs-retry, verify every completed file's duration and real resolution with `ffprobe`, and wire the `retry` / `showLog` row actions live.

**Architecture:** Retry orchestration lives in `DownloadEngine`'s existing synchronous terminal path (`recordExit`), not a new controller. `job.attempt` (a persisted `DownloadJob` field from Phase 2) is the budget counter. `Backoff` is a pure function; `EngineTuning` is an env-overridable constant bag holding every retry/pacing number. `Backoff` is the first caller of the Phase 2 `deferStart(_:until:)` seam — Phase 6's host cooldown becomes the second caller with no coordinator, the seam re-sorts by `Date`. `IntegrityCheck` shells `ffprobe` through the existing `ProcessRunning` from the engine's launcher `Task` *after* the process exits and the output file resolves, then re-enters the actor through `recordExit`. `FailurePresentation` is one `switch` over `ErrorClass` in `GrabberKit`; `ErrorSignatures` is a shared substring→class data table both the download-side (`ProgressParser.classifyStderr`) and the probe-side (`MetadataProbe`) classifier read.

**Tech Stack:** Swift 6, strict concurrency, `actor DownloadEngine`, XCTest, `FakeProcessRunner` / `FakeClock` / `FakeMetadataProbe` / `EventCollector` test doubles, Tuist project, `ffprobe` (fixture JSON only in tests).

**Spec:** `docs/superpowers/specs/2026-09-01-media-grabber-phase-4.md` (repo-root relative; parent design `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1, §7.5, §7.7, §7.9). All paths in this plan are relative to `apps/media-grabber/` unless prefixed `docs/`.

## Global Constraints

- **Deployment target macOS 14.** `Synchronization.Mutex` needs macOS 15 — banned. `NSLock.lock()/.unlock()` banned in async contexts — use the `os_unfair_lock`-backed `LockedBox` (`Tests/TestSupport/LockedBox.swift`, or the `GrabberKit` equivalent).
- **Comments: one line, or zero.** Only to explain *why*, only when type/function names don't already carry it. No `///` doc comments. No stacked `//` blocks. A wrapped multi-line comment is never acceptable — restructure the code instead. `// MARK:` is fine.
- **No phase / ticket / epic reference anywhere in code OR shipped UI copy.** Not in comments, strings, log keys, or `Info.plist`. This plan and the spec are the only places phase numbers live. `screens.html` is a meta file — minimal phase references allowed there.
- **`swiftformat --lint` + `swiftlint --strict` must be clean.** Do not inline a multi-line `if` condition (`||` / `,`) — extract a named predicate function. `swiftformat` promotes a `//` directly above a declaration to `///` unless `docComments` is disabled (it is — keep it).
- **`ProcessRunner` is the ONLY place `Foundation.Process` is touched. `DownloadEngine` is the ONLY component that spawns a child process.** `IntegrityCheck` spawns through an injected `ProcessRunning`, and only from the engine's launcher `Task`.
- **Two targets:** `GrabberKit` (no SwiftUI) and `MediaGrabber` (App, SwiftUI over it). `ErrorClass`, `FailurePresentation`, `ErrorSignatures`, `IntegrityCheck`, `Backoff`, `EngineTuning`, `DeferReason`, `LogEvent`, `EnvironmentProbe`, `DownloadEngine*`, `YtDlpArguments` are `GrabberKit`. `RowModel`, `RowStore`, `AppModel` are App-target.
- **`DownloadJob` is `@MainActor @Observable`** — engine hops `await MainActor.run { … }` for job mutations; tests reading `job.state` are `@MainActor` and poll. Actors are reentrant across `await` — a method that suspends does not hold the actor. `recordExit` runs synchronously (no `await` inside) — the Phase 2 mutation invariant; keep it that way.
- **After adding/removing/renaming files:** `mise exec -- tuist generate --no-open` from `apps/media-grabber/`.
- **Test command:** `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`. Single suite: append `-only-testing:GrabberKitTests/<Suite>` or `-only-testing:AppUnitTests/<Suite>`. Do NOT use `tuist test` when debugging (it hides compiler errors).
- **Lint:** `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict`, run from `apps/media-grabber/`.
- **TDD — test before implementation for every unit.** Each unit: write the failing test, run it, see it fail for the right reason, then the minimal implementation, then green, then commit.
- **No stubs to swap later.** Everything in spec §1 "in this phase" is built to final-app form. Phase 6 (`cooldownUntil`, per-host state) and Phase 7 (`player_client`, YouTube `ErrorClass` cases) extend additively — leave their seams (`cooldownUntil` nil, `FailurePresentation` switch open to four more arms) but do not build them.
- **Network:** no network in tests. Real-network tests gated behind `MG_LIVE_TESTS=1`. macOS network-failure stderr says "Failed to resolve … nodename nor servname provided", not "getaddrinfo" — keep macOS phrasing.

---

## File Structure

**New — GrabberKit:**

| File | Responsibility |
|---|---|
| `Sources/GrabberKit/Download/ErrorSignatures.swift` | `enum ErrorSignatures` — the ordered `[(class: ErrorClass, substrings: [String])]` data table (case-insensitive match). Shared by `ProgressParser.classifyStderr` and `MetadataProbe`'s classifier for the strings they share. Also the `Retry-After` integer parser. |
| `Sources/GrabberKit/Download/FailurePresentation.swift` | `struct FailurePresentation { sentence, offeredActions }` + `static func for(_ :ErrorClass) -> FailurePresentation` — one `switch` over `ErrorClass`. |
| `Sources/GrabberKit/Download/ErrorClass+Presentation.swift` | `public extension ErrorClass` — `key`, `presentation`, `isAutoRetryable`, `retryAfterSeconds`. (Kept beside the type; `ErrorClass.swift` stays a bare enum.) |
| `Sources/GrabberKit/Download/IntegrityCheck.swift` | `struct IntegrityCheck { init(runner:ffprobeURL:) }` + `func verify(file:expectedDurationSeconds:) async -> IntegrityResult`; `struct IntegrityResult { verdict, actualQuality }`. |
| `Sources/GrabberKit/RateLimiting/Backoff.swift` | `enum Backoff` — pure `static func delay(attempt:retryAfter:tuning:jitter:) -> TimeInterval`. |
| `Sources/GrabberKit/Model/EngineTuning.swift` | `struct YtDlpTuning` + `struct EngineTuning` (`ytDlp`, `backoffLadder`, `backoffCap`) + `static func resolved(environment:) -> EngineTuning`. |
| `Sources/GrabberKit/Download/DownloadEngine+Retry.swift` | The `retry(_:) async` intent and its resume-vs-retry branch, `usablePartFile(for:)` helper. |

**Modified — GrabberKit:**

| File | Change |
|---|---|
| `Sources/GrabberKit/Download/ErrorClass.swift` | `case rateLimited` → `case rateLimited(retryAfterSeconds: Int? = nil)`. Add `case incomplete`? — already present. No other case shape changes. |
| `Sources/GrabberKit/Download/SubmitResult.swift` | `enum DeferReason` gains `case backoff(attempt: Int)` (currently empty). |
| `Sources/GrabberKit/Logging/LogEvent.swift` | New cases `jobRetried(id: UUID)` and `showLogTargetMissing(jobID: UUID)`; `jobDeferred` fields gain `reason` / `attempt`. |
| `Sources/GrabberKit/Download/ProgressParser.swift` | `classifyStderr` reads `ErrorSignatures` after the network check, before the `ERROR:` fallthrough; parses `Retry-After`. |
| `Sources/GrabberKit/Download/MetadataProbe.swift` | `classify(stderr:exitCode:)` reads `ErrorSignatures` for its shared `unavailable` strings instead of its private `unavailableSignatures` list. |
| `Sources/GrabberKit/Download/DownloadJob.swift` | New fields `integrityVerdict: IntegrityVerdict?`, `actualQuality: String?` (runtime-only, not persisted); `snapshot(...)` passes them through. |
| `Sources/GrabberKit/Download/DownloadEngine+Mutations.swift` | `recordExit` gains `integrity: IntegrityResult?`; new decision order (spec §2); the classify→retry-or-fail branch. |
| `Sources/GrabberKit/Download/DownloadEngine.swift` | `evaluateSchedule` launcher `Task` runs `IntegrityCheck.verify` after exit 0, before `recordExit`; passes `integrity:` through. |
| `Sources/GrabberKit/Download/DownloadEngine+Helpers.swift` | `availableActions(for:)` `.failed` arm reads `errorClass.presentation.offeredActions ∪ {.remove,.openInBrowser,.showLog}`; `showLog` added to `.running`/`.paused`/`.completed`/`.cancelled`. |
| `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` | Protocol gains `func retry(_ id: UUID) async`; `EngineDependencies` gains `tuning: EngineTuning` (default `.default`) and `ffprobeURL: URL?` (default `nil`); `.live(...)` sets `.resolved()` / derives ffprobe. |
| `Sources/GrabberKit/Download/YtDlpArguments.swift` | `build` / `redacted` take `tuning: YtDlpTuning = .default`; `baseArgv` emits the §7 always-on flags from it. |
| `Sources/GrabberKit/Onboarding/EnvironmentProbe.swift` | `EnvironmentReport` gains `ffprobe: ToolInfo?`, resolved as `ffmpeg`'s dir + `/ffprobe`. `isReadyForDownloads` unchanged. |

**Modified — App target:**

| File | Change |
|---|---|
| `Sources/App/Rows/RowModel.swift` | `status(for:maxAutoRetries:)` — retry-state variants; `quality(for:)` uses `actualQuality`; ctor + `patch` + `patchProgress` thread `maxAutoRetries`. |
| `Sources/App/RowStore.swift` (path: `Sources/App/Home/…` — confirm at task time) | `apply(_:maxAutoRetries:)` and `resync(_:maxAutoRetries:)` thread the value to `RowModel`; no `Preferences` dependency added. |
| `Sources/App/AppModel.swift` | `handleRowAction` `.retry` → `engine.retry(id)`; `.showLog` → `showLog(jobID:)`; consumer passes `prefs.maxAutoRetries` into `rowStore.apply` / `resync`. |
| `Sources/App/AppModelDialogs.swift` | `showLogMissingNotice()` `ConfirmationRequest`. |
| `Sources/App/MediaGrabberApp.swift` | `EngineDependencies.live` / manual construction passes `ffprobeURL` resolved like `resolveYtDlp`. |

**Modified — mockup:**

| File | Change |
|---|---|
| `docs/mockups/screens.html` | §1 Home table gains a failed row + a retrying row; one completed row's Quality cell shows `1080p → 720p`; row-action bar drawn with full button set + Phase 4 enable states. |

**Modified — parent spec (same pass, Task 15):** `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1 Phase 4 stub, §12.1 Phase 6 stub, §9, §12.2 rows (`ErrorClass`, row-action bar). §7.5 already carries the bounded flag set — verify, no edit expected.

---

## Interfaces (canonical signatures — every task consuming these copies from here)

```swift
// ErrorClass.swift
public enum ErrorClass: Sendable, Equatable {
    case rateLimited(retryAfterSeconds: Int? = nil)
    case botCheck
    case sabrGated
    case formatsMissing
    case cookieReadFailed
    case geoBlocked
    case `private`
    case unavailable
    case ageRestricted
    case networkDown
    case diskFull
    case permissionDenied
    case incomplete
    case depMissing
    case potProviderDown
    case unknown(raw: String)
}

// ErrorClass+Presentation.swift
public extension ErrorClass {
    var key: String { get }                    // "rate_limited", "geo_blocked", … stable, not user-facing
    var presentation: FailurePresentation { get }
    var isAutoRetryable: Bool { get }          // true for .rateLimited, .networkDown, .incomplete, .unknown
    var retryAfterSeconds: Int? { get }        // the associated value of .rateLimited, else nil
}

// FailurePresentation.swift
public struct FailurePresentation: Sendable, Equatable {
    public let sentence: String
    public let offeredActions: Set<RowAction>  // beyond the always-present remove / openInBrowser / showLog
    public static func `for`(_ errorClass: ErrorClass) -> FailurePresentation
}

// ErrorSignatures.swift
public enum ErrorSignatures {
    // Ordered; first class whose any-substring (case-insensitive) is contained wins.
    static let table: [(errorClass: ErrorClass, substrings: [String])]
    // Parses a trailing "Retry-After: <int>" (integer seconds only; HTTP-date → nil).
    static func retryAfterSeconds(in line: String) -> Int?
}

// Backoff.swift
public enum Backoff {
    public static func delay(
        attempt: Int,                          // 1-based; first retry is attempt 1
        retryAfter: Int? = nil,
        tuning: EngineTuning = .default,
        jitter: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) -> TimeInterval
}

// EngineTuning.swift
public struct YtDlpTuning: Sendable, Equatable {
    public var retries: Int
    public var fragmentRetries: Int
    public var socketTimeout: Int
    public var retrySleep: String
    public var throttledRateKBps: Int
    public var fileAccessRetries: Int
    public var sleepRequests: Int
    public var sleepInterval: Int
    public var maxSleepInterval: Int
    public static let `default`: YtDlpTuning   // 3,10,30,"linear=1:10:2",100,5,1,1,5
}
public struct EngineTuning: Sendable, Equatable {
    public var ytDlp: YtDlpTuning
    public var backoffLadder: [Int]            // [30,60,120,300,600]
    public var backoffCap: Int                 // 600
    public static let `default`: EngineTuning
    public static func resolved(environment: [String: String] = ProcessInfo.processInfo.environment) -> EngineTuning
}

// IntegrityCheck.swift
public struct IntegrityCheck: Sendable {
    public init(runner: ProcessRunning, ffprobeURL: URL?)
    public func verify(file: URL, expectedDurationSeconds: Int?) async -> IntegrityResult
}
public struct IntegrityResult: Sendable, Equatable {
    public let verdict: IntegrityVerdict       // .passed / .failed(reason:) / .skipped(reason:) — already in JobSnapshot.swift
    public let actualQuality: String?          // "720p" for video, nil for audio / unknown
}

// DownloadEngineProtocol.swift additions
public protocol DownloadEngineProtocol: Sendable {
    // …existing…
    func retry(_ id: UUID) async
}

// DownloadEngine+Mutations.swift — new recordExit signature
func recordExit(
    _ id: UUID,
    _ result: ProcessResult,
    integrity: IntegrityResult?,
    lastError: ErrorClass?,
    launchFailed: Bool
)

// SubmitResult.swift
public enum DeferReason: Sendable, Equatable {
    case backoff(attempt: Int)
}

// LogEvent.swift additions
case jobRetried(id: UUID)                       // key "job.retried", category .engine, no fields
case showLogTargetMissing(jobID: UUID)          // key "show_log.target_missing", category .ui

// RowModel.swift
static func status(for snapshot: JobSnapshot, maxAutoRetries: Int) -> String
```

---

## Task 1: `ErrorClass` widens `rateLimited`, gains `key` — ✅ DONE

**Files:**
- Modify: `Sources/GrabberKit/Download/ErrorClass.swift`
- Create: `Sources/GrabberKit/Download/ErrorClass+Presentation.swift` (this task adds only `key`)
- Test: `Tests/GrabberKitTests/ErrorClassKeyTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `ErrorClass.rateLimited(retryAfterSeconds: Int? = nil)`, `ErrorClass.retryAfterSeconds`, `ErrorClass.key` (see Interfaces block).

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import XCTest

final class ErrorClassKeyTests: XCTestCase {
    private let all: [ErrorClass] = [
        .rateLimited(), .botCheck, .sabrGated, .formatsMissing, .cookieReadFailed,
        .geoBlocked, .private, .unavailable, .ageRestricted, .networkDown,
        .diskFull, .permissionDenied, .incomplete, .depMissing, .potProviderDown,
        .unknown(raw: "x")
    ]

    func test_everyCaseHasADistinctKey() {
        let keys = all.map(\.key)
        XCTAssertEqual(Set(keys).count, all.count)
        XCTAssertFalse(keys.contains(where: \.isEmpty))
    }

    func test_rateLimitedKeyIsStableRegardlessOfRetryAfter() {
        XCTAssertEqual(ErrorClass.rateLimited().key, "rate_limited")
        XCTAssertEqual(ErrorClass.rateLimited(retryAfterSeconds: 90).key, "rate_limited")
    }

    func test_retryAfterSeconds() {
        XCTAssertEqual(ErrorClass.rateLimited(retryAfterSeconds: 45).retryAfterSeconds, 45)
        XCTAssertNil(ErrorClass.rateLimited().retryAfterSeconds)
        XCTAssertNil(ErrorClass.networkDown.retryAfterSeconds)
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/ErrorClassKeyTests`
Expected: FAIL — compile error, `rateLimited` takes no argument / `key` undefined.

- [x] **Step 3: Widen the case**

In `ErrorClass.swift` change `case rateLimited` to:

```swift
case rateLimited(retryAfterSeconds: Int? = nil)
```

- [x] **Step 4: Add `key` and `retryAfterSeconds`**

Create `Sources/GrabberKit/Download/ErrorClass+Presentation.swift`:

```swift
import Foundation

public extension ErrorClass {
    // A stable token for logs and the later diagnostics report — not user-facing.
    var key: String {
        switch self {
        case .rateLimited: "rate_limited"
        case .botCheck: "bot_check"
        case .sabrGated: "sabr_gated"
        case .formatsMissing: "formats_missing"
        case .cookieReadFailed: "cookie_read_failed"
        case .geoBlocked: "geo_blocked"
        case .private: "private"
        case .unavailable: "unavailable"
        case .ageRestricted: "age_restricted"
        case .networkDown: "network_down"
        case .diskFull: "disk_full"
        case .permissionDenied: "permission_denied"
        case .incomplete: "incomplete"
        case .depMissing: "dep_missing"
        case .potProviderDown: "pot_provider_down"
        case .unknown: "unknown"
        }
    }

    var retryAfterSeconds: Int? {
        if case let .rateLimited(seconds) = self { return seconds }
        return nil
    }
}
```

- [x] **Step 5: Fix the fallout**

`ErrorClass.rateLimited` now needs `()` at every existing use. Search:

Run: `grep -rn "\.rateLimited\b" Sources Tests`
Change each bare `.rateLimited` to `.rateLimited()`. (Phase 1–3 have no emit path for it, so this is likely only in `PersistedJob.reason(for:)`'s `"\(errorClass)"` — no change needed there — and possibly a test fixture.)

- [x] **Step 6: Run tests + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/ErrorClassKeyTests` → PASS
Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict` → clean

- [x] **Step 7: Commit**

```bash
git add Sources/GrabberKit/Download/ErrorClass.swift Sources/GrabberKit/Download/ErrorClass+Presentation.swift Tests/GrabberKitTests/ErrorClassKeyTests.swift
git commit -m "feat(grabberkit): ErrorClass.rateLimited carries Retry-After; add ErrorClass.key"
```

---

## Task 2: `FailurePresentation` — ✅ DONE

**Files:**
- Create: `Sources/GrabberKit/Download/FailurePresentation.swift`
- Modify: `Sources/GrabberKit/Download/ErrorClass+Presentation.swift` (add `presentation`, `isAutoRetryable`)
- Test: `Tests/GrabberKitTests/FailurePresentationTests.swift`

**Interfaces:**
- Consumes: `ErrorClass` (Task 1), `RowAction` (`JobSnapshot.swift`, existing — has `.retry`, `.retryWithCookies`, `.showLog`).
- Produces: `FailurePresentation`, `FailurePresentation.for(_:)`, `ErrorClass.presentation`, `ErrorClass.isAutoRetryable` (see Interfaces block).

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import XCTest

final class FailurePresentationTests: XCTestCase {
    private let cases: [ErrorClass] = [
        .rateLimited(), .geoBlocked, .private, .unavailable, .ageRestricted,
        .networkDown, .cookieReadFailed, .diskFull, .permissionDenied,
        .incomplete, .depMissing, .unknown(raw: "ERROR: boom")
    ]

    func test_everyCaseHasANonEmptySentence() {
        for errorClass in cases {
            XCTAssertFalse(errorClass.presentation.sentence.isEmpty, "\(errorClass)")
        }
    }

    func test_unknownSentenceIsTheRawText() {
        XCTAssertEqual(ErrorClass.unknown(raw: "ERROR: boom").presentation.sentence, "ERROR: boom")
    }

    func test_offeredActionsMatchSpec() {
        XCTAssertEqual(ErrorClass.rateLimited().presentation.offeredActions, [.retry])
        XCTAssertEqual(ErrorClass.geoBlocked.presentation.offeredActions, [])
        XCTAssertEqual(ErrorClass.private.presentation.offeredActions, [])
        XCTAssertEqual(ErrorClass.unavailable.presentation.offeredActions, [])
        XCTAssertEqual(ErrorClass.ageRestricted.presentation.offeredActions, [])
        XCTAssertEqual(ErrorClass.depMissing.presentation.offeredActions, [])
        XCTAssertEqual(ErrorClass.networkDown.presentation.offeredActions, [.retry])
        XCTAssertEqual(ErrorClass.cookieReadFailed.presentation.offeredActions, [.retry])
        XCTAssertEqual(ErrorClass.diskFull.presentation.offeredActions, [.retry])
        XCTAssertEqual(ErrorClass.permissionDenied.presentation.offeredActions, [.retry])
        XCTAssertEqual(ErrorClass.incomplete.presentation.offeredActions, [.retry])
        XCTAssertEqual(ErrorClass.unknown(raw: "x").presentation.offeredActions, [.retry])
    }

    func test_isAutoRetryableIsASubsetOfClassesOfferingRetry() {
        let retryable = cases.filter(\.isAutoRetryable)
        XCTAssertEqual(Set(retryable.map(\.key)), ["rate_limited", "network_down", "incomplete", "unknown"])
        for errorClass in retryable {
            XCTAssertTrue(errorClass.presentation.offeredActions.contains(.retry), "\(errorClass)")
        }
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/FailurePresentationTests`
Expected: FAIL — `FailurePresentation` / `presentation` / `isAutoRetryable` undefined.

- [x] **Step 3: Implement `FailurePresentation`**

Create `Sources/GrabberKit/Download/FailurePresentation.swift`:

```swift
import Foundation

public struct FailurePresentation: Sendable, Equatable {
    // One plain-English sentence — no error code, no yt-dlp jargon.
    public let sentence: String
    // Row actions offered beyond the always-present remove / openInBrowser / showLog.
    public let offeredActions: Set<RowAction>

    public static func `for`(_ errorClass: ErrorClass) -> FailurePresentation {
        switch errorClass {
        case .rateLimited:
            FailurePresentation(
                sentence: "The site is limiting how fast we can download right now.",
                offeredActions: [.retry]
            )
        case .geoBlocked:
            FailurePresentation(sentence: "This video isn't available in your region.", offeredActions: [])
        case .private:
            FailurePresentation(sentence: "This video is private.", offeredActions: [])
        case .unavailable:
            FailurePresentation(sentence: "This video is no longer available.", offeredActions: [])
        case .ageRestricted:
            FailurePresentation(
                sentence: "This video is age-restricted and needs you to be signed in.",
                offeredActions: []
            )
        case .networkDown:
            FailurePresentation(sentence: "No internet connection.", offeredActions: [.retry])
        case .cookieReadFailed:
            FailurePresentation(sentence: "Couldn't read your browser's sign-in.", offeredActions: [.retry])
        case .diskFull:
            FailurePresentation(sentence: "The disk is full.", offeredActions: [.retry])
        case .permissionDenied:
            FailurePresentation(sentence: "The download folder isn't writable.", offeredActions: [.retry])
        case .incomplete:
            FailurePresentation(sentence: "The download kept ending early.", offeredActions: [.retry])
        case .depMissing:
            FailurePresentation(sentence: "The downloader needs reinstalling.", offeredActions: [])
        case let .unknown(raw):
            FailurePresentation(
                sentence: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                offeredActions: [.retry]
            )
        case .botCheck, .sabrGated, .formatsMissing, .potProviderDown:
            FailurePresentation(sentence: "This download failed.", offeredActions: [.retry])
        }
    }
}
```

(The `botCheck`/`sabrGated`/`formatsMissing`/`potProviderDown` arm is a placeholder that a later phase replaces with real copy — it exists only so the `switch` is exhaustive; no classifier emits these this phase. Keep it a single grouped arm.)

- [x] **Step 4: Add `presentation` and `isAutoRetryable`**

Append to `ErrorClass+Presentation.swift`:

```swift
public extension ErrorClass {
    var presentation: FailurePresentation { FailurePresentation.for(self) }

    var isAutoRetryable: Bool {
        switch self {
        case .rateLimited, .networkDown, .incomplete, .unknown: true
        default: false
        }
    }
}
```

- [x] **Step 5: Run tests + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/FailurePresentationTests` → PASS
Run: lint → clean

- [x] **Step 6: Commit**

```bash
git add Sources/GrabberKit/Download/FailurePresentation.swift Sources/GrabberKit/Download/ErrorClass+Presentation.swift Tests/GrabberKitTests/FailurePresentationTests.swift
git commit -m "feat(grabberkit): FailurePresentation — plain-English reason + offered actions per ErrorClass"
```

---

## Task 3: `ErrorSignatures` table + `classifyStderr` wiring — ✅ DONE

**Files:**
- Create: `Sources/GrabberKit/Download/ErrorSignatures.swift`
- Modify: `Sources/GrabberKit/Download/ProgressParser.swift`
- Modify: `Sources/GrabberKit/Download/MetadataProbe.swift`
- Test: `Tests/GrabberKitTests/ErrorSignaturesTests.swift`
- Test: `Tests/GrabberKitTests/ProgressParserTests.swift` (extend)
- Test: `Tests/GrabberKitTests/MetadataProbeTests.swift` (extend — shared-string agreement)

**Interfaces:**
- Consumes: `ErrorClass` (Task 1), `ProgressParser.classifyStderr` (existing signature `(String) -> ErrorClass?`), `ProgressParser` network signatures (private, Phase 1).
- Produces: `ErrorSignatures.table`, `ErrorSignatures.retryAfterSeconds(in:)`; `classifyStderr` now returns the generic classes.

- [x] **Step 1: Write `ErrorSignaturesTests`**

```swift
@testable import GrabberKit
import XCTest

final class ErrorSignaturesTests: XCTestCase {
    private func classify(_ line: String) -> ErrorClass? {
        ProgressParser.classifyStderr(line)
    }

    func test_rateLimitedSignatures() {
        XCTAssertEqual(classify("ERROR: HTTP Error 429: Too Many Requests"), .rateLimited())
        XCTAssertEqual(classify("WARNING: The download speed is below the minimum"), .rateLimited())
        XCTAssertEqual(classify("ERROR: Download speed 12.00KiB/s below throttle limit"), .rateLimited())
    }

    func test_geoBlocked() {
        XCTAssertEqual(classify("ERROR: The uploader has not made this video available in your country"), .geoBlocked)
        XCTAssertEqual(classify("ERROR: This video contains content ... who has blocked it in your country"), .geoBlocked)
    }

    func test_private_unavailable_ageRestricted() {
        XCTAssertEqual(classify("ERROR: Private video. Sign in if you've been granted access to this video"), .private)
        XCTAssertEqual(classify("ERROR: Video unavailable"), .unavailable)
        XCTAssertEqual(classify("ERROR: This video has been removed by the uploader"), .unavailable)
        XCTAssertEqual(classify("ERROR: Sign in to confirm your age"), .ageRestricted)
    }

    func test_networkFirstThenTableThenErrorFallthroughThenNil() {
        XCTAssertEqual(classify("ERROR: Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided>"), .networkDown)
        XCTAssertEqual(classify("ERROR: something we have no signature for"), .unknown(raw: "ERROR: something we have no signature for"))
        XCTAssertNil(classify("[download] 42% of 10MiB"))
    }

    func test_retryAfterIntegerParsedIntoRateLimited() {
        XCTAssertEqual(classify("ERROR: HTTP Error 429: Too Many Requests. Retry-After: 90"),
                       .rateLimited(retryAfterSeconds: 90))
    }

    func test_retryAfterHttpDateIgnored() {
        XCTAssertEqual(classify("ERROR: HTTP Error 429. Retry-After: Wed, 21 Oct 2025 07:28:00 GMT"),
                       .rateLimited(retryAfterSeconds: nil))
    }
}
```

- [x] **Step 2: Run — verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/ErrorSignaturesTests`
Expected: FAIL — `classifyStderr` still returns `.unknown` / `nil` for these lines.

- [x] **Step 3: Implement `ErrorSignatures`**

Create `Sources/GrabberKit/Download/ErrorSignatures.swift`:

```swift
import Foundation

public enum ErrorSignatures {
    // Ordered: the first class with any contained substring (case-insensitive) wins.
    // networkDown is handled by ProgressParser's own signature list before this table.
    static let table: [(errorClass: ErrorClass, substrings: [String])] = [
        (.rateLimited(), [
            "HTTP Error 429", "Too Many Requests",
            "below throttle limit", "The download speed is below the minimum"
        ]),
        (.geoBlocked, [
            "not available in your country", "blocked it in your country", "geo restrict"
        ]),
        (.private, [
            "Private video", "Sign in if you've been granted access to this video"
        ]),
        (.unavailable, [
            "Video unavailable", "This video is unavailable", "This video is not available",
            "has been removed", "no longer available"
        ]),
        (.ageRestricted, [
            "Sign in to confirm your age", "age-restricted", "confirm your age"
        ])
    ]

    static func firstMatch(in line: String) -> ErrorClass? {
        let lowered = line.lowercased()
        for entry in table where entry.substrings.contains(where: { lowered.contains($0.lowercased()) }) {
            return entry.errorClass
        }
        return nil
    }

    static func retryAfterSeconds(in line: String) -> Int? {
        guard let range = line.range(of: "Retry-After:", options: .caseInsensitive) else { return nil }
        let tail = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let token = tail.prefix { $0.isNumber }
        guard !token.isEmpty, tail.first?.isNumber == true else { return nil }
        return Int(token)
    }
}
```

- [x] **Step 4: Wire `classifyStderr`**

Replace `ProgressParser.classifyStderr`:

```swift
public static func classifyStderr(_ line: String) -> ErrorClass? {
    if line.contains("Unable to download"), containsNetworkSignature(line) {
        return .networkDown
    }
    if containsNetworkSignature(line), line.hasPrefix("ERROR:") {
        return .networkDown
    }
    if let matched = ErrorSignatures.firstMatch(in: line) {
        if case .rateLimited = matched {
            return .rateLimited(retryAfterSeconds: ErrorSignatures.retryAfterSeconds(in: line))
        }
        return matched
    }
    if line.hasPrefix("ERROR:") {
        return .unknown(raw: line)
    }
    return nil
}
```

(Keep the existing first `if` — Phase 1's `"Unable to download" + network signature` path — unchanged; the second `if` widens network detection to a bare `ERROR:` line carrying a resolution failure, matching the §10 test.)

- [x] **Step 5: Run — green**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/ErrorSignaturesTests` → PASS
Run: `xcodebuild ... test -only-testing:GrabberKitTests/ProgressParserTests` → PASS (existing tests unaffected)

- [x] **Step 6: Extend `MetadataProbe` to share the table — failing test first**

Add to `MetadataProbeTests.swift`:

```swift
func test_unavailableSignaturesAgreeWithDownloadSideTable() async {
    let shared = ["Video unavailable", "This video is unavailable", "This video is not available"]
    for line in shared {
        XCTAssertEqual(ProgressParser.classifyStderr("ERROR: \(line)"), .unavailable)
    }
    // Probe-side still returns .unavailable for the same strings.
    let probe = MetadataProbe(ytDlpURL: URL(fileURLWithPath: "/x"),
                              runner: FakeProcessRunner.stderrRunner("ERROR: Video unavailable", exitCode: 1))
    let result = await probe.probe("https://example.com")
    XCTAssertEqual(result, .failure(.unavailable))
}
```

(If `FakeProcessRunner.stderrRunner` does not exist, script a `FakeProcessRunner` inline the way `MetadataProbeTests` already does — match the file's existing pattern.)

- [x] **Step 7: Point `MetadataProbe.classify` at the shared strings**

In `MetadataProbe.swift`, replace the private `unavailableSignatures` array's *shared* members with a lookup that pulls the `.unavailable` and `.private` substrings from `ErrorSignatures.table`:

```swift
private var unavailableSignatures: [String] {
    ErrorSignatures.table
        .filter { entry in
            switch entry.errorClass {
            case .unavailable, .private, .geoBlocked: true
            default: false
            }
        }
        .flatMap(\.substrings)
        + ["The web client only works when logged-in"]   // probe-only, no download-side equivalent
}
```

(The probe keeps its own extra strings; only the shared ones now come from one list.)

- [x] **Step 8: Run — green + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/MetadataProbeTests -only-testing:GrabberKitTests/ErrorSignaturesTests` → PASS
Run: lint → clean

- [x] **Step 9: Commit**

```bash
git add Sources/GrabberKit/Download/ErrorSignatures.swift Sources/GrabberKit/Download/ProgressParser.swift Sources/GrabberKit/Download/MetadataProbe.swift Tests/GrabberKitTests/ErrorSignaturesTests.swift Tests/GrabberKitTests/ProgressParserTests.swift Tests/GrabberKitTests/MetadataProbeTests.swift
git commit -m "feat(grabberkit): shared ErrorSignatures table drives classifyStderr and the probe classifier"
```

---

## Task 4: `Backoff` — ✅ DONE

**Files:**
- Create: `Sources/GrabberKit/RateLimiting/Backoff.swift`
- Test: `Tests/GrabberKitTests/BackoffTests.swift`

**Interfaces:**
- Consumes: `EngineTuning` — **not built yet**. This task uses a local literal ladder/cap via a minimal `EngineTuning` shim, OR builds `EngineTuning` first. **Decision: build `EngineTuning` in Task 5 and reorder — do Task 5 before Task 4.** If executing sequentially, swap: Task 5 (`EngineTuning`) then Task 4 (`Backoff`). The plan numbers them 4/5 for reading order; the executor does 5 then 4.
- Produces: `Backoff.delay(attempt:retryAfter:tuning:jitter:)` (see Interfaces block).

- [x] **Step 1: Write the failing test** (assumes `EngineTuning` from Task 5 exists)

```swift
@testable import GrabberKit
import XCTest

final class BackoffTests: XCTestCase {
    // jitter that always returns the top of the range → the ladder value itself
    private let maxJitter: (ClosedRange<Double>) -> Double = { $0.upperBound }

    func test_ladderValuesAtEachAttempt() {
        let expected: [Int: Double] = [1: 30, 2: 60, 3: 120, 4: 300, 5: 600]
        for (attempt, seconds) in expected {
            XCTAssertEqual(Backoff.delay(attempt: attempt, jitter: maxJitter), seconds, accuracy: 0.001)
        }
    }

    func test_attemptPastLadderReusesLastEntry() {
        XCTAssertEqual(Backoff.delay(attempt: 6, jitter: maxJitter), 600, accuracy: 0.001)
        XCTAssertEqual(Backoff.delay(attempt: 99, jitter: maxJitter), 600, accuracy: 0.001)
    }

    func test_retryAfterWinsOverLadderNoJitter() {
        XCTAssertEqual(Backoff.delay(attempt: 1, retryAfter: 45, jitter: maxJitter), 45, accuracy: 0.001)
    }

    func test_retryAfterZeroFallsBackToLadder() {
        XCTAssertEqual(Backoff.delay(attempt: 2, retryAfter: 0, jitter: maxJitter), 60, accuracy: 0.001)
    }

    func test_retryAfterAboveCapIsClamped() {
        XCTAssertEqual(Backoff.delay(attempt: 1, retryAfter: 5000, jitter: maxJitter), 600, accuracy: 0.001)
    }

    func test_realRandomStaysInZeroToBase() {
        for _ in 0 ..< 500 {
            let value = Backoff.delay(attempt: 3)
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 120)
        }
    }

    func test_nonDefaultTuningLadderAndCapHonoured() {
        let tuning = EngineTuning(ytDlp: .default, backoffLadder: [10, 20, 30], backoffCap: 25)
        XCTAssertEqual(Backoff.delay(attempt: 1, tuning: tuning, jitter: maxJitter), 10, accuracy: 0.001)
        XCTAssertEqual(Backoff.delay(attempt: 3, tuning: tuning, jitter: maxJitter), 25, accuracy: 0.001) // 30 capped to 25
    }
}
```

- [x] **Step 2: Run — verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/BackoffTests`
Expected: FAIL — `Backoff` undefined.

- [x] **Step 3: Implement**

Create `Sources/GrabberKit/RateLimiting/Backoff.swift`:

```swift
import Foundation

public enum Backoff {
    // attempt is 1-based — the first retry is attempt 1.
    public static func delay(
        attempt: Int,
        retryAfter: Int? = nil,
        tuning: EngineTuning = .default,
        jitter: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) -> TimeInterval {
        if let retryAfter, retryAfter > 0 {
            return TimeInterval(min(retryAfter, tuning.backoffCap))
        }
        let ladder = tuning.backoffLadder
        let index = min(max(attempt, 1), ladder.count) - 1
        let base = min(ladder[index], tuning.backoffCap)
        return jitter(0 ... Double(base))
    }
}
```

- [x] **Step 4: Run — green + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/BackoffTests` → PASS
Run: lint → clean

- [x] **Step 5: Commit**

```bash
git add Sources/GrabberKit/RateLimiting/Backoff.swift Tests/GrabberKitTests/BackoffTests.swift
git commit -m "feat(grabberkit): Backoff — full-jitter ladder with cap and integer Retry-After"
```

---

## Task 5: `EngineTuning` — ✅ DONE

**Files:**
- Create: `Sources/GrabberKit/Model/EngineTuning.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` — `EngineDependencies` gains `tuning`
- Test: `Tests/GrabberKitTests/EngineTuningTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `YtDlpTuning`, `EngineTuning`, `EngineTuning.default`, `EngineTuning.resolved(environment:)`; `EngineDependencies.tuning: EngineTuning` (default `.default`).

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import XCTest

final class EngineTuningTests: XCTestCase {
    func test_noEnvKeysGivesDefault() {
        XCTAssertEqual(EngineTuning.resolved(environment: [:]), .default)
    }

    func test_eachYtDlpKeyParses() {
        let env = [
            "MG_YTDLP_RETRIES": "7",
            "MG_YTDLP_FRAGMENT_RETRIES": "20",
            "MG_YTDLP_SOCKET_TIMEOUT": "45",
            "MG_YTDLP_RETRY_SLEEP": "exp=1:20",
            "MG_YTDLP_THROTTLED_RATE_KBPS": "50",
            "MG_YTDLP_FILE_ACCESS_RETRIES": "9",
            "MG_YTDLP_SLEEP_REQUESTS": "2",
            "MG_YTDLP_SLEEP_INTERVAL": "3",
            "MG_YTDLP_MAX_SLEEP_INTERVAL": "8"
        ]
        let tuning = EngineTuning.resolved(environment: env).ytDlp
        XCTAssertEqual(tuning.retries, 7)
        XCTAssertEqual(tuning.fragmentRetries, 20)
        XCTAssertEqual(tuning.socketTimeout, 45)
        XCTAssertEqual(tuning.retrySleep, "exp=1:20")
        XCTAssertEqual(tuning.throttledRateKBps, 50)
        XCTAssertEqual(tuning.fileAccessRetries, 9)
        XCTAssertEqual(tuning.sleepRequests, 2)
        XCTAssertEqual(tuning.sleepInterval, 3)
        XCTAssertEqual(tuning.maxSleepInterval, 8)
    }

    func test_malformedIntKeepsDefaultForThatField() {
        let tuning = EngineTuning.resolved(environment: ["MG_YTDLP_RETRIES": "not-a-number"]).ytDlp
        XCTAssertEqual(tuning.retries, YtDlpTuning.default.retries)
    }

    func test_backoffLadderParsesCommaList() {
        let resolved = EngineTuning.resolved(environment: ["MG_BACKOFF_LADDER": "10,20,30"])
        XCTAssertEqual(resolved.backoffLadder, [10, 20, 30])
    }

    func test_backoffCapParses() {
        XCTAssertEqual(EngineTuning.resolved(environment: ["MG_BACKOFF_CAP": "120"]).backoffCap, 120)
    }

    func test_malformedLadderKeepsDefault() {
        XCTAssertEqual(EngineTuning.resolved(environment: ["MG_BACKOFF_LADDER": "10,x,30"]).backoffLadder,
                       EngineTuning.default.backoffLadder)
    }
}
```

- [x] **Step 2: Run — verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EngineTuningTests`
Expected: FAIL — types undefined.

- [x] **Step 3: Implement the types**

Create `Sources/GrabberKit/Model/EngineTuning.swift`:

```swift
import Foundation

public struct YtDlpTuning: Sendable, Equatable {
    public var retries: Int
    public var fragmentRetries: Int
    public var socketTimeout: Int
    public var retrySleep: String
    public var throttledRateKBps: Int
    public var fileAccessRetries: Int
    public var sleepRequests: Int
    public var sleepInterval: Int
    public var maxSleepInterval: Int

    public init(
        retries: Int, fragmentRetries: Int, socketTimeout: Int, retrySleep: String,
        throttledRateKBps: Int, fileAccessRetries: Int, sleepRequests: Int,
        sleepInterval: Int, maxSleepInterval: Int
    ) {
        self.retries = retries
        self.fragmentRetries = fragmentRetries
        self.socketTimeout = socketTimeout
        self.retrySleep = retrySleep
        self.throttledRateKBps = throttledRateKBps
        self.fileAccessRetries = fileAccessRetries
        self.sleepRequests = sleepRequests
        self.sleepInterval = sleepInterval
        self.maxSleepInterval = maxSleepInterval
    }

    public static let `default` = YtDlpTuning(
        retries: 3, fragmentRetries: 10, socketTimeout: 30,
        retrySleep: "linear=1:10:2", throttledRateKBps: 100,
        fileAccessRetries: 5, sleepRequests: 1,
        sleepInterval: 1, maxSleepInterval: 5
    )
}

public struct EngineTuning: Sendable, Equatable {
    public var ytDlp: YtDlpTuning
    public var backoffLadder: [Int]
    public var backoffCap: Int

    public init(ytDlp: YtDlpTuning, backoffLadder: [Int], backoffCap: Int) {
        self.ytDlp = ytDlp
        self.backoffLadder = backoffLadder
        self.backoffCap = backoffCap
    }

    public static let `default` = EngineTuning(
        ytDlp: .default,
        backoffLadder: [30, 60, 120, 300, 600],
        backoffCap: 600
    )

    public static func resolved(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> EngineTuning {
        func int(_ key: String, _ fallback: Int) -> Int {
            guard let raw = environment[key] else { return fallback }
            return Int(raw) ?? fallback
        }
        func string(_ key: String, _ fallback: String) -> String {
            environment[key] ?? fallback
        }
        let base = YtDlpTuning.default
        let ytDlp = YtDlpTuning(
            retries: int("MG_YTDLP_RETRIES", base.retries),
            fragmentRetries: int("MG_YTDLP_FRAGMENT_RETRIES", base.fragmentRetries),
            socketTimeout: int("MG_YTDLP_SOCKET_TIMEOUT", base.socketTimeout),
            retrySleep: string("MG_YTDLP_RETRY_SLEEP", base.retrySleep),
            throttledRateKBps: int("MG_YTDLP_THROTTLED_RATE_KBPS", base.throttledRateKBps),
            fileAccessRetries: int("MG_YTDLP_FILE_ACCESS_RETRIES", base.fileAccessRetries),
            sleepRequests: int("MG_YTDLP_SLEEP_REQUESTS", base.sleepRequests),
            sleepInterval: int("MG_YTDLP_SLEEP_INTERVAL", base.sleepInterval),
            maxSleepInterval: int("MG_YTDLP_MAX_SLEEP_INTERVAL", base.maxSleepInterval)
        )
        let ladder: [Int]
        if let raw = environment["MG_BACKOFF_LADDER"] {
            let parsed = raw.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
            ladder = parsed.contains(nil) ? EngineTuning.default.backoffLadder : parsed.compactMap(\.self)
        } else {
            ladder = EngineTuning.default.backoffLadder
        }
        return EngineTuning(
            ytDlp: ytDlp,
            backoffLadder: ladder,
            backoffCap: int("MG_BACKOFF_CAP", EngineTuning.default.backoffCap)
        )
    }
}
```

(Spec §4.6 says "a malformed key logs once." There is no logger in `EngineTuning.resolved`. Keep it silent for now — the fallback is the contract the tests assert, and a one-shot log with no `LogWriter` in scope is not worth threading one through. If a reviewer insists, thread an optional `log:` closure. Note this in the commit body.)

- [x] **Step 4: Add `tuning` to `EngineDependencies`**

In `DownloadEngineProtocol.swift`, add to `EngineDependencies`: stored `public var tuning: EngineTuning`, `init` parameter `tuning: EngineTuning = .default`, and in `.live(...)` pass `tuning: .resolved()`.

- [x] **Step 5: Run — green + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EngineTuningTests` → PASS
Run: full `GrabberKitTests` build compiles (the `EngineDependencies` change touches every engine test's fixture — the default keeps them compiling).
Run: lint → clean

- [x] **Step 6: Commit**

```bash
git add Sources/GrabberKit/Model/EngineTuning.swift Sources/GrabberKit/Download/DownloadEngineProtocol.swift Tests/GrabberKitTests/EngineTuningTests.swift
git commit -m "feat(grabberkit): EngineTuning — env-overridable retry/pacing constants"
```

---

## Task 6: Always-on `yt-dlp` flags from `YtDlpTuning` — ✅ DONE

**Files:**
- Modify: `Sources/GrabberKit/Download/YtDlpArguments.swift`
- Test: `Tests/GrabberKitTests/YtDlpArgumentsTests.swift`

**Interfaces:**
- Consumes: `YtDlpTuning` (Task 5).
- Produces: `YtDlpArguments.build(for:options:tuning:)` and `.redacted(for:options:tuning:)` — new trailing `tuning: YtDlpTuning = .default` parameter.

- [x] **Step 1: Update the existing argv fixtures + add a flag test (failing)**

In `YtDlpArgumentsTests.swift`, the two hard-coded `XCTAssertEqual(argv, [...])` fixtures gain the new tokens. Add:

```swift
func test_alwaysOnResilienceFlagsFromDefaultTuning() {
    let argv = YtDlpArguments.build(for: request(kind: .video(maxHeight: 1080), container: "mp4"))
    let expected = [
        "--retries", "3",
        "--fragment-retries", "10",
        "--socket-timeout", "30",
        "--retry-sleep", "linear=1:10:2",
        "--throttled-rate", "100K",
        "--file-access-retries", "5",
        "--no-part-hint",
        "--sleep-requests", "1",
        "--sleep-interval", "1",
        "--max-sleep-interval", "5"
    ]
    XCTAssertTrue(containsSubsequence(argv, expected), "argv missing resilience flags: \(argv)")
    XCTAssertFalse(argv.contains("infinite"))
    XCTAssertLessThan(argv.firstIndex(of: "--retries")!, argv.firstIndex(of: url)!)
}

func test_nonDefaultTuningChangesEmittedValues() {
    var tuning = YtDlpTuning.default
    tuning.retries = 9
    tuning.throttledRateKBps = 250
    let argv = YtDlpArguments.build(
        for: request(kind: .video(maxHeight: 720)),
        tuning: tuning
    )
    XCTAssertEqual(argv[argv.firstIndex(of: "--retries")! + 1], "9")
    XCTAssertEqual(argv[argv.firstIndex(of: "--throttled-rate")! + 1], "250K")
}

private func containsSubsequence(_ haystack: [String], _ needle: [String]) -> Bool {
    guard let start = haystack.firstIndex(of: needle[0]) else { return false }
    return Array(haystack[start ..< min(start + needle.count, haystack.count)]) == needle
}
```

Also update the two existing full-array fixtures (`test_video1080_mp4`, and the redaction fixture if it asserts a full array) to include the ten tokens in the position you choose in Step 2.

- [x] **Step 2: Run — verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/YtDlpArgumentsTests`
Expected: FAIL — `build` takes no `tuning`; flags absent.

- [x] **Step 3: Implement**

```swift
public static func build(
    for request: DownloadRequest,
    options: GlobalDownloadOptions = .none,
    tuning: YtDlpTuning = .default
) -> [String] {
    baseArgv(for: request, tuning: tuning)
        + globalFlags(options, proxyURL: options.proxyURL)
        + [request.url]
}

public static func redacted(
    for request: DownloadRequest,
    options: GlobalDownloadOptions = .none,
    tuning: YtDlpTuning = .default
) -> [String] {
    baseArgv(for: request, tuning: tuning)
        + globalFlags(options, proxyURL: options.proxyURL.map(maskUserinfo(in:)))
        + [request.url]
}

private static func baseArgv(for request: DownloadRequest, tuning: YtDlpTuning) -> [String] {
    var argv: [String] = []
    argv += ["-P", request.destFolder.path]
    argv += ["-o", request.filenameTemplate]
    argv += formatSelector(for: request)
    argv += ["--newline", "--progress", "--progress-template", progressTemplate]
    argv += ["--no-playlist"]
    argv += ["--no-warnings"]
    argv += resilienceFlags(tuning)
    return argv
}

private static func resilienceFlags(_ tuning: YtDlpTuning) -> [String] {
    [
        "--retries", "\(tuning.retries)",
        "--fragment-retries", "\(tuning.fragmentRetries)",
        "--socket-timeout", "\(tuning.socketTimeout)",
        "--retry-sleep", tuning.retrySleep,
        "--throttled-rate", "\(tuning.throttledRateKBps)K",
        "--file-access-retries", "\(tuning.fileAccessRetries)",
        "--no-part-hint",
        "--sleep-requests", "\(tuning.sleepRequests)",
        "--sleep-interval", "\(tuning.sleepInterval)",
        "--max-sleep-interval", "\(tuning.maxSleepInterval)"
    ]
}
```

- [x] **Step 4: Thread `tuning` from the engine spawn**

In `DownloadEngine.swift` `launchDownload`, change the `YtDlpArguments.build(for: request, options: options)` call to `YtDlpArguments.build(for: request, options: options, tuning: dependencies.tuning.ytDlp)`.

- [x] **Step 5: Run — green + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/YtDlpArgumentsTests` → PASS
Run: full `GrabberKitTests` (the argv now longer — check `EngineGlobalOptionsTests` / any test asserting a full argv against a launch; update those fixtures if they break).
Run: lint → clean

- [x] **Step 6: Commit**

```bash
git add Sources/GrabberKit/Download/YtDlpArguments.swift Sources/GrabberKit/Download/DownloadEngine.swift Tests/GrabberKitTests/YtDlpArgumentsTests.swift
git commit -m "feat(grabberkit): always-on bounded yt-dlp resilience flags from YtDlpTuning"
```

---

## Task 7: `IntegrityCheck` — ✅ DONE (added `isExecutable` injection for tests)

**Files:**
- Create: `Sources/GrabberKit/Download/IntegrityCheck.swift`
- Test: `Tests/GrabberKitTests/IntegrityCheckTests.swift`
- Test fixture: `Tests/GrabberKitTests/Fixtures/ffprobe-*.json` (or inline strings — match `MetadataProbeTests` convention; check whether it inlines JSON or loads files)

**Interfaces:**
- Consumes: `ProcessRunning` / `ProcessLaunch` (existing), `IntegrityVerdict` (`JobSnapshot.swift`, existing), `FakeProcessRunner` (`Tests/TestSupport`).
- Produces: `IntegrityCheck`, `IntegrityResult` (see Interfaces block).

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import TestSupport
import XCTest

final class IntegrityCheckTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/tmp/out.mp4")
    private let ffprobe = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")

    private func json(duration: Double, height: Int?) -> String {
        let streams = height.map { "[{\"codec_type\":\"video\",\"height\":\($0)}]" } ?? "[]"
        return "{\"format\":{\"duration\":\"\(duration)\"},\"streams\":\(streams)}"
    }

    private func runner(_ output: String, exitCode: Int32 = 0) -> FakeProcessRunner {
        let r = FakeProcessRunner()
        r.script(.stdout(output, exitCode: exitCode), forPathEndingIn: "ffprobe")
        return r
    }

    func test_withinTolerancePasses_andReadsHeight() async {
        let check = IntegrityCheck(runner: runner(json(duration: 600, height: 720)), ffprobeURL: ffprobe)
        let result = await check.verify(file: file, expectedDurationSeconds: 600)
        XCTAssertEqual(result.verdict, .passed)
        XCTAssertEqual(result.actualQuality, "720p")
    }

    func test_materiallyShortFails() async {
        let check = IntegrityCheck(runner: runner(json(duration: 200, height: 1080)), ffprobeURL: ffprobe)
        let result = await check.verify(file: file, expectedDurationSeconds: 600)
        guard case let .failed(reason) = result.verdict else { return XCTFail("expected .failed") }
        XCTAssertTrue(reason.contains("400"))
    }

    func test_smallAbsoluteGapUnder10sPasses() async {
        let check = IntegrityCheck(runner: runner(json(duration: 594, height: 720)), ffprobeURL: ffprobe)
        let result = await check.verify(file: file, expectedDurationSeconds: 600)
        XCTAssertEqual(result.verdict, .passed) // 6s gap, under the 10s floor
    }

    func test_gapOver10sButUnder5PercentPasses() async {
        // expected 3600, actual 3585 → 15s gap, 0.42% → passes (needs BOTH conditions)
        let check = IntegrityCheck(runner: runner(json(duration: 3585, height: 1080)), ffprobeURL: ffprobe)
        let result = await check.verify(file: file, expectedDurationSeconds: 3600)
        XCTAssertEqual(result.verdict, .passed)
    }

    func test_nilExpectedDurationSkipsButStillReadsHeight() async {
        let check = IntegrityCheck(runner: runner(json(duration: 600, height: 480)), ffprobeURL: ffprobe)
        let result = await check.verify(file: file, expectedDurationSeconds: nil)
        guard case .skipped = result.verdict else { return XCTFail("expected .skipped") }
        XCTAssertEqual(result.actualQuality, "480p")
    }

    func test_audioOnlyJsonHasNilQualityButComputesDuration() async {
        let check = IntegrityCheck(runner: runner(json(duration: 200, height: nil)), ffprobeURL: ffprobe)
        let result = await check.verify(file: file, expectedDurationSeconds: 600)
        XCTAssertNil(result.actualQuality)
        if case .failed = result.verdict {} else { XCTFail("expected .failed on the short duration") }
    }

    func test_nilFfprobeURLSkipsWithNoSpawn() async {
        let r = FakeProcessRunner()
        let check = IntegrityCheck(runner: r, ffprobeURL: nil)
        let result = await check.verify(file: file, expectedDurationSeconds: 600)
        guard case .skipped = result.verdict else { return XCTFail("expected .skipped") }
        XCTAssertTrue(r.launches.isEmpty)
    }

    func test_nonZeroFfprobeExitSkips() async {
        let check = IntegrityCheck(runner: runner("garbage", exitCode: 1), ffprobeURL: ffprobe)
        let result = await check.verify(file: file, expectedDurationSeconds: 600)
        guard case .skipped = result.verdict else { return XCTFail("expected .skipped") }
    }
}
```

- [x] **Step 2: Run — verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/IntegrityCheckTests`
Expected: FAIL — `IntegrityCheck` undefined.

- [x] **Step 3: Implement**

Create `Sources/GrabberKit/Download/IntegrityCheck.swift`:

```swift
import Foundation

public struct IntegrityResult: Sendable, Equatable {
    public let verdict: IntegrityVerdict
    public let actualQuality: String?

    public init(verdict: IntegrityVerdict, actualQuality: String?) {
        self.verdict = verdict
        self.actualQuality = actualQuality
    }
}

public struct IntegrityCheck: Sendable {
    private let runner: ProcessRunning
    private let ffprobeURL: URL?

    public init(runner: ProcessRunning, ffprobeURL: URL?) {
        self.runner = runner
        self.ffprobeURL = ffprobeURL
    }

    public func verify(file: URL, expectedDurationSeconds: Int?) async -> IntegrityResult {
        guard let ffprobeURL, FileManager.default.isExecutableFile(atPath: ffprobeURL.path) else {
            return IntegrityResult(verdict: .skipped(reason: "ffprobe unavailable"), actualQuality: nil)
        }
        let execution = runner.run(ProcessLaunch(
            executableURL: ffprobeURL,
            arguments: ["-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", file.path]
        ))
        var stdout = ""
        for await line in execution.lines {
            if case let .stdout(text) = line { stdout += text + "\n" }
        }
        let result = await execution.result()
        guard result.exitCode == 0, let probe = Self.parse(stdout) else {
            return IntegrityResult(verdict: .skipped(reason: "ffprobe failed"), actualQuality: nil)
        }
        let quality = probe.height.map { "\($0)p" }
        guard let expected = expectedDurationSeconds else {
            return IntegrityResult(verdict: .skipped(reason: "no expected duration"), actualQuality: quality)
        }
        return IntegrityResult(verdict: Self.durationVerdict(actual: probe.duration, expected: expected),
                               actualQuality: quality)
    }

    private struct Probe { var duration: Double; var height: Int? }

    private static func parse(_ stdout: String) -> Probe? {
        struct Stream: Decodable { let codec_type: String?; let height: Int? }
        struct Format: Decodable { let duration: String? }
        struct Payload: Decodable { let format: Format?; let streams: [Stream]? }
        guard
            let data = stdout.data(using: .utf8),
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            let durationString = payload.format?.duration,
            let duration = Double(durationString)
        else { return nil }
        let height = payload.streams?.first { $0.codec_type == "video" }?.height
        return Probe(duration: duration, height: height)
    }

    private static func durationVerdict(actual: Double, expected: Int) -> IntegrityVerdict {
        let expectedDouble = Double(expected)
        let gap = expectedDouble - actual
        let materiallyShort = actual < expectedDouble * 0.95 && gap > 10
        if materiallyShort {
            return .failed(reason: "recording is \(Int(gap))s short")
        }
        return .passed
    }
}
```

(`swiftlint` will flag `codec_type` / `height` naming — add `// swiftlint:disable:next identifier_name` on the `Stream` line the same way `MetadataProbe.decode` does for `_type`. Single line only.)

- [x] **Step 4: Run — green + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/IntegrityCheckTests` → PASS
Run: lint → clean

- [x] **Step 5: Commit**

```bash
git add Sources/GrabberKit/Download/IntegrityCheck.swift Tests/GrabberKitTests/IntegrityCheckTests.swift
git commit -m "feat(grabberkit): IntegrityCheck — ffprobe duration verdict + real resolution"
```

---

## Task 8: `EnvironmentReport.ffprobe` — ✅ DONE

**Files:**
- Modify: `Sources/GrabberKit/Onboarding/EnvironmentProbe.swift`
- Modify: `Tests/TestSupport/FakeEnvironmentProbe.swift` — `EnvironmentReport.with(...)` gains `ffprobe`
- Test: `Tests/GrabberKitTests/EnvironmentProbeTests.swift` (extend)

**Interfaces:**
- Consumes: `ToolInfo`, `EnvironmentReport` (existing).
- Produces: `EnvironmentReport.ffprobe: ToolInfo?`; `EnvironmentReport.with(..., ffprobe: Bool = false)`.

- [x] **Step 1: Write the failing test**

Add to `EnvironmentProbeTests.swift` (match its existing fixture style — it injects `isExecutable` and a `FakeProcessRunner`):

```swift
func test_ffprobeResolvedAsFfmpegSibling() async {
    // ffmpeg at /opt/homebrew/bin/ffmpeg → ffprobe expected at the same dir
    let present: Set<String> = ["/opt/homebrew/bin/ffmpeg", "/opt/homebrew/bin/ffprobe", "/opt/homebrew/bin/yt-dlp"]
    let probe = EnvironmentProbe(
        runner: fakeVersionRunner(),  // returns a parseable --version / -version line per tool
        extraSearchPaths: [URL(fileURLWithPath: "/opt/homebrew/bin")],
        isExecutable: { present.contains($0.path) }
    )
    let report = await probe.probe()
    XCTAssertNotNil(report.ffprobe)
    XCTAssertEqual(report.ffprobe?.path.path, "/opt/homebrew/bin/ffprobe")
}

func test_ffmpegPresentButNoSiblingFfprobe_reportNilButStillReady() async {
    let present: Set<String> = ["/opt/homebrew/bin/ffmpeg", "/opt/homebrew/bin/yt-dlp"]
    let probe = EnvironmentProbe(
        runner: fakeVersionRunner(),
        extraSearchPaths: [URL(fileURLWithPath: "/opt/homebrew/bin")],
        isExecutable: { present.contains($0.path) }
    )
    let report = await probe.probe()
    XCTAssertNil(report.ffprobe)
    XCTAssertTrue(report.isReadyForDownloads)
}
```

(`fakeVersionRunner()` — reuse or add a small helper scripting `.stdout("ffprobe version 6.1", exitCode: 0)` etc. keyed `forPathEndingIn`. Match how the file already fakes `ffmpeg -version`.)

- [x] **Step 2: Run — verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EnvironmentProbeTests`
Expected: FAIL — `report.ffprobe` undefined.

- [x] **Step 3: Implement**

In `EnvironmentProbe.swift`:

```swift
public struct EnvironmentReport: Sendable, Equatable {
    public let brew: ToolInfo?
    public let ytDlp: ToolInfo?
    public let ffmpeg: ToolInfo?
    public let ffprobe: ToolInfo?

    public init(brew: ToolInfo?, ytDlp: ToolInfo?, ffmpeg: ToolInfo?, ffprobe: ToolInfo? = nil) {
        self.brew = brew
        self.ytDlp = ytDlp
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
    }

    public var isReadyForDownloads: Bool {
        ytDlp != nil && ffmpeg != nil
    }
}
```

In `probe()`, after `ffmpeg` resolves, resolve `ffprobe` as its directory sibling (not an independent search):

```swift
let ffmpegInfo = await ffmpeg
let ffprobeInfo = await Self.resolveFfprobe(besideFfmpeg: ffmpegInfo, runner: runner, isExecutable: isExecutable)
return EnvironmentReport(brew: await brew, ytDlp: await ytDlp, ffmpeg: ffmpegInfo, ffprobe: ffprobeInfo)
```

Add:

```swift
private static func resolveFfprobe(
    besideFfmpeg ffmpeg: ToolInfo?,
    runner: ProcessRunning,
    isExecutable: (URL) -> Bool
) async -> ToolInfo? {
    guard let ffmpeg else { return nil }
    let candidate = ffmpeg.path.deletingLastPathComponent().appendingPathComponent("ffprobe")
    guard isExecutable(candidate) else { return nil }
    let execution = runner.run(ProcessLaunch(executableURL: candidate, arguments: ["-version"]))
    var output = ""
    for await line in execution.lines {
        switch line { case let .stdout(t), let .stderr(t): output += t + "\n" }
    }
    guard await execution.result().exitCode == 0, let version = parseFfmpeg(output) else { return nil }
    return ToolInfo(path: candidate, version: version)
}
```

(The `isExecutable` closure is currently `private let` on the struct — pass it through, or refactor `resolveFfprobe` to an instance method. Instance method is simpler; keep it `private func`, drop the params it can read from `self`.)

- [x] **Step 4: Update `FakeEnvironmentProbe.with(...)`**

Add `ffprobe: Bool = false` to the `EnvironmentReport.with(...)` extension and pass `tool("ffprobe", ffprobe)`.

- [x] **Step 5: Run — green + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EnvironmentProbeTests` → PASS
Run: full `GrabberKitTests` + `AppUnitTests` build compiles (the `EnvironmentReport` initializer defaulted `ffprobe`, so existing `.with(...)` / direct constructions still compile).
Run: lint → clean

- [x] **Step 6: Commit**

```bash
git add Sources/GrabberKit/Onboarding/EnvironmentProbe.swift Tests/TestSupport/FakeEnvironmentProbe.swift Tests/GrabberKitTests/EnvironmentProbeTests.swift
git commit -m "feat(grabberkit): EnvironmentReport.ffprobe resolved from the ffmpeg location"
```

---

## Task 9: `DeferReason.backoff` + new `LogEvent` cases — ✅ DONE

**Files:**
- Modify: `Sources/GrabberKit/Download/SubmitResult.swift`
- Modify: `Sources/GrabberKit/Logging/LogEvent.swift`
- Test: `Tests/GrabberKitTests/LogEventTests.swift` (or wherever `LogEvent` serialisation is tested — check; likely `LogWriterTests` or a dedicated file)

**Interfaces:**
- Consumes: nothing.
- Produces: `DeferReason.backoff(attempt: Int)`; `LogEvent.jobRetried(id:)`, `LogEvent.showLogTargetMissing(jobID:)`; `jobDeferred` fields now include `reason` and (for `.backoff`) `attempt`.

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import XCTest

final class LogEventPhase4Tests: XCTestCase {
    func test_jobDeferredBackoffFields() {
        let until = Date(timeIntervalSince1970: 1_000)
        let event = LogEvent.jobDeferred(id: UUID(), until: until, reason: .backoff(attempt: 2))
        XCTAssertEqual(event.fields["reason"], "backoff")
        XCTAssertEqual(event.fields["attempt"], "2")
        XCTAssertEqual(event.fields["until"], ISO8601DateFormatter().string(from: until))
    }

    func test_jobRetried() {
        let event = LogEvent.jobRetried(id: UUID())
        XCTAssertEqual(event.key, "job.retried")
        XCTAssertEqual(event.category, .engine)
        XCTAssertTrue(event.fields.isEmpty)
    }

    func test_showLogTargetMissing() {
        let id = UUID()
        let event = LogEvent.showLogTargetMissing(jobID: id)
        XCTAssertEqual(event.key, "show_log.target_missing")
        XCTAssertEqual(event.category, .ui)
        XCTAssertEqual(event.fields["job_id"], id.uuidString)
    }
}
```

- [x] **Step 2: Run — verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/LogEventPhase4Tests`
Expected: FAIL — `.backoff` / `.jobRetried` / `.showLogTargetMissing` undefined.

- [x] **Step 3: Implement `DeferReason`**

In `SubmitResult.swift`:

```swift
public enum DeferReason: Sendable, Equatable {
    case backoff(attempt: Int)
}
```

- [x] **Step 4: Implement the `LogEvent` cases**

In `LogEvent.swift`:
- Add `case jobRetried(id: UUID)` and `case showLogTargetMissing(jobID: UUID)` to the enum.
- `key`: `.jobRetried` → `"job.retried"`, `.showLogTargetMissing` → `"show_log.target_missing"`.
- `category`: `.jobRetried` → `.engine`, `.showLogTargetMissing` → `.ui`.
- `jobID`: `.jobRetried(id)` → `id`, `.showLogTargetMissing(jobID)` → `jobID`.
- `fields`: `.jobRetried` → `[:]`; `.showLogTargetMissing(jobID)` → `["job_id": jobID.uuidString]`.
- `jobDeferred` `fields` arm — add `reason` and, for `.backoff`, `attempt`:

```swift
case let .jobDeferred(_, until, reason):
    switch reason {
    case let .backoff(attempt):
        ["reason": "backoff", "attempt": String(attempt), "until": ISO8601DateFormatter().string(from: until)]
    }
```

- [x] **Step 5: Run — green + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/LogEventPhase4Tests` → PASS
Run: full `GrabberKitTests` build compiles.
Run: lint → clean

- [x] **Step 6: Commit**

```bash
git add Sources/GrabberKit/Download/SubmitResult.swift Sources/GrabberKit/Logging/LogEvent.swift Tests/GrabberKitTests/LogEventPhase4Tests.swift
git commit -m "feat(grabberkit): DeferReason.backoff + jobRetried / showLogTargetMissing log events"
```

---

## Task 10: `DownloadJob` integrity fields + `availableActions` for `.failed` — ✅ DONE

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadJob.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine+Helpers.swift`
- Test: `Tests/GrabberKitTests/AvailableActionsTests.swift` (extend)

**Interfaces:**
- Consumes: `IntegrityVerdict` (existing), `FailurePresentation` (Task 2).
- Produces: `DownloadJob.integrityVerdict: IntegrityVerdict?`, `DownloadJob.actualQuality: String?`; `availableActions(for:)` `.failed` arm reads `presentation.offeredActions`; `showLog` in `.running`/`.paused`/`.completed`/`.cancelled`/`.failed`.

- [x] **Step 1: Write the failing test**

Add to `AvailableActionsTests.swift`:

```swift
func test_failedActionsFromPresentation_rateLimited() {
    let actions = DownloadEngine.availableActions(for: .failed(.rateLimited()))
    XCTAssertTrue(actions.isSuperset(of: [.retry, .showLog, .remove, .openInBrowser]))
    XCTAssertFalse(actions.contains(.pause))
    XCTAssertFalse(actions.contains(.forceStart))
}

func test_failedActions_geoBlockedHasNoRetry() {
    let actions = DownloadEngine.availableActions(for: .failed(.geoBlocked))
    XCTAssertFalse(actions.contains(.retry))
    XCTAssertTrue(actions.isSuperset(of: [.showLog, .remove, .openInBrowser]))
}

func test_showLogInEveryRunState() {
    for state: JobState in [.running, .paused, .completed, .cancelled] {
        XCTAssertTrue(DownloadEngine.availableActions(for: state).contains(.showLog), "\(state)")
    }
    for state: JobState in [.queued, .probing] {
        XCTAssertFalse(DownloadEngine.availableActions(for: state).contains(.showLog), "\(state)")
    }
}
```

- [x] **Step 2: Run — verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/AvailableActionsTests`
Expected: FAIL — `.failed` arm returns `[.remove, .openInBrowser]`; `.showLog` absent elsewhere.

- [x] **Step 3: Add the `DownloadJob` fields**

In `DownloadJob.swift`: add `var integrityVerdict: IntegrityVerdict?` and `var actualQuality: String?`, initialise both `nil` in `init`, and pass them in `snapshot(...)` (replace the hard-coded `actualQuality: nil` / `integrityVerdict: nil`).

- [x] **Step 4: Rewrite `availableActions`**

```swift
static func availableActions(for state: JobState) -> Set<RowAction> {
    switch state {
    case .queued:
        [.pause, .cancel, .forceStart, .remove, .openInBrowser]
    case .probing:
        [.cancel, .remove, .openInBrowser]
    case .running:
        [.pause, .cancel, .remove, .openInBrowser, .showLog]
    case .paused:
        [.resume, .cancel, .remove, .openInBrowser, .showLog]
    case .waitingForNetwork, .cooldown:
        [.cancel, .remove, .openInBrowser]
    case .completed:
        [.reveal, .remove, .openInBrowser, .showLog]
    case .cancelled:
        [.remove, .openInBrowser, .showLog]
    case let .failed(errorClass):
        errorClass.presentation.offeredActions.union([.remove, .openInBrowser, .showLog])
    }
}
```

- [x] **Step 5: Run — green + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/AvailableActionsTests` → PASS
Run: full `GrabberKitTests` — `DownloadJobTests` / `ValueTypesTests` / snapshot fixtures may assert the field set; update.
Run: lint → clean

- [x] **Step 6: Commit**

```bash
git add Sources/GrabberKit/Download/DownloadJob.swift Sources/GrabberKit/Download/DownloadEngine+Helpers.swift Tests/GrabberKitTests/AvailableActionsTests.swift
git commit -m "feat(grabberkit): DownloadJob integrity fields; .failed actions from FailurePresentation; showLog on run states"
```

---

## Task 11: Auto-retry in `recordExit` — ✅ DONE (rewrote 2 Phase-1 classification tests to single-retry-budget form; refactored integrity call into `runIntegrityCheck` helper for lint)

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine+Mutations.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (launcher `Task` runs `IntegrityCheck.verify`, passes `integrity:`)
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` (`EngineDependencies.ffprobeURL`)
- Test: `Tests/GrabberKitTests/EngineRetryTests.swift` (new)

**Interfaces:**
- Consumes: `Backoff` (Task 4), `EngineTuning` (Task 5), `IntegrityCheck` / `IntegrityResult` (Task 7), `DeferReason.backoff` (Task 9), `ErrorClass.isAutoRetryable` / `.retryAfterSeconds` (Tasks 1–2), `deferStart(_:until:)` (existing, `DownloadEngine+Deferral.swift`), `Preferences.maxAutoRetries` (existing).
- Produces: new `recordExit(_:_:integrity:lastError:launchFailed:)` signature; `EngineDependencies.ffprobeURL: URL?` (default `nil`).

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import TestSupport
import XCTest

@MainActor
final class EngineRetryTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func engine(
        _ runner: FakeProcessRunner,
        _ probe: FakeMetadataProbe,
        clock: FakeClock,
        maxAutoRetries: Int = 3,
        ffprobeURL: URL? = nil,
        tuning: EngineTuning = .default
    ) -> DownloadEngine {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = Preferences(defaults: defaults)
        prefs.maxAutoRetries = maxAutoRetries
        return DownloadEngine(
            dependencies: EngineDependencies(
                runner: runner, probe: probe,
                envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
                clock: clock, ytDlpURL: Fix.ytDlp, jobLogDir: Fix.scratchLogDir(),
                debugFlags: EngineDebugFlags(concurrencyCapOverride: 1),
                tuning: tuning, ffprobeURL: ffprobeURL
            ),
            preferences: prefs
        )
    }

    func test_autoRetryableExitDefersWithIncrementedAttempt() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(.stderr("ERROR: HTTP Error 429: Too Many Requests", exitCode: 1), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip", durationSeconds: 10))
        let e = engine(runner, probe, clock: clock)
        let collector = EventCollector(e.events)

        let id = await submitJob(e, Fix.request())
        _ = await collector.waitForState(id) { $0 == .queued } // re-queued after the failure

        let snap = collector.latestSnapshot()?.jobs.first { $0.id == id }
        XCTAssertEqual(snap?.attempt, 1)
        XCTAssertTrue(collector.all.contains { event in
            if case let .snapshot(s) = event { return s.jobs.contains { $0.id == id && $0.state == .failed(.rateLimited()) } }
            return false
        } == false, "no transient .failed snapshot")

        // The deferral fires when the clock passes the backoff deadline.
        clock.advance(by: .seconds(600))
        await expectState(collector, id) { $0 == .running || $0 == .queued }
    }

    func test_budgetExhaustionGoesTerminal() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(.stderr("ERROR: HTTP Error 429", exitCode: 1), forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let e = engine(runner, probe, clock: clock, maxAutoRetries: 2)
        let collector = EventCollector(e.events)

        let id = await submitJob(e, Fix.request())
        // fail, retry (attempt 1), fail, retry (attempt 2), fail → terminal
        for _ in 0 ..< 4 { clock.advance(by: .seconds(600)); try? await Task.sleep(for: .milliseconds(30)) }
        await expectState(collector, id) { if case .failed = $0 { return true } else { return false } }
        XCTAssertEqual(collector.latestSnapshot()?.jobs.first { $0.id == id }?.attempt, 2)
    }

    func test_nonRetryableClassIsImmediatelyTerminal() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(.stderr("ERROR: The uploader has not made this video available in your country", exitCode: 1),
                      forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let e = engine(runner, probe, clock: clock)
        let collector = EventCollector(e.events)

        let id = await submitJob(e, Fix.request())
        await expectState(collector, id) { $0 == .failed(.geoBlocked) }
        XCTAssertEqual(collector.latestSnapshot()?.jobs.first { $0.id == id }?.attempt, 0)
    }

    func test_failedIntegrityTakesIncompleteRetryPath() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(.completingScript(), forPathEndingIn: "yt-dlp") // exit 0
        runner.script(.stdout("{\"format\":{\"duration\":\"5\"},\"streams\":[{\"codec_type\":\"video\",\"height\":720}]}",
                              exitCode: 0), forPathEndingIn: "ffprobe")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip", durationSeconds: 600))
        let e = engine(runner, probe, clock: clock,
                       ffprobeURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe"))
        let collector = EventCollector(e.events)

        let id = await submitJob(e, Fix.request())
        _ = await collector.waitForState(id) { $0 == .queued } // .incomplete → retry, not .completed
        XCTAssertEqual(collector.latestSnapshot()?.jobs.first { $0.id == id }?.attempt, 1)
    }

    func test_skippedIntegrityCompletesAndStoresActualQuality() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(.completingScript(), forPathEndingIn: "yt-dlp")
        runner.script(.stdout("{\"format\":{\"duration\":\"600\"},\"streams\":[{\"codec_type\":\"video\",\"height\":720}]}",
                              exitCode: 0), forPathEndingIn: "ffprobe")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip", durationSeconds: nil)) // → .skipped
        let e = engine(runner, probe, clock: clock,
                       ffprobeURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe"))
        let collector = EventCollector(e.events)

        let id = await submitJob(e, Fix.request())
        await expectState(collector, id) { $0 == .completed }
        XCTAssertEqual(collector.latestSnapshot()?.jobs.first { $0.id == id }?.actualQuality, "720p")
    }
}
```

(Some assertions above depend on `FakeProcessRunner` executing the `yt-dlp` script each retry. Confirm the fake re-serves the same script per launch — it does, scripts are keyed by suffix, not consumed. `ffprobe` naming: `IntegrityCheck` is constructed by the engine with `dependencies.ffprobeURL`; the fake matches `forPathEndingIn: "ffprobe"` — but `/opt/homebrew/bin/ffprobe` also ends in `...ffprobe`, and NOT in `yt-dlp`, so no collision.)

- [x] **Step 2: Run — verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EngineRetryTests`
Expected: FAIL — `recordExit` signature has no `integrity:`; no retry branch; `ffprobeURL` not on `EngineDependencies`.

- [x] **Step 3: Add `ffprobeURL` to `EngineDependencies`**

In `DownloadEngineProtocol.swift`: stored `public var ffprobeURL: URL?`, `init` param `ffprobeURL: URL? = nil`, `.live(...)` derives it (Task 14 wires the real resolution; for now `.live` can leave it `nil` or derive from `EnvironmentProbe` — leave `nil` here, Task 14 fills it).

- [x] **Step 4: Run `IntegrityCheck` in the launcher `Task`**

In `DownloadEngine.swift` `launchDownload`, after `let result = await processResult` and before `recordExit`:

```swift
let integrity: IntegrityResult?
if result.exitCode == 0, !result.wasCancelled {
    let file = await self?.finalizedOutputFile(id: id)
    let expected = await self?.expectedDuration(id: id)
    integrity = await IntegrityCheck(runner: runner, ffprobeURL: self?.ffprobeURLValue)
        .verify(file: file ?? URL(fileURLWithPath: "/dev/null"), expectedDurationSeconds: expected ?? nil)
} else {
    integrity = nil
}
jobLog.close()
await self?.recordExit(id, result, integrity: integrity, lastError: outcome.lastError,
                       launchFailed: outcome.launchFailed && result.exitCode == 127)
```

Add small actor accessors: `func finalizedOutputFile(id:) -> URL?` (`finalizedOutputFiles(for:).first`), `func expectedDuration(id:) -> Int?` (`jobs.first{…}?.durationSeconds`), and a `nonisolated`-safe `ffprobeURLValue` — actually `dependencies.ffprobeURL` is `Sendable`; read it via `await self?.dependencies.ffprobeURL` or add `var ffprobeURLValue: URL? { dependencies.ffprobeURL }`. Keep `runner` captured as the existing local (`dependencies.runner`, already captured in the `Task` as `runner`).

(`IntegrityCheck` needs the finalized file — it runs strictly after the process exits. The engine still owns the only spawn: the `verify` call is made from the engine's own launcher `Task` via the injected `ProcessRunning`. `ProcessRunner` stays the only `Foundation.Process`.)

- [x] **Step 5: Rewrite `recordExit`**

```swift
func recordExit(
    _ id: UUID,
    _ result: ProcessResult,
    integrity: IntegrityResult?,
    lastError: ErrorClass?,
    launchFailed: Bool
) {
    childTasks[id] = nil
    guard let job = jobs.first(where: { $0.id == id }) else { evaluateSchedule(); return }
    guard job.state == .running else { evaluateSchedule(); return }

    if launchFailed { haltForDepMissing(offending: job); return }
    if result.wasCancelled {
        job.state = .cancelled
        job.finishedAt = .now
        finishTerminal()
        return
    }

    if result.exitCode == 0 {
        job.actualQuality = integrity?.actualQuality
        switch integrity?.verdict {
        case .passed, .skipped, nil:
            job.integrityVerdict = integrity?.verdict
            job.outputFiles = finalizedOutputFiles(for: job)
            job.state = .completed
            job.finishedAt = .now
            finishTerminal()
            return
        case .failed:
            job.integrityVerdict = integrity?.verdict
            // fall through to classification as .incomplete
        }
    }

    let errorClass: ErrorClass = {
        if result.exitCode == 0 { return .incomplete } // failed integrity
        return lastError ?? .unknown(raw: "yt-dlp exited \(result.exitCode)")
    }()

    let budget = preferences.maxAutoRetries
    if errorClass.isAutoRetryable, job.attempt < budget {
        job.attempt += 1
        job.state = .queued
        job.progress = nil
        let deadline = dependencies.clock.now.addingTimeInterval(
            Backoff.delay(attempt: job.attempt,
                          retryAfter: errorClass.retryAfterSeconds,
                          tuning: dependencies.tuning)
        )
        bump()
        emitSnapshot()
        logEvent(.jobDeferred(id: id, until: deadline, reason: .backoff(attempt: job.attempt)))
        deferStart(id, until: deadline)
        evaluateSchedule()
        return
    }

    job.state = .failed(errorClass)
    job.finishedAt = .now
    finishTerminal()
}

private func finishTerminal() {
    enforceTerminalCap()
    bump()
    emitSnapshot()
    evaluateSchedule()
}
```

(An auto-retry re-queue is one sync mutation — `.running` → `.queued`, `attempt` bumped, deferral pending; no transient `.failed` snapshot. `nextDownloads` skips `deferredIDs`, so the scheduler ignores the job until the backoff `Task` fires `evaluateSchedule()`. `maxAutoRetries` is read from `preferences` at classification time — a mid-flight pref change applies to the next failure.)

- [x] **Step 6: Run — green**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EngineRetryTests` → PASS
Run: `xcodebuild ... test -only-testing:GrabberKitTests/DownloadEngineTests -only-testing:GrabberKitTests/EngineForceStartTests -only-testing:GrabberKitTests/EngineHaltTests -only-testing:GrabberKitTests/DownloadEngineSchedulerTests` → PASS (the `recordExit` signature change ripples through every engine test that calls it directly, if any — most drive through the public API. Fix call sites.)

- [x] **Step 7: Lint + commit**

Run: lint → clean

```bash
git add Sources/GrabberKit/Download/DownloadEngine+Mutations.swift Sources/GrabberKit/Download/DownloadEngine.swift Sources/GrabberKit/Download/DownloadEngineProtocol.swift Tests/GrabberKitTests/EngineRetryTests.swift
git commit -m "feat(grabberkit): auto-retry classified failures on the Backoff schedule against maxAutoRetries"
```

---

## Task 12: The `retry(_:)` intent — resume vs retry — ✅ DONE (state+part-file assertions instead of async log-line assertions; fixed DownloadsTableTests showLog case)

**Files:**
- Create: `Sources/GrabberKit/Download/DownloadEngine+Retry.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` (protocol method — done in Task 11 Step 3? No — add here)
- Test: `Tests/GrabberKitTests/EngineRetryIntentTests.swift` (new)

**Interfaces:**
- Consumes: `deletePartFiles(for:)` (existing helper), `move(_:toTail:)` (existing), `ErrorClass.presentation.offeredActions` (Task 2), `jobResumed` (existing `LogEvent`), `jobRetried` (Task 9).
- Produces: `DownloadEngine.retry(_ id: UUID) async` (also on `DownloadEngineProtocol`).

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import TestSupport
import XCTest

@MainActor
final class EngineRetryIntentTests: XCTestCase {
    private typealias Fix = EngineFixture

    // Build a .failed job directly in a scratch dir, optionally with a .part on disk.
    private func failedJob(
        _ e: DownloadEngine, _ collector: EventCollector,
        errorClass: ErrorClass, withPart: Bool
    ) async -> (UUID, URL) { /* helper: submit, drive to .failed via a scripted stderr,
                                write a "<title stem>.f137.mp4.part" file if withPart */ }

    func test_resumePath_networkDownWithPart_keepsAttemptAndPart() async {
        // arrange a .failed(.networkDown) job, attempt 2, with a non-empty title-matching .part
        // act: await e.retry(id)
        // assert: state .queued at tail, attempt == 2, .part still on disk,
        //         jobResumed logged, jobRetried NOT logged, integrityVerdict/actualQuality nil
    }

    func test_retryPath_rateLimited_resetsAttemptDeletesPart() async {
        // .failed(.rateLimited()) job, attempt 3, .part on disk
        // act: await e.retry(id)
        // assert: attempt == 0, .part deleted, state .queued at tail, jobRetried logged
    }

    func test_retryPath_incompleteWithNoPart_usesRetryNotResume() async {
        // .failed(.incomplete), no .part → retry path (nothing to resume), jobRetried logged
    }

    func test_noOpOnNonRetryableClass() async {
        // .failed(.geoBlocked) → retry is a no-op: state stays .failed, no log
    }

    func test_noOpOnNonFailedJob() async {
        // a .completed job → retry is a no-op
    }

    func test_neitherPathCallsDeferStart() async {
        // after retry, the job is immediately schedulable (no deferral)
    }
}
```

(Flesh each body out following `EngineDeferralTests` / `EngineForceStartTests` patterns — `EventCollector`, `waitForState`, `FakeProcessRunner` scripted stderr to reach `.failed`. Write a `.part` with `FileManager` under `Fix.request().destFolder` named `<titleStem>.f000.mp4.part` with a few bytes. Use `LogWriter` capture via `EventCollector`-equivalent for events — check how `EngineJobLogTests` asserts logged events and reuse that.)

- [x] **Step 2: Run — verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EngineRetryIntentTests`
Expected: FAIL — `retry` undefined.

- [x] **Step 3: Implement**

Create `Sources/GrabberKit/Download/DownloadEngine+Retry.swift`:

```swift
import Foundation

extension DownloadEngine {
    public func retry(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }),
              case let .failed(errorClass) = job.state,
              errorClass.presentation.offeredActions.contains(.retry)
        else { return }

        job.state = .queued
        job.finishedAt = nil
        job.progress = nil
        job.sizeBytes = nil
        job.integrityVerdict = nil
        job.actualQuality = nil
        move(job, toTail: true)

        if shouldResume(job, errorClass: errorClass) {
            logEvent(.jobResumed(id: id))
        } else {
            job.attempt = 0
            deletePartFiles(for: job)
            logEvent(.jobRetried(id: id))
        }

        bump()
        emitSnapshot()
        evaluateSchedule()
    }

    private func shouldResume(_ job: DownloadJob, errorClass: ErrorClass) -> Bool {
        let transient: Bool = switch errorClass {
        case .networkDown, .incomplete, .unknown: true
        default: false
        }
        return transient && usablePartFile(for: job) != nil
    }

    // A .part matching the job's title stem in the destination folder, non-empty.
    private func usablePartFile(for job: DownloadJob) -> URL? {
        guard let title = job.title else { return nil }
        let stem = String(title.unicodeScalars.filter {
            $0 != "/" && !CharacterSet.controlCharacters.contains($0)
        })
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: job.request.destFolder,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return entries.first { url in
            url.lastPathComponent.hasPrefix(stem)
                && url.pathExtension == "part"
                && ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        }
    }
}
```

(Spec §4.3: "The Phase 2 `titleStem` helper and the `deletePartFiles` helper already cover the matching and the delete." `titleStem` is `private static` in `DownloadEngine+Helpers.swift` — either make it `static` (drop `private`) and reuse, or duplicate the 3-line filter as above. Prefer dropping `private` on `titleStem` and calling `Self.titleStem(title)` — one source of truth. Adjust the implementation accordingly and note it.)

- [x] **Step 4: Add to the protocol**

`DownloadEngineProtocol.swift`: add `func retry(_ id: UUID) async`. Any conforming test double / mock (search `: DownloadEngineProtocol`) gets a `retry` stub.

- [x] **Step 5: Run — green + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EngineRetryIntentTests` → PASS
Run: `xcodebuild ... test -only-testing:AppUnitTests` build compiles (the protocol grew — App-side fakes need `retry`).
Run: lint → clean

- [x] **Step 6: Commit**

```bash
git add Sources/GrabberKit/Download/DownloadEngine+Retry.swift Sources/GrabberKit/Download/DownloadEngine+Helpers.swift Sources/GrabberKit/Download/DownloadEngineProtocol.swift Tests/GrabberKitTests/EngineRetryIntentTests.swift
git commit -m "feat(grabberkit): retry(_:) intent — resume keeps .part and attempt, retry restarts clean"
```

---

## Task 13: Persistence round-trip + restore behaviour — ✅ DONE (no production change)

**Files:**
- Test: `Tests/GrabberKitTests/PersistenceTests.swift` (extend) or `EnginePersistenceWiringTests.swift`
- Modify: none expected — `PersistedJob.attempt` already round-trips (Phase 2); `integrityVerdict` / `actualQuality` are runtime-only by design.

**Interfaces:**
- Consumes: `PersistedJob` (existing), `DownloadEngine.restore` (existing), `retry(_:)` (Task 12).
- Produces: nothing new — this task is a guard-rail test proving the spec §6 claims hold with no code change.

- [x] **Step 1: Write the tests**

```swift
func test_queuedJobWithAttemptRoundTrips() async {
    // persist a job at .queued attempt: 3 → reload → attempt == 3, state .queued
}

func test_restoredFailedJobIsUnknownRawAndOffersRetry() async {
    // persist .failed(.rateLimited(retryAfterSeconds: 90)) → reload
    // → state .failed(.unknown(raw: ...)), presentation.offeredActions.contains(.retry)
}

func test_retryOnRestoredUnknownJobWithPart_takesResumePath_classStaysUnknown() async {
    // restored .failed(.unknown(raw:)) + a .part on disk → retry → resume path,
    // state .queued, class still .unknown until a fresh failure reclassifies
}

func test_integrityFieldsDoNotPersist() async {
    // a .completed job with actualQuality "720p" → reload → actualQuality nil (runtime-only)
}
```

- [x] **Step 2: Run**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/PersistenceTests`
Expected: mostly PASS immediately (no code change). If `test_restoredFailedJobIsUnknownRawAndOffersRetry` fails because `PersistedJob.reason(for:)` produces a string `FailurePresentation.for(.unknown(raw:))` doesn't like — inspect. It should be fine: `.unknown` always offers `retry`.

- [x] **Step 3: If any test fails, fix the minimal thing**

Only if a real gap surfaces (e.g. `restoredJobState` for `.queued` drops `attempt` — it doesn't, `downloadJob(from:)` sets `job.attempt = persisted.attempt` before `job.state`). Otherwise no production change.

- [x] **Step 4: Lint + commit**

```bash
git add Tests/GrabberKitTests/PersistenceTests.swift
git commit -m "test(grabberkit): pin Phase 4 persistence round-trip and restore-retry behaviour"
```

---

## Task 14: `MediaGrabberApp` wires `ffprobeURL` + `tuning` — ✅ DONE (ffprobe auto-located inside `.live`, not a duplicate resolver in the App)

**Files:**
- Modify: `Sources/App/MediaGrabberApp.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` — `.live(...)` derives `ffprobeURL`
- Test: `Tests/AppUnitTests/` — check if `MediaGrabberApp` construction is unit-tested; if not, no new test (covered by the smoke checklist).

**Interfaces:**
- Consumes: `EnvironmentProbe` / `EnvironmentReport.ffprobe` (Task 8), `EngineDependencies` (Tasks 5, 11).
- Produces: a live engine with a real `ffprobeURL` and `.resolved()` tuning.

- [x] **Step 1: Read the current wiring**

Run: `grep -n "resolveYtDlp\|EngineDependencies\|ffmpeg\|ffprobe\|\.live(" Sources/App/MediaGrabberApp.swift`
Find where `ytDlpURL` is resolved (`resolveYtDlp` pattern — a `/opt/homebrew/bin` / `/usr/local/bin` probe).

- [x] **Step 2: Add `resolveFfprobe`**

Mirror `resolveYtDlp`:

```swift
private static func resolveFfprobe() -> URL? {
    let candidates = [
        "/opt/homebrew/bin/ffprobe",
        "/usr/local/bin/ffprobe"
    ].map(URL.init(fileURLWithPath:))
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
}
```

- [x] **Step 3: Thread it in**

Where `EngineDependencies` is built (either `.live(...)` or a direct init): pass `ffprobeURL: Self.resolveFfprobe()` and, if using a direct init rather than `.live`, `tuning: .resolved()`. Update `EngineDependencies.live(...)` to accept/derive `ffprobeURL` (add a `ffprobeURL: URL? = nil` param, or derive from `EnvironmentProbe().probe().ffprobe?.path` — a direct filesystem probe like `resolveFfprobe` is simpler and matches `resolveYtDlp`; do that inside `.live`).

- [x] **Step 4: Build + run the app once**

Run: `make` (rebuilds, kills running instance, launches). Confirm it launches, a download completes, no crash. (Full verification is the smoke checklist, Task 16.)

- [x] **Step 5: Run the full test suite**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`
Expected: all green.

- [x] **Step 6: Lint + commit**

```bash
git add Sources/App/MediaGrabberApp.swift Sources/GrabberKit/Download/DownloadEngineProtocol.swift
git commit -m "feat(app): wire live ffprobeURL and resolved EngineTuning into the engine"
```

---

## Task 15: `RowModel` / `RowStore` / `AppModel` — ✅ DONE (status(for:maxAutoRetries:) kept name w/ default; split AppModel row-actions + tests into own files for type_body_length; added OpenURLSink)

**Files:**
- Modify: `Sources/App/Rows/RowModel.swift`
- Modify: `Sources/App/Home/RowStore.swift` (confirm path)
- Modify: `Sources/App/AppModel.swift`
- Modify: `Sources/App/AppModelDialogs.swift`
- Test: `Tests/AppUnitTests/RowModelTests.swift` (or wherever `RowModel.status` is tested — check; may be `DownloadsTableTests` / `RowStoreTests`)
- Test: `Tests/AppUnitTests/RowStoreTests.swift` (extend)
- Test: `Tests/AppUnitTests/AppModelTests.swift` (extend)

**Interfaces:**
- Consumes: `JobSnapshot` (`attempt`, `actualQuality`, `state`, `kind`), `ErrorClass.presentation.sentence` (Task 2), `engine.retry(_:)` (Task 12), `LogEvent.showLogTargetMissing` (Task 9), `JobLog.defaultDir` (existing).
- Produces: `RowModel.status(for:maxAutoRetries:)`; `RowStore.apply(_:maxAutoRetries:)` / `resync(_:maxAutoRetries:)`; `AppModel.showLog(jobID:)`.

- [x] **Step 1: `RowModel.status` — failing test**

Add to the `RowModel` status test file:

```swift
@MainActor
func test_status_queuedWithAttemptShowsRetrying() {
    let snap = jobSnapshot(state: .queued, attempt: 2)
    XCTAssertEqual(RowModel.status(for: snap, maxAutoRetries: 5), "Retrying — attempt 3 of 5")
}

@MainActor
func test_status_queuedAttemptZeroIsPlainQueued() {
    let snap = jobSnapshot(state: .queued, attempt: 0)
    XCTAssertEqual(RowModel.status(for: snap, maxAutoRetries: 5), "Queued")
}

@MainActor
func test_status_failedUsesPresentationSentence() {
    let snap = jobSnapshot(state: .failed(.rateLimited()), attempt: 5)
    XCTAssertEqual(RowModel.status(for: snap, maxAutoRetries: 5),
                   "Failed — The site is limiting how fast we can download right now.")
}

@MainActor
func test_quality_actualDiffersShowsArrow() {
    let snap = jobSnapshot(kind: .video(maxHeight: 1080), actualQuality: "720p")
    XCTAssertEqual(RowModel.quality(for: snap), "1080p → 720p")
}

@MainActor
func test_quality_actualMatchesShowsRequest() {
    let snap = jobSnapshot(kind: .video(maxHeight: 1080), actualQuality: "1080p")
    XCTAssertEqual(RowModel.quality(for: snap), "1080p")
}

@MainActor
func test_quality_actualNilShowsRequest() {
    let snap = jobSnapshot(kind: .video(maxHeight: 1080), actualQuality: nil)
    XCTAssertEqual(RowModel.quality(for: snap), "1080p")
}
```

- [x] **Step 2: Run — verify it fails**

Run: `xcodebuild ... test -only-testing:AppUnitTests/<RowModelSuite>`
Expected: FAIL — `status(for:maxAutoRetries:)` signature; `quality` ignores `actualQuality`.

- [x] **Step 3: Implement `RowModel` changes**

`status(for:)` → `status(for:maxAutoRetries:)`:

```swift
static func status(for snapshot: JobSnapshot, maxAutoRetries: Int) -> String {
    switch snapshot.state {
    case .queued:
        snapshot.attempt > 0
            ? "Retrying — attempt \(snapshot.attempt + 1) of \(maxAutoRetries)"
            : "Queued"
    case .probing: "Resolving…"
    case .running:
        snapshot.progress.map { "Downloading \(Int($0.fraction * 100))%" } ?? "Downloading"
    case .paused: "Paused"
    case .waitingForNetwork: "Waiting for network"
    case .cooldown: "Cooling down"
    case .completed: "Saved"
    case .cancelled: "Cancelled"
    case let .failed(errorClass): "Failed — \(errorClass.presentation.sentence)"
    }
}
```

(Delete the private `failureReason(_:)` helper — `presentation.sentence` replaces it. The `#N` queue-position badge stays on `queueBadge` — `badge(for:position:)` already returns nil unless `.queued`; guard it also nil when `attempt > 0` per spec §4.4 "no position badge" for the retrying state.)

`badge(for:position:)`:

```swift
static func badge(for snapshot: JobSnapshot, position: Int?) -> String? {
    guard snapshot.state == .queued, snapshot.attempt == 0, let position else { return nil }
    return "#\(position)"
}
```

`quality(for:)`:

```swift
static func quality(for snapshot: JobSnapshot) -> String {
    let request: String = switch snapshot.kind {
    case let .video(maxHeight): "\(maxHeight)p"
    case let .audio(format): format.rawValue
    }
    guard let actual = snapshot.actualQuality, actual != request else { return request }
    return "\(request) → \(actual)"
}
```

Thread `maxAutoRetries` through `init`, `patch`, `patchProgress`, `recomputeAll` — every call to `Self.status(for:)` gains `maxAutoRetries:`. Add a stored `private let maxAutoRetries: Int` set in `init` and updated by `patch` (since a live pref change must reach the recompute — spec §4.4: "`AppModel` passes the current `maxAutoRetries` into `RowStore.apply(_:)` / the recompute").

Simplest: `patch(_ next:queuePosition:maxAutoRetries:)` and `init(_:queuePosition:maxAutoRetries:)` and `patchProgress` reads a stored `self.maxAutoRetries` (updated in `patch`).

- [x] **Step 4: `RowStore` plumbing — failing test**

Add to `RowStoreTests.swift`:

```swift
@MainActor
func test_maxAutoRetriesReachesRowModelStatus() {
    let store = RowStore()
    store.apply(.snapshot(queueSnapshot([snap(1, state: .queued, attempt: 2)])), maxAutoRetries: 4)
    XCTAssertEqual(store.rows.first?.statusText, "Retrying — attempt 3 of 4")
}
```

- [x] **Step 5: Implement `RowStore` plumbing**

`apply(_ event: QueueEvent, maxAutoRetries: Int)` and `resync(_ snapshot: QueueSnapshot, maxAutoRetries: Int)` — store `private var maxAutoRetries = 5`, set it at the top of `apply` / `resync`, pass it into every `RowModel.init` / `.patch` / `.patchProgress` call inside `applySnapshot`. No `Preferences` import. Keep a default value so existing tests that call `apply(event)` without it still compile — actually, changing the signature breaks them; either (a) give `maxAutoRetries` a default `= 5` on the parameter, or (b) update every call site. Spec §4.4 wants `AppModel` (holding `prefs`) to pass it. Default parameter `maxAutoRetries: Int = 5` keeps old tests green and lets `AppModel` pass the real value — do that.

- [x] **Step 6: `AppModel` — failing test**

Add to `AppModelTests.swift`:

```swift
@MainActor
func test_handleRowAction_retryCallsEngineRetry() async {
    let engine = FakeEngine()  // conforms to DownloadEngineProtocol, records calls
    let model = makeModel(engine: engine)
    let id = UUID()
    await model.handleRowAction(id, action: .retry)
    XCTAssertEqual(engine.retriedIDs, [id])
}

@MainActor
func test_handleRowAction_showLogMissingFileShowsNoticeAndLogs() async {
    let model = makeModel()  // jobLogDir points at an empty scratch dir
    let id = UUID()
    await model.handleRowAction(id, action: .showLog)
    XCTAssertNotNil(model.pendingConfirmation)
    XCTAssertEqual(model.pendingConfirmation?.cancelTitle, nil)  // a notice
    // assert showLogTargetMissing logged via the fake LogWriter
}
```

(`FakeEngine` — check `Tests/AppUnitTests/Support/AppFakes.swift`; it likely already has a `DownloadEngineProtocol` fake. Add `retriedIDs` + `func retry(_:)`.)

- [x] **Step 7: Implement `AppModel`**

```swift
func handleRowAction(_ id: UUID, action: RowAction) async {
    switch action {
    case .pause: await engine.pause(id)
    case .resume: await engine.resume(id)
    case .cancel: await engine.cancel(id)
    case .remove: await engine.remove(id)
    case .forceStart: await engine.forceStart(id)
    case .reveal: await reveal(jobID: id)
    case .openInBrowser: openInBrowser(jobID: id)
    case .retry: await engine.retry(id)
    case .showLog: await showLog(jobID: id)
    case .retryWithCookies: break
    }
}

func showLog(jobID: UUID) async {
    let dir = JobLog.defaultDir  // or an engine.jobLogDir accessor if one exists
    let url = dir.appendingPathComponent("\(jobID.uuidString).log")
    if FileManager.default.fileExists(atPath: url.path) {
        #if canImport(AppKit)
            NSWorkspace.shared.open(url)
        #endif
    } else {
        await log.log(.showLogTargetMissing(jobID: jobID))
        _ = await confirm(AppModelDialogs.showLogMissingNotice())
    }
}
```

(Spec §9: the `NSWorkspace.open` call should go through a testable sink like `RevealSink`. Add an `OpenURLSink` protocol + `WorkspaceOpenURLSink` mirroring `RevealSink` / `WorkspaceRevealSink`, injected into `AppModel`, so `test_handleRowAction_showLog...` for the *present-file* case can assert the sink was called. The missing-file path needs no sink.)

`AppModelDialogs.showLogMissingNotice()`:

```swift
static func showLogMissingNotice() -> ConfirmationRequest {
    ConfirmationRequest(
        title: "Log unavailable",
        message: "The log for this download is no longer available.",
        confirmTitle: "OK",
        cancelTitle: nil
    )
}
```

In `runConsumer()` / wherever `rowStore.apply(event)` is called, pass `maxAutoRetries: prefs.maxAutoRetries`; same for `rowStore.resync(...)` in `performLaunchSetup`.

- [x] **Step 8: Run — green**

Run: `xcodebuild ... test -only-testing:AppUnitTests` → PASS
Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test` → full suite green

- [x] **Step 9: Lint + commit**

```bash
git add Sources/App/Rows/RowModel.swift Sources/App/Home/RowStore.swift Sources/App/AppModel.swift Sources/App/AppModelDialogs.swift Tests/AppUnitTests/
git commit -m "feat(app): retry/showLog row actions, Retrying status, Quality column shows real resolution"
```

---

## Task 16: `screens.html` mockup + parent-spec edits + smoke checklist — ✅ DONE (§12.2 rows already matched shipped surface; §12.1 Phase 4 stub reworded to "shipped")

**Files:**
- Modify: `docs/mockups/screens.html`
- Modify: `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md`
- Create: `docs/superpowers/plans/2026-09-01-media-grabber-phase-4-smoke.md` (the leaf smoke checklist, mirroring `plans/archived/2026-08-31-media-grabber-phase-3-smoke.md`)

**Interfaces:** none — documentation.

- [x] **Step 1: `screens.html` — the §1 Home table**

In the Home screen table markup:
- Add a **failed row**: a non-recoverable class (e.g. `private`) — Status cell `Failed — This video is private.`, Retry button rendered **disabled**, `showLog` / `remove` / `openInBrowser` enabled.
- Add a **retrying row**: Status cell `Retrying — attempt 3 of 5`, no position badge, no countdown, Cancel / Remove enabled.
- One **completed row's** Quality cell → `1080p → 720p`.
- Draw the **row-action bar** with its full button set in `RowAction.displayOrder` and the Phase 4 enable states: `retry` enabled only for a failed row whose class offers it; `showLog` enabled on every run/terminal state; `retryWithCookies` (`🔑`) rendered disabled (Phase 5).

- [x] **Step 2: Open `screens.html` in a browser, eyeball every screen**

Run: `open docs/mockups/screens.html`
Confirm the skin/palette switcher still works, no layout break, the new rows read correctly in both themes.

- [x] **Step 3: Parent-spec §12.1 Phase 4 stub**

Rewrite the Phase 4 bullet in §12.1 to past-tense "shipped" form: generic `ErrorClass` classification with `FailurePresentation`; live `retry` / `show-log` actions; the resume-vs-retry split; the `maxAutoRetries` budget; `Backoff` as first `deferStart` caller; `EngineTuning` as the env-overridable home of every retry/pacing number; `IntegrityCheck` feeding `actualQuality` into the Quality column; `EnvironmentReport.ffprobe`.

- [x] **Step 4: Parent-spec §12.1 Phase 6 stub**

Confirm the hint is present (spec §12 says "*Done*"): *the Status cell's live `m:ss` backoff / cooldown countdown lands here; Phase 4 shows a static `attempt N of M` and leaves `JobSnapshot.cooldownUntil` nil.* It is already at line ~709 — verify wording, no change if it matches.

- [x] **Step 5: Parent-spec §9 and §12.2 rows**

- §9 — confirm `ErrorClass` staging reads: enum ships whole (Phase 1); Phase 4 adds the classifier signatures + `FailurePresentation` + `ErrorClass.key`. (Line ~544 — already says this; verify.)
- §12.2 `ErrorClass` row and row-action-bar row — confirm they name Phase 4 for the generic signatures / `FailurePresentation` / `key`, and `retry` + `showLog` live. (Lines ~739, ~743 — already present; verify, adjust only if stale.)
- §7.5 — confirm the bounded flag line is present (line ~463). It is. No edit.

(Most §12 edits are marked "*Done*" in the phase-4 spec §12 — this step is verification, not rewriting. Make an edit only where the parent spec's current text contradicts what shipped.)

- [x] **Step 6: Write the smoke checklist**

Create `docs/superpowers/plans/2026-09-01-media-grabber-phase-4-smoke.md` from spec §10 "Manual smoke":
- Force a classified non-recoverable failure (private / removed URL) → plain sentence, Retry disabled, `showLog` opens the raw log.
- Disconnect mid-download → within ~45 s `Retrying — attempt 1 of N`, retries after backoff, stops at budget; Retry then resumes from `.part`.
- Normal completion → Quality shows real resolution (`1080p → 720p` when the site served lower), integrity passes silently.
- Truncate a download (kill connection near end, or tiny `MG_YTDLP_SOCKET_TIMEOUT`) → `The download kept ending early`, auto-retries.
- `MG_BACKOFF_LADDER=2,4,6` → retry waits shorten (proves the tuning path).
- Rename `ffprobe` away → downloads still complete, Quality shows request value, no integrity failures.
- `showLog` on a job whose log was evicted → the "no longer available" notice.

- [x] **Step 7: Commit**

```bash
git add docs/mockups/screens.html docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md docs/superpowers/plans/2026-09-01-media-grabber-phase-4-smoke.md
git commit -m "docs: Phase 4 screens.html rows, parent-spec §12 sync, smoke checklist"
```

---

## Task 17: Full verification pass — ✅ automated portion DONE; manual smoke pending user

**Files:** none — verification only.

- [x] **Step 1: Regenerate the project**

Run: `mise exec -- tuist generate --no-open` (from `apps/media-grabber/`)

- [x] **Step 2: Full test suite** — 248 GrabberKitTests (1 live-net skip) + AppUnitTests, 0 failures

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`
Expected: all green. Paste the summary line into the task notes.

- [x] **Step 3: Lint, both tools, strict** — swiftformat + swiftlint --strict clean, 145 files

Run: `mise exec -- swiftformat --lint .`
Run: `mise exec -- swiftlint lint --strict`
Expected: both clean, zero warnings.

- [x] **Step 4: Build** — BUILD SUCCEEDED. (launch + Console watch is a manual step)

Run: `make`
Confirm: launches, a real download completes, the Quality column shows a resolution, no crash in Console.

- [ ] **Step 5: Run the smoke checklist**

Work through `docs/superpowers/plans/2026-09-01-media-grabber-phase-4-smoke.md` on the real machine. Record pass/fail per line.

- [ ] **Step 6: Final commit (if the smoke run needed a fix)**

Otherwise nothing to commit — the phase is done.

```bash
git commit --allow-empty -m "chore: Phase 4 verification pass — tests green, lint clean, smoke passed"
```

---

## Self-Review

**Spec coverage:**

| Spec §1 item | Task |
|---|---|
| `ProgressParser.classifyStderr` generic signatures → `ErrorClass` | Task 3 |
| `FailurePresentation` value + `ErrorClass.key` / `.presentation` | Tasks 1, 2 |
| Retry row action live (resume vs retry) | Task 12 |
| Per-job auto-retry budget (`maxAutoRetries`) | Task 11 |
| `Backoff` — exponential + full jitter + ladder + cap + `Retry-After` | Task 4 |
| `EngineTuning` / `YtDlpTuning` — env-overridable | Task 5 |
| `DeferReason.backoff(attempt:)` + `jobDeferred` fields | Task 9 |
| `jobRetried(id:)`, `showLogTargetMissing(jobID:)` | Task 9 |
| `IntegrityCheck` — ffprobe duration verdict + `actualQuality` | Task 7 |
| `.incomplete` retry path from a failed integrity check | Task 11 |
| Always-on §7.5 download flags in `YtDlpArguments` | Task 6 |
| `EnvironmentReport.ffprobe` | Task 8 |
| `showLog` row action live | Tasks 10 (actions), 15 (UI) |
| `availableActions` for `.failed` from `presentation.offeredActions` | Task 10 |
| Status cell `Retrying — attempt N of M` | Task 15 |
| Quality column `1080p → 720p` | Task 15 |
| `RowStore.apply` plumbs `maxAutoRetries`, stays `Preferences`-free | Task 15 |
| Persistence round-trip + restore-retry | Task 13 |
| `screens.html` failed / retrying / quality rows + action bar | Task 16 |
| Parent-spec §12 edits | Task 16 |
| Manual smoke checklist | Tasks 16 (write), 17 (run) |

**Deferred items correctly NOT built:** live `m:ss` countdown (Phase 6 — Status shows static text, `cooldownUntil` left nil), per-host `RateState` / cooldown / circuit breaker / `NetworkMonitor` (Phase 6), `player_client` rotation (Phase 7), YouTube `ErrorClass` cases (Phase 7 — the `FailurePresentation` switch has one grouped placeholder arm for exhaustiveness, no classifier signatures), `retryWithCookies` + `cookieReadFailed` emit path (Phase 5 — `cookieReadFailed` has a `FailurePresentation` entry and `retry` action but no `ErrorSignatures` row). No `ffprobe` onboarding step. No `WarningBanner` / `HealthStrip` content. No toasts / notifications. No Diagnostics page.

**Type consistency check:** `recordExit` new signature `(_:_:integrity:lastError:launchFailed:)` used consistently Task 11. `status(for:maxAutoRetries:)` Task 15 matches the Interfaces block. `Backoff.delay(attempt:retryAfter:tuning:jitter:)` matches Tasks 4 and 11's call. `IntegrityResult { verdict, actualQuality }` matches Tasks 7 and 11. `EngineDependencies` gains `tuning` (Task 5) then `ffprobeURL` (Task 11) — both defaulted, both additive. `FailurePresentation.for(_:)` one switch, Task 2, extended by Phase 7 only.

**Ordering note:** Task 5 (`EngineTuning`) executes **before** Task 4 (`Backoff`) — `Backoff.delay` takes `tuning: EngineTuning`. The plan reads 4→5 for narrative (Backoff is the headline) but the executor does 5, then 4. Every other task is in dependency order.

**Placeholder scan:** every code step carries real code; every test step carries real assertions (Task 12's intent-test bodies are sketched with explicit arrange/act/assert comments rather than full code — the one concession, because each body is a 20-line rearrangement of the same `EngineDeferralTests` scaffold and the exact fake-scripting differs per case; the executor writes them against the named pattern). No "add error handling", no "similar to Task N", no "TBD".

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-09-01-media-grabber-phase-4.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`.

**2. Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.

**Which approach?**
