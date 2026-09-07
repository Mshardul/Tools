# MediaGrabber Phase 6 — Rate Limiting and Circuit Breaker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MediaGrabber respond to a site rate-limiting it — per-host cooldown ladder, a circuit breaker that halts auto-retry until the user intervenes, adaptive concurrency, and network-drop handling — without rewriting the Phase 2 scheduler.

**Architecture:** A new engine-owned value type `RateLimiter` holds `[RateHost: RateState]`, a global adaptive concurrency cap, and a clean-streak counter; its transition logic is a pure `RatePolicy` enum. The engine consults it on every `evaluateSchedule()` and mutates it on every `recordExit`. The Phase 2 scheduler gains two `Set<UUID>` gate fields and swaps its `cap` input — no loop rewrite. A `NetworkPathMonitoring` protocol (live impl wraps `NWPathMonitor`) drives a `.networkDown` halt and `.waitingForNetwork` job state. The App layer gains a `HealthController` producing the `HealthStrip` chip array, a `BannerReason` priority resolver driving `WarningBanner`, and a `TimelineView`-based countdown in the Status cell.

**Tech Stack:** Swift 6, Tuist, XCTest. Targets: `GrabberKit` (UI-free engine), `MediaGrabber` (SwiftUI app), `TestSupport` (shared fakes), `GrabberKitTests`, `AppUnitTests`.

**Spec:** `docs/superpowers/specs/2026-09-04-media-grabber-phase-6.md` — read it alongside this plan. Every task's "why" is there; this plan is the "how".

## Global Constraints

- **No git.** This plan contains no `git` commands. Each task ends by running lint + tests and handing the changed files to the user. Do not create branches, do not commit, do not stage. The user handles all version control.
- **No phase / ticket / epic numbers anywhere in source or UI copy.** Not in comments, not in log strings, not in SwiftUI `Text`, not in `Info.plist`. The spec and this plan are the only places "Phase 6" appears. User-facing copy for a not-yet-built thing says "coming in a future update", never a phase reference.
- **Comments: single-line only, only the *why*, only when names don't carry it.** No `///` doc comments (`.swiftformat` has `--disable docComments`). No stacked `//` blocks. If the why needs two lines, restructure. Default to zero comments. `// MARK:` is fine.
- **No multi-line comments in any file type** — Swift, TOML, YAML, shell alike.
- **Swift 6 concurrency:** `NSLock` is banned in async contexts (deployment target is macOS 14, `Synchronization.Mutex` needs 15). The `os_unfair_lock`-backed `LockedBox` lives in `Tests/TestSupport/LockedBox.swift` (public, `@unchecked Sendable`, `read` / `mutate`). **`GrabberKit` sources cannot import `TestSupport`** (the dependency runs the other way). Any `GrabberKit` type needing a lock (the live `NWPathNetworkMonitor`) serializes on its own `DispatchQueue` — do NOT try to reuse `LockedBox` there and do NOT promote it into sources. Actors are reentrant across `await` — actor isolation is not a queue. `XCTestCase` is not `Sendable` — build values before a `Task {}` and capture only `Sendable` locals.
- **`@Observable` classes using `URL` / `Foundation` types need an explicit `import Foundation`** — `Observation` does not re-export it.
- **Lint after every task:** `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict` must both pass. Recurring traps and their fixes are in the "Lint traps" section below — apply the fix the first time, do not wait for the linter to catch it.
- **Build after adding/removing files:** `mise exec -- tuist generate --no-open`.
- **Test command:** `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`. Single suite: append `-only-testing:GrabberKitTests/<SuiteName>` or `-only-testing:AppUnitTests/<SuiteName>`. Do NOT use `tuist test` while developing — its output filtering hides compiler errors.
- **Engine tests are not `@MainActor`** — a `@MainActor` test class breaks `expectState`'s closure send. Read job state via `await engine.currentSnapshot()` or the `EventCollector`.
- **All Phase 6 tuning numbers live in `EngineTuning`, env-overridable via `MG_*`, never in the Preferences UI.**
- **Test names carry no phase/ticket number.** Not `testPhase6Defaults`, not `EngineTuningPhase6Tests`. Name them for the behavior: `testRateLimitTuningDefaults`, `EngineTuningRateLimitTests`, `LogEventRateLimitTests`. Sibling files split for `type_body_length` get descriptive names too.
- **The real test harness (do not invent APIs):**
  - Attach a collector: `let collector = EventCollector(engine.events)` — positional init, not `.attach(to:)`.
  - `collector.latestSnapshot()` → `QueueSnapshot?`; `collector.waitForState(id) { state in … }` → `async -> Bool` (5 s timeout); `collector.snapshots` → `[QueueSnapshot]`.
  - Poll helper: `func job(_ collector: EventCollector, _ id: UUID) -> JobSnapshot? { collector.latestSnapshot()?.jobs.first { $0.id == id } }`.
  - Process scripts are **path-keyed, last-write-wins**: `runner.script(.stderr("…", exitCode: 1), forPathEndingIn: "yt-dlp")`. Every launch of `yt-dlp` gets that one script. For "attempt 1 fails, attempt 2 succeeds" you MUST use the ordered-script API added in **Task 0**: `runner.scripts([s1, s2], forPathEndingIn: "yt-dlp")`.
  - `runner.launches` → `[ProcessLaunch]` (all recorded, in order); `ProcessLaunch.arguments` → `[String]`.
  - `FakeMetadataProbe(default:)` defaults to `.failure(.malformedOutput)` — **a job never reaches `recordExit` unless you set a success**: `probe.result(FakeMetadataProbe.success(title: "Clip"))` (or `.success(title:extractor:)`).
  - `FakeClock(now:)` — `clock.advance(by: .seconds(N))` moves time AND resumes any `deferralTask` awaiting `clock.sleep(until:)`, which runs `fireDueDeferrals`. After `advance`, `try? await Task.sleep(for: .milliseconds(20))` to let the continuation propagate. There is no separate "fire deferrals" seam.
  - `EngineFixture.engine(runner:probe:cap:preferences:fileManager:resolverHome:)` builds an engine with `debugFlags.concurrencyCapOverride: cap` (default 3). **Task 11 adds `networkMonitor:` (default a `FakeNetworkMonitor` → `AlwaysOnlineMonitor` chain), `clock: FakeClock?`, `tuning: EngineTuning`, and `maxAutoRetries: Int?` params** — Tasks 12–19 rely on all four. `EngineRetryTests` has its own private `engine(_:_:clock:maxAutoRetries:ffprobeURL:tuning:)` — some suites use one, some the other; match the suite you are editing.
  - `FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true))`.
- All paths below are relative to `apps/media-grabber/`.

## Lint traps (apply the fix pre-emptively)

- `swiftlint cyclomatic_complexity` (limit 10) — a `switch` mixing `case let` with comma-grouped patterns trips it. Fix: split into per-arm helper funcs.
- `swiftlint function_body_length` (limit 50) — fix: hoist sub-expression builds into helpers.
- `swiftformat` collapses a `switch` arm returning a value into an implicit-return ternary, then `swiftlint void_function_in_ternary` rejects it. Fix: give that arm its own `guard`-based helper.
- `swiftlint large_tuple` (limit 2) — a test helper returning a 3+ tuple fails. Fix: a private `struct`.
- `swiftlint type_body_length` (limit 250, strict) — adding ~3 tests to a large XCTestCase trips it. Fix: split into a sibling `<Name>MoreTests.swift`.
- `swiftformat` reformats `for … where <pred> {` onto its own `{` line → `swiftlint opening_brace` rejects. Use `table.first { entry in … }?.field`. Same for a multi-line `if cond, let x`.
- `swiftformat` and `swiftlint` disagree on the `{` placement for a wrapped multi-line `if` condition. Fix: extract the condition into a named predicate function; do not inline a multi-line `||` / `,` condition.

## File Structure

**New — `GrabberKit/RateLimiting/`:**

| File | Responsibility |
|---|---|
| `RateHost.swift` | `struct RateHost` — normalized per-site key + alias table. |
| `RateState.swift` | `enum RateState` (`normal` / `cooldown` / `circuitOpen`) + `HostRateDisplayState`. |
| `RatePolicy.swift` | Pure `enum RatePolicy` — `next(state:event:now:tuning:)`. |
| `RateLimiter.swift` | Engine-owned `struct RateLimiter` — the dict, the adaptive cap, the streak, the public API. |
| `NetworkPathMonitoring.swift` | `protocol NetworkPathMonitoring` + `NWPathNetworkMonitor` live impl (debounced). |
| `CountdownFormat.swift` | `enum CountdownFormat` — `mmss(until:now:)`. Shared by the Status cell and the chip. |

**Modified — `Tests/TestSupport/`:**

| File | Change |
|---|---|
| `FakeProcessRunner.swift` | **Task 0** — ordered-script API: `scripts([Script], forPathEndingIn:)` consumed one per launch, last repeats. |
| `FakeNetworkMonitor.swift` (new) | Manually-toggled `NetworkPathMonitoring` fake. |

**Modified — `GrabberKit/Download/`:**

| File | Change |
|---|---|
| `JobSnapshot.swift` | `JobSnapshot` gains `rateHost: RateHost`; `QueueHaltReason` gains `.networkDown`, `.circuitOpen`; `availableActions` split of the `.cooldown` / `.waitingForNetwork` arm. |
| `QueueEvent.swift` | `QueueSnapshot` gains `hostRateSummary: [RateHost: HostRateDisplayState]` and `isOnline: Bool`. |
| `DownloadJob.swift` | gains `var cooldownUntil: Date?`; `snapshot(availableActions:)` stays one-arg, reads `self.rateHost`-derived + `self.cooldownUntil`. |
| `DownloadEngine.swift` | Holds `var rateLimiter`, `var isOnline`, `networkTask`; `private var effectiveCap: Int { min(rateLimiter.adaptiveCap, cap) }`; `evaluateSchedule()` re-clamps `RateLimiter` from `cap`, builds the two gate sets, uses `effectiveCap`; `setCap` calls `rateLimiter.setPreferencesCap`. |
| `DownloadEngine+Deferral.swift` | `cancelDeferral(_:)`; `fireDueDeferrals` flips a due `.cooldown` job back to `.queued`. |
| `DownloadEngine+Mutations.swift` | `recordExit` split — unconditional strike (terminal too), then host-rate path (one `.cooldown` job per host) vs Phase 4 path; emits `adaptiveConcurrencyChanged` on a cap delta. |
| `DownloadEngine.swift` (`forceStart`) | Accepts a `.cooldown` job; overrides a host block for the one forced job; eviction uses `effectiveCap`. |
| `DownloadEngine+State.swift` | `buildSnapshot` fills `hostRateSummary`, `isOnline`, `effectiveQueueHalt()` (raw hard halts + derived `.circuitOpen`). |
| `DownloadEngine.swift` (`revalidate`) | `if queueHalt == .depMissing { queueHalt = nil }` — only depMissing. Add `resetCircuit(_:)` / `resetAllCircuits()` (own methods, emit `circuitReset`). |
| `DownloadEngineProtocol.swift` | Protocol gains `resetCircuit(_:) async`, `resetAllCircuits() async`; `EngineDependencies` gains `networkMonitor` (default a no-op `AlwaysOnlineMonitor`, live only in `.live`). |
| `DownloadEngine.swift` (`hasActiveJobs`) | Also counts `.cooldown` / `.waitingForNetwork` (pending work — the quit prompt should show). |
| `Scheduler.swift` | `SchedulerInput` gains `blockedHostIDs`, `blockedProbeHostIDs`; `nextDownloads` / `nextProbe` one filter clause each. |
| `YtDlpArguments.swift` | `build` gains `concurrentFragments: Int` (non-defaulted — fix all call sites). |
| `EngineTuning.swift` | Seven new fields (all `init` params **defaulted** so existing 3-arg call sites compile) + `resolved()` parse lines. |
| `Logging/LogEvent.swift` | `DeferReason.hostCooldown`; six new events, keyed via `.key` (not `.name`). |
| `App/QuitCoordinator.swift` | `quitConfirmation(halt:)` arms for `.networkDown` / `.circuitOpen`. |

**Modified — `App/`:**

| File | Change |
|---|---|
| `Chrome/HealthController.swift` (new) | `@Observable HealthController` — `update(snapshot:now:) -> [HealthChip]`. |
| `Chrome/HealthStrip.swift` | `ChipInteraction` gains `.popover(PopoverKind)`; the strip renders interaction (click → popover host). |
| `Chrome/WarningBanner.swift` | `BannerContent.buttonTitle` / `action` optional; banner publishes its height. |
| `Chrome/BannerResolver.swift` (new) | `enum BannerReason` + pure `resolveBanner(_:)` + the priority list + the copy. |
| `SiteNames.swift` (new) | `enum SiteNames { static func display(_ canonical: String) -> String }` — keyed by `RateHost.canonical` (NOT `RowModel.siteMap`, which is keyed by extractor and stays as-is). Used by `HealthController`, `HostRatePopover`, `BannerResolver`. |
| `Chrome/HostRatePopover.swift` (new) | The cooldown-chip popover body, built from `hostRateSummary` + `AppModel` action closures. |
| `AppModel.swift` | Owns `HealthController`; `healthChips` delegates; `private(set) var hostRateSummary`; `bannerContent` from the resolver each snapshot; `resetCircuit(host:)` / `resetAllCircuits()` → engine. |
| `MainWindow.swift` | Captures the banner's measured height; bottom safe-area inset on `page` when a banner shows. |
| `Table/TablePresentation.swift` | `statusDisplay(for:hostRateSummary:)` — the **real** Status-cell text function; new prefixes for cooling / circuit / retrying. |
| `Rows/RowModel.swift` | Learns `rateHost`; stores its last `HostRateDisplayState`; `hostCooldownDeadline` computed. |
| `Rows/RowStore.swift` | Carries `hostRateSummary` off the snapshot into `RowModel` / `statusDisplay` / the status filter value. |
| `Table/DownloadRow.swift` (Status cell) | wraps `statusDisplay` output in `TimelineView` + `CountdownFormat.mmss` when a future deadline exists. |

**Modified tests (existing suites that break — each named in its task):**
- `Tests/GrabberKitTests/AvailableActionsTests.swift` — `test_waitingForNetwork_and_cooldown` (Task 9).
- `Tests/GrabberKitTests/EngineRetryTests.swift` — `test_autoRetryableExitDefersWithIncrementedAttempt` and any 429 test expecting `.queued` (Task 12).
- `Tests/GrabberKitTests/BackoffTests.swift:57` — 3-arg `EngineTuning(` (Task 3 — defaulted params make it compile, but confirm).
- `Tests/GrabberKitTests/SchedulerTests.swift` — `SchedulerInput(` arity (Task 12).
- `Tests/AppUnitTests/Support/AppFakes.swift` — `FakeEngine` gains `resetCircuit` / `resetAllCircuits` no-ops (Task 14).
- `Tests/AppUnitTests/DownloadsTableTests.swift` — `statusDisplay` output for cooldown (Task 19).
- every `JobSnapshot(` / `QueueSnapshot(` / `EngineDependencies(` construction site — Task 8 lists the grep.

**Modified — docs:** `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` (§5.2, §5.6, §7.4, §7.6, §7.8, §12.1, §12.2) and `docs/superpowers/specs/2026-09-04-media-grabber-phase-6.md` (header, §3.2, §4, §6.3, §9 — sync to the plan's signatures — Task 20).

---

## Task 0: `FakeProcessRunner` ordered-script support

The current fake keys scripts by executable path, last-write-wins, so every launch
of `yt-dlp` gets the same script. Phase 6 needs "attempt 1 rate-limited, attempt 2
succeeds" for the cooldown-expiry, force-start, and circuit-reset tests. Add an
ordered-script mode; the existing path-keyed API is untouched.

**Files:**
- Modify: `Tests/TestSupport/FakeProcessRunner.swift`
- Test: `Tests/GrabberKitTests/FakeProcessRunnerTests.swift` (new — the fake is now non-trivial)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `func scripts(_ scripts: [FakeProcessRunner.Script], forPathEndingIn suffix: String)` — the Nth launch matching `suffix` uses `scripts[min(N, scripts.count - 1)]` (the last entry repeats for any further launches)
  - existing `script(_:forPathEndingIn:)` / `script(_:forExactPath:)` unchanged — a single script still applies to every launch
  - resolution order in `run(_:)`: an ordered list for the matched suffix wins over a single script for the same key; exact-path single script still wins over a suffix match (keep the current precedence: exact path, then `lastPathComponent`)

- [x] **Step 1: Write the failing test**

`Tests/GrabberKitTests/FakeProcessRunnerTests.swift`:

```swift
@testable import GrabberKit
import TestSupport
import XCTest

final class FakeProcessRunnerTests: XCTestCase {
    private func launch(_ name: String) -> ProcessLaunch {
        ProcessLaunch(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"), arguments: [])
    }

    private func drain(_ exec: ProcessExecution) async -> ProcessResult {
        for await _ in exec.lines {}
        return await exec.result()
    }

    func testOrderedScriptsAdvancePerLaunch() async {
        let runner = FakeProcessRunner()
        runner.scripts([
            .stderr("ERROR: HTTP Error 429", exitCode: 1),
            FakeProcessRunner.Script(exitCode: 0),
        ], forPathEndingIn: "yt-dlp")

        let first = await drain(runner.run(launch("yt-dlp")))
        XCTAssertEqual(first.exitCode, 1)
        let second = await drain(runner.run(launch("yt-dlp")))
        XCTAssertEqual(second.exitCode, 0)
    }

    func testLastOrderedScriptRepeats() async {
        let runner = FakeProcessRunner()
        runner.scripts([FakeProcessRunner.Script(exitCode: 3)], forPathEndingIn: "yt-dlp")
        _ = await drain(runner.run(launch("yt-dlp")))
        let again = await drain(runner.run(launch("yt-dlp")))
        XCTAssertEqual(again.exitCode, 3)
    }

    func testSingleScriptApiUnchanged() async {
        let runner = FakeProcessRunner()
        runner.script(.stderr("ERROR: boom", exitCode: 1), forPathEndingIn: "yt-dlp")
        let a = await drain(runner.run(launch("yt-dlp")))
        let b = await drain(runner.run(launch("yt-dlp")))
        XCTAssertEqual(a.exitCode, 1)
        XCTAssertEqual(b.exitCode, 1)
    }
}
```

- [x] **Step 2: Run, verify fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/FakeProcessRunnerTests`
Expected: FAIL — `value of type 'FakeProcessRunner' has no member 'scripts'`.

- [x] **Step 3: Implement**

In `FakeProcessRunner.State`, add `var orderedScripts: [String: [Script]] = [:]` and `var orderedIndex: [String: Int] = [:]`.

```swift
public func scripts(_ scripts: [Script], forPathEndingIn suffix: String) {
    box.mutate {
        $0.orderedScripts[suffix] = scripts
        $0.orderedIndex[suffix] = 0
    }
}
```

In `run(_:)`, in the `box.mutate` block that currently resolves `state.scripts[…] ?? … ?? Script(exitCode: 127)`, first check the ordered lists (keyed by `launch.executableURL.lastPathComponent`, then any suffix key that the path ends with):

```swift
let script: Script
if let key = state.orderedScripts.keys.first(where: {
    launch.executableURL.path.hasSuffix($0) || launch.executableURL.lastPathComponent == $0
}), let list = state.orderedScripts[key], !list.isEmpty {
    let i = min(state.orderedIndex[key] ?? 0, list.count - 1)
    script = list[i]
    state.orderedIndex[key] = (state.orderedIndex[key] ?? 0) + 1
} else {
    script = state.scripts[launch.executableURL.path]
        ?? state.scripts[launch.executableURL.lastPathComponent]
        ?? Script(exitCode: 127)
}
```

(Keep the `state.launches.append`, `currentConcurrent`, `maxConcurrent` lines exactly as they are — only the script resolution changes.)

- [x] **Step 4: Run, verify pass**

Run: same as Step 2. Expected: PASS.

- [x] **Step 5: Run the full suite** — `FakeProcessRunner` is used everywhere; the single-script path must be byte-for-byte unchanged.

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`
Expected: all green.

- [x] **Step 6: Lint**

Run: `mise exec -- tuist generate --no-open && mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean. `run(_:)`'s `box.mutate` closure may trip `cyclomatic_complexity` — extract the resolution into a private `func resolveScript(_ launch: ProcessLaunch, _ state: inout State) -> Script`.

- [x] **Step 7: Hand off** — report the two files to the user; no commit.

---

## Task 1: `RateHost`

**Files:**
- Create: `Sources/GrabberKit/RateLimiting/RateHost.swift`
- Test: `Tests/GrabberKitTests/RateHostTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct RateHost: Hashable, Sendable, CustomStringConvertible`
  - `public init(urlString: String)` — total, never fails
  - `public let canonical: String`
  - `public var description: String { canonical }`
  - `public static let unresolved: RateHost`

- [x] **Step 1: Write the failing test**

`Tests/GrabberKitTests/RateHostTests.swift`:

```swift
@testable import GrabberKit
import XCTest

final class RateHostTests: XCTestCase {
    func testYouTubeSubdomainsFoldToOneBucket() {
        let hosts = [
            "https://www.youtube.com/watch?v=abc",
            "https://youtu.be/abc",
            "https://m.youtube.com/watch?v=abc",
            "https://music.youtube.com/watch?v=abc",
            "https://gaming.youtube.com/watch?v=abc",
            "https://www.youtube-nocookie.com/embed/abc",
        ]
        for host in hosts {
            XCTAssertEqual(RateHost(urlString: host).canonical, "youtube", host)
        }
    }

    func testWWWStrippedAndGenericHostKept() {
        XCTAssertEqual(RateHost(urlString: "https://www.vimeo.com/123").canonical, "vimeo.com")
        XCTAssertEqual(RateHost(urlString: "https://archive.org/details/x").canonical, "archive.org")
    }

    func testUnparseableStringResolvesToUnresolved() {
        XCTAssertEqual(RateHost(urlString: "not a url").canonical, RateHost.unresolved.canonical)
        XCTAssertEqual(RateHost(urlString: "").canonical, RateHost.unresolved.canonical)
    }

    func testHashableAndDescription() {
        let a = RateHost(urlString: "https://youtu.be/x")
        let b = RateHost(urlString: "https://youtube.com/watch?v=y")
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
        XCTAssertEqual(a.description, "youtube")
    }
}
```

- [x] **Step 2: Run the test, verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/RateHostTests`
Expected: FAIL — `cannot find 'RateHost' in scope`.

- [x] **Step 3: Create `RateHost`**

`Sources/GrabberKit/RateLimiting/RateHost.swift`:

```swift
import Foundation

public struct RateHost: Hashable, Sendable, CustomStringConvertible {
    public let canonical: String

    public var description: String { canonical }

    public static let unresolved = RateHost(canonical: "unresolved")

    private init(canonical: String) {
        self.canonical = canonical
    }

    public init(urlString: String) {
        guard
            let host = URLComponents(string: urlString)?.host?.lowercased(),
            !host.isEmpty
        else {
            self = .unresolved
            return
        }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        self.canonical = Self.aliases[bare] ?? bare
    }

    private static let aliases: [String: String] = [
        "youtube.com": "youtube",
        "youtu.be": "youtube",
        "m.youtube.com": "youtube",
        "music.youtube.com": "youtube",
        "gaming.youtube.com": "youtube",
        "youtube-nocookie.com": "youtube",
    ]
}
```

- [x] **Step 4: Run the test, verify it passes**

Run: same as Step 2.
Expected: PASS.

- [x] **Step 5: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean. (`tuist generate --no-open` first if the new file is not yet in the project.)

- [x] **Step 6: Hand off**

Report the two new files to the user; do not commit.

---

## Task 2: `RateState` and `HostRateDisplayState`

**Files:**
- Create: `Sources/GrabberKit/RateLimiting/RateState.swift`
- Test: `Tests/GrabberKitTests/RateStateTests.swift`

**Interfaces:**
- Consumes: `RateHost` (Task 1) — only in the display-state doc comment, not the type.
- Produces:
  - `public enum RateState: Sendable, Equatable { case normal; case cooldown(until: Date, strikes: Int); case circuitOpen(since: Date, strikes: Int) }`
  - `public struct HostRateDisplayState: Sendable, Equatable { let state: RateState; let lastErrorKey: String?; let concurrencyReducedToOne: Bool }` — all `let`, public memberwise `init`
  - `public extension RateState { var strikes: Int }` — 0 for `.normal`

- [x] **Step 1: Write the failing test**

`Tests/GrabberKitTests/RateStateTests.swift`:

```swift
@testable import GrabberKit
import XCTest

final class RateStateTests: XCTestCase {
    func testStrikesAccessor() {
        XCTAssertEqual(RateState.normal.strikes, 0)
        XCTAssertEqual(RateState.cooldown(until: .now, strikes: 3).strikes, 3)
        XCTAssertEqual(RateState.circuitOpen(since: .now, strikes: 4).strikes, 4)
    }

    func testDisplayStateIsEquatable() {
        let a = HostRateDisplayState(
            state: .cooldown(until: Date(timeIntervalSince1970: 100), strikes: 1),
            lastErrorKey: "rate_limited",
            concurrencyReducedToOne: true
        )
        let b = a
        XCTAssertEqual(a, b)
    }
}
```

- [x] **Step 2: Run, verify fail**

Run: `xcodebuild … test -only-testing:GrabberKitTests/RateStateTests`
Expected: FAIL — `cannot find 'RateState' in scope`.

- [x] **Step 3: Create the file**

`Sources/GrabberKit/RateLimiting/RateState.swift`:

```swift
import Foundation

public enum RateState: Sendable, Equatable {
    case normal
    case cooldown(until: Date, strikes: Int)
    case circuitOpen(since: Date, strikes: Int)
}

public extension RateState {
    var strikes: Int {
        switch self {
        case .normal: 0
        case let .cooldown(_, strikes): strikes
        case let .circuitOpen(_, strikes): strikes
        }
    }
}

public struct HostRateDisplayState: Sendable, Equatable {
    public let state: RateState
    public let lastErrorKey: String?
    public let concurrencyReducedToOne: Bool

    public init(state: RateState, lastErrorKey: String?, concurrencyReducedToOne: Bool) {
        self.state = state
        self.lastErrorKey = lastErrorKey
        self.concurrencyReducedToOne = concurrencyReducedToOne
    }
}
```

- [x] **Step 4: Run, verify pass**

Run: same as Step 2. Expected: PASS.

- [x] **Step 5: Lint** — `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict` (regenerate first).

- [x] **Step 6: Hand off** — report files, no commit.

---

## Task 3: `EngineTuning` — the seven Phase 6 fields

**Files:**
- Modify: `Sources/GrabberKit/Model/EngineTuning.swift`
- Test: `Tests/GrabberKitTests/EngineTuningTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces — on `EngineTuning`:
  - `public var circuitStrikeThreshold: Int` (default 4)
  - `public var adaptiveConcurrencyStart: Int` (default 2)
  - `public var cleanStreakToRaise: Int` (default 5)
  - `public var networkOfflineGraceSeconds: Int` (default 2)
  - `public var networkOnlineSettleSeconds: Int` (default 2)
  - `public var concurrentFragmentsNormal: Int` (default 4)
  - `public var concurrentFragmentsThrottled: Int` (default 1)
  - env keys: `MG_CIRCUIT_STRIKE_THRESHOLD`, `MG_ADAPTIVE_CONCURRENCY_START`, `MG_CLEAN_STREAK_TO_RAISE`, `MG_NETWORK_OFFLINE_GRACE_SECONDS`, `MG_NETWORK_ONLINE_SETTLE_SECONDS`, `MG_CONCURRENT_FRAGMENTS_NORMAL`, `MG_CONCURRENT_FRAGMENTS_THROTTLED`
  - **the memberwise `init`'s seven new params are DEFAULTED** to their `.default` values (`circuitStrikeThreshold: Int = 4`, …). This keeps the existing 3-arg call site `BackoffTests.swift:57` (`EngineTuning(ytDlp:backoffLadder:backoffCap:)`) compiling untouched, and the `RatePolicyTests` / `RateLimiterTests` constructions that pass all fields explicitly still work. `.default` and `.resolved` pass all seven.

- [x] **Step 1: Write the failing test**

New sibling file `Tests/GrabberKitTests/EngineTuningRateLimitTests.swift` (keeps the existing `EngineTuningTests` under `type_body_length`):

```swift
@testable import GrabberKit
import XCTest

final class EngineTuningRateLimitTests: XCTestCase {
    func testRateLimitTuningDefaults() {
        let t = EngineTuning.default
        XCTAssertEqual(t.circuitStrikeThreshold, 4)
        XCTAssertEqual(t.adaptiveConcurrencyStart, 2)
        XCTAssertEqual(t.cleanStreakToRaise, 5)
        XCTAssertEqual(t.networkOfflineGraceSeconds, 2)
        XCTAssertEqual(t.networkOnlineSettleSeconds, 2)
        XCTAssertEqual(t.concurrentFragmentsNormal, 4)
        XCTAssertEqual(t.concurrentFragmentsThrottled, 1)
    }

    func testRateLimitEnvOverrides() {
        let env = [
            "MG_CIRCUIT_STRIKE_THRESHOLD": "2",
            "MG_ADAPTIVE_CONCURRENCY_START": "1",
            "MG_CLEAN_STREAK_TO_RAISE": "3",
            "MG_NETWORK_OFFLINE_GRACE_SECONDS": "5",
            "MG_NETWORK_ONLINE_SETTLE_SECONDS": "4",
            "MG_CONCURRENT_FRAGMENTS_NORMAL": "6",
            "MG_CONCURRENT_FRAGMENTS_THROTTLED": "2",
        ]
        let t = EngineTuning.resolved(environment: env)
        XCTAssertEqual(t.circuitStrikeThreshold, 2)
        XCTAssertEqual(t.adaptiveConcurrencyStart, 1)
        XCTAssertEqual(t.cleanStreakToRaise, 3)
        XCTAssertEqual(t.networkOfflineGraceSeconds, 5)
        XCTAssertEqual(t.networkOnlineSettleSeconds, 4)
        XCTAssertEqual(t.concurrentFragmentsNormal, 6)
        XCTAssertEqual(t.concurrentFragmentsThrottled, 2)
    }

    func testMalformedEnvKeepsDefault() {
        let t = EngineTuning.resolved(environment: ["MG_CIRCUIT_STRIKE_THRESHOLD": "nope"])
        XCTAssertEqual(t.circuitStrikeThreshold, 4)
    }
}
```

- [x] **Step 2: Run, verify fail**

Run: `xcodebuild … test -only-testing:GrabberKitTests/EngineTuningRateLimitTests`
Expected: FAIL — `value of type 'EngineTuning' has no member 'circuitStrikeThreshold'`.

- [x] **Step 3: Add the fields**

In `Sources/GrabberKit/Model/EngineTuning.swift`, in the `EngineTuning` struct — add the seven `public var` declarations, add them to the memberwise `init` **with defaults**, add them to `.default`, and add to `.resolved(environment:)` (which already has the `intValue(_:_:)` local helper):

```swift
// in EngineTuning:
public var circuitStrikeThreshold: Int
public var adaptiveConcurrencyStart: Int
public var cleanStreakToRaise: Int
public var networkOfflineGraceSeconds: Int
public var networkOnlineSettleSeconds: Int
public var concurrentFragmentsNormal: Int
public var concurrentFragmentsThrottled: Int

// in init(...) — the seven new params, defaulted:
//   circuitStrikeThreshold: Int = 4,
//   adaptiveConcurrencyStart: Int = 2,
//   cleanStreakToRaise: Int = 5,
//   networkOfflineGraceSeconds: Int = 2,
//   networkOnlineSettleSeconds: Int = 2,
//   concurrentFragmentsNormal: Int = 4,
//   concurrentFragmentsThrottled: Int = 1
// and the matching self.x = x assignments
```

```swift
// in .default:
circuitStrikeThreshold: 4,
adaptiveConcurrencyStart: 2,
cleanStreakToRaise: 5,
networkOfflineGraceSeconds: 2,
networkOnlineSettleSeconds: 2,
concurrentFragmentsNormal: 4,
concurrentFragmentsThrottled: 1
```

```swift
// in .resolved(environment:), after the ytDlp block, before the return:
let base6 = EngineTuning.default
return EngineTuning(
    ytDlp: ytDlp,
    backoffLadder: resolveLadder(environment["MG_BACKOFF_LADDER"]),
    backoffCap: intValue("MG_BACKOFF_CAP", EngineTuning.default.backoffCap),
    circuitStrikeThreshold: intValue("MG_CIRCUIT_STRIKE_THRESHOLD", base6.circuitStrikeThreshold),
    adaptiveConcurrencyStart: intValue("MG_ADAPTIVE_CONCURRENCY_START", base6.adaptiveConcurrencyStart),
    cleanStreakToRaise: intValue("MG_CLEAN_STREAK_TO_RAISE", base6.cleanStreakToRaise),
    networkOfflineGraceSeconds: intValue("MG_NETWORK_OFFLINE_GRACE_SECONDS", base6.networkOfflineGraceSeconds),
    networkOnlineSettleSeconds: intValue("MG_NETWORK_ONLINE_SETTLE_SECONDS", base6.networkOnlineSettleSeconds),
    concurrentFragmentsNormal: intValue("MG_CONCURRENT_FRAGMENTS_NORMAL", base6.concurrentFragmentsNormal),
    concurrentFragmentsThrottled: intValue("MG_CONCURRENT_FRAGMENTS_THROTTLED", base6.concurrentFragmentsThrottled)
)
```

Append the seven params to the `init` signature (after `backoffCap`), each **with its default**. `.default` and `.resolved` pass all seven explicitly.

- [x] **Step 4: Run, verify pass**

Run: same as Step 2, plus the full `EngineTuningTests` suite AND `BackoffTests` (which has a 3-arg `EngineTuning(` at line 57 — the defaults must let it compile untouched).
Expected: PASS. If `BackoffTests:57` fails to compile, the defaults were not applied — fix.

- [x] **Step 5: Lint** — regenerate, then `swiftformat --lint` + `swiftlint --strict`. `function_body_length` on `resolved()` may trip — if so, extract the Phase 6 fields into a private `resolveRateLimitTuning(_ environment:) -> RateLimitTuningValues` returning a small private `struct` (avoid `large_tuple`).

- [x] **Step 6: Hand off** — report files, no commit.

---

## Task 4: `RatePolicy` — the pure state machine

**Files:**
- Create: `Sources/GrabberKit/RateLimiting/RatePolicy.swift`
- Test: `Tests/GrabberKitTests/RatePolicyTests.swift`

**Interfaces:**
- Consumes: `RateState` (Task 2), `EngineTuning` (Task 3), `Backoff` (Phase 4 — `Backoff.delay(attempt:retryAfter:tuning:jitter:)`).
- Produces:
  - `public enum RatePolicyEvent: Sendable, Equatable { case strike(retryAfter: Int?); case cleanSuccess; case userReset }`
  - `public enum RatePolicy { public static func next(state: RateState, event: RatePolicyEvent, now: Date, tuning: EngineTuning, jitter: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> RateState }`

- [ ] **Step 1: Write the failing test**

`Tests/GrabberKitTests/RatePolicyTests.swift`:

```swift
@testable import GrabberKit
import XCTest

final class RatePolicyTests: XCTestCase {
    // ladder [1, 2], threshold 3, no jitter (always the max of the range)
    private let tuning = EngineTuning(
        ytDlp: .default,
        backoffLadder: [1, 2],
        backoffCap: 600,
        circuitStrikeThreshold: 3,
        adaptiveConcurrencyStart: 2,
        cleanStreakToRaise: 5,
        networkOfflineGraceSeconds: 2,
        networkOnlineSettleSeconds: 2,
        concurrentFragmentsNormal: 4,
        concurrentFragmentsThrottled: 1
    )
    private let noJitter: (ClosedRange<Double>) -> Double = { $0.upperBound }
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func next(_ s: RateState, _ e: RatePolicyEvent, at now: Date) -> RateState {
        RatePolicy.next(state: s, event: e, now: now, tuning: tuning, jitter: noJitter)
    }

    func testNormalStrikeEntersCooldownRungOne() {
        let s = next(.normal, .strike(retryAfter: nil), at: t0)
        guard case let .cooldown(until, strikes) = s else { return XCTFail("\(s)") }
        XCTAssertEqual(strikes, 1)
        XCTAssertEqual(until, t0.addingTimeInterval(1))
    }

    func testStrikeBeforeDeadlineIsIgnored() {
        let cooling = RateState.cooldown(until: t0.addingTimeInterval(30), strikes: 1)
        let s = next(cooling, .strike(retryAfter: nil), at: t0)
        XCTAssertEqual(s, cooling)
    }

    func testStrikeAfterDeadlineEscalatesThenTripsCircuit() {
        var s = RateState.cooldown(until: t0, strikes: 1)
        s = next(s, .strike(retryAfter: nil), at: t0.addingTimeInterval(5))
        guard case let .cooldown(_, strikes) = s else { return XCTFail("\(s)") }
        XCTAssertEqual(strikes, 2)

        s = next(s, .strike(retryAfter: nil), at: t0.addingTimeInterval(20))
        guard case let .circuitOpen(_, strikes3) = s else { return XCTFail("\(s)") }
        XCTAssertEqual(strikes3, 3)
    }

    func testCleanSuccessResetsFromCooldown() {
        let s = next(.cooldown(until: t0, strikes: 2), .cleanSuccess, at: t0)
        XCTAssertEqual(s, .normal)
    }

    func testUserResetFromCircuitOpen() {
        let s = next(.circuitOpen(since: t0, strikes: 4), .userReset, at: t0)
        XCTAssertEqual(s, .normal)
    }

    func testRetryAfterOverridesLadder() {
        let s = next(.normal, .strike(retryAfter: 120), at: t0)
        guard case let .cooldown(until, _) = s else { return XCTFail("\(s)") }
        XCTAssertEqual(until, t0.addingTimeInterval(120))
    }
}
```

- [ ] **Step 2: Run, verify fail** — `-only-testing:GrabberKitTests/RatePolicyTests`, FAIL `cannot find 'RatePolicy'`.

- [ ] **Step 3: Create `RatePolicy`**

`Sources/GrabberKit/RateLimiting/RatePolicy.swift`:

```swift
import Foundation

public enum RatePolicyEvent: Sendable, Equatable {
    case strike(retryAfter: Int?)
    case cleanSuccess
    case userReset
}

public enum RatePolicy {
    public static func next(
        state: RateState,
        event: RatePolicyEvent,
        now: Date,
        tuning: EngineTuning,
        jitter: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) -> RateState {
        switch event {
        case .cleanSuccess, .userReset:
            return .normal
        case let .strike(retryAfter):
            return afterStrike(state, retryAfter: retryAfter, now: now, tuning: tuning, jitter: jitter)
        }
    }

    private static func afterStrike(
        _ state: RateState,
        retryAfter: Int?,
        now: Date,
        tuning: EngineTuning,
        jitter: (ClosedRange<Double>) -> Double
    ) -> RateState {
        if case let .cooldown(until, _) = state, until > now {
            return state
        }
        let strikes = state.strikes + 1
        if strikes >= tuning.circuitStrikeThreshold {
            return .circuitOpen(since: now, strikes: strikes)
        }
        let delay = Backoff.delay(
            attempt: strikes,
            retryAfter: retryAfter,
            tuning: tuning,
            jitter: jitter
        )
        return .cooldown(until: now.addingTimeInterval(delay), strikes: strikes)
    }
}
```

- [ ] **Step 4: Run, verify pass** — same as Step 2. PASS.

- [ ] **Step 5: Lint** — regenerate, `swiftformat --lint` + `swiftlint --strict`.

- [ ] **Step 6: Hand off** — report files, no commit.

---

## Task 5: `RateLimiter`

**Files:**
- Create: `Sources/GrabberKit/RateLimiting/RateLimiter.swift`
- Test: `Tests/GrabberKitTests/RateLimiterTests.swift`

**Interfaces:**
- Consumes: `RateHost` (T1), `RateState` / `HostRateDisplayState` (T2), `EngineTuning` (T3), `RatePolicy` / `RatePolicyEvent` (T4).
- Produces — `struct RateLimiter` (not public; `internal` to `GrabberKit`, `@testable` reachable):
  - `init(tuning: EngineTuning, preferencesCap: Int)`
  - `private(set) var adaptiveCap: Int`
  - `mutating func recordStrike(host: RateHost, retryAfter: Int?, lastErrorKey: String, now: Date)` — `lastErrorKey` is `ErrorClass.key` (always `"rate_limited"` in Phase 6, kept general); stored per host so `displaySummary` can fill `HostRateDisplayState.lastErrorKey`
  - `mutating func recordCleanSuccess(host: RateHost, now: Date)`
  - `func state(for host: RateHost) -> RateState`
  - `func blocked(host: RateHost, now: Date) -> Bool`
  - `var circuitOpenHosts: Set<RateHost>`
  - `func cooldownDeadline(for host: RateHost) -> Date?`
  - `var concurrencyReducedByStrike: Bool`
  - `func displaySummary(now: Date) -> [RateHost: HostRateDisplayState]`
  - `mutating func resetCircuit(host: RateHost)`
  - `mutating func resetAllCircuits()`
  - `mutating func setPreferencesCap(_ cap: Int)`

- [ ] **Step 1: Write the failing test**

`Tests/GrabberKitTests/RateLimiterTests.swift`:

```swift
@testable import GrabberKit
import XCTest

final class RateLimiterTests: XCTestCase {
    private func tuning(threshold: Int = 3, streak: Int = 5) -> EngineTuning {
        EngineTuning(
            ytDlp: .default, backoffLadder: [1, 2], backoffCap: 600,
            circuitStrikeThreshold: threshold, adaptiveConcurrencyStart: 2,
            cleanStreakToRaise: streak, networkOfflineGraceSeconds: 2,
            networkOnlineSettleSeconds: 2, concurrentFragmentsNormal: 4,
            concurrentFragmentsThrottled: 1
        )
    }
    private let yt = RateHost(urlString: "https://youtube.com/watch?v=x")
    private let vimeo = RateHost(urlString: "https://vimeo.com/1")
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testAdaptiveCapStartsClamped() {
        XCTAssertEqual(RateLimiter(tuning: tuning(), preferencesCap: 6).adaptiveCap, 2)
        XCTAssertEqual(RateLimiter(tuning: tuning(), preferencesCap: 1).adaptiveCap, 1)
    }

    func testCleanStreakRaisesCapUpToPrefsCeiling() {
        var rl = RateLimiter(tuning: tuning(streak: 3), preferencesCap: 4)
        for _ in 0..<3 { rl.recordCleanSuccess(host: yt, now: t0) }
        XCTAssertEqual(rl.adaptiveCap, 3)
        for _ in 0..<3 { rl.recordCleanSuccess(host: yt, now: t0) }
        XCTAssertEqual(rl.adaptiveCap, 4)
        for _ in 0..<3 { rl.recordCleanSuccess(host: yt, now: t0) }
        XCTAssertEqual(rl.adaptiveCap, 4, "clamped at prefs cap")
    }

    func testStrikeDropsCapToOneAndResetsStreak() {
        var rl = RateLimiter(tuning: tuning(streak: 3), preferencesCap: 6)
        rl.recordCleanSuccess(host: yt, now: t0)
        rl.recordCleanSuccess(host: yt, now: t0)
        rl.recordStrike(host: yt, retryAfter: nil, lastErrorKey: "rate_limited", now: t0)
        XCTAssertEqual(rl.adaptiveCap, 1)
        XCTAssertTrue(rl.concurrencyReducedByStrike)
        rl.recordCleanSuccess(host: yt, now: t0)
        XCTAssertEqual(rl.adaptiveCap, 1, "streak restarted from zero")
    }

    func testBlockedTrueWhileCoolingFalseAfterDeadline() {
        var rl = RateLimiter(tuning: tuning(), preferencesCap: 6)
        rl.recordStrike(host: yt, retryAfter: 30, lastErrorKey: "rate_limited", now: t0)
        XCTAssertTrue(rl.blocked(host: yt, now: t0.addingTimeInterval(10)))
        XCTAssertFalse(rl.blocked(host: yt, now: t0.addingTimeInterval(31)))
        XCTAssertFalse(rl.blocked(host: vimeo, now: t0.addingTimeInterval(10)))
    }

    func testCircuitTripAndReset() {
        var rl = RateLimiter(tuning: tuning(threshold: 2), preferencesCap: 6)
        rl.recordStrike(host: yt, retryAfter: 1, lastErrorKey: "rate_limited", now: t0)
        rl.recordStrike(host: yt, retryAfter: 1, lastErrorKey: "rate_limited", now: t0.addingTimeInterval(5))
        XCTAssertEqual(rl.circuitOpenHosts, [yt])
        XCTAssertTrue(rl.blocked(host: yt, now: t0.addingTimeInterval(999)))
        rl.resetCircuit(host: yt)
        XCTAssertTrue(rl.circuitOpenHosts.isEmpty)
        XCTAssertFalse(rl.blocked(host: yt, now: t0.addingTimeInterval(999)))
    }

    func testCleanSuccessResetsStrikeSoLadderRestarts() {
        var rl = RateLimiter(tuning: tuning(threshold: 3), preferencesCap: 6)
        rl.recordStrike(host: yt, retryAfter: 1, lastErrorKey: "rate_limited", now: t0)
        rl.recordCleanSuccess(host: yt, now: t0.addingTimeInterval(5))
        rl.recordStrike(host: yt, retryAfter: 1, lastErrorKey: "rate_limited", now: t0.addingTimeInterval(10))
        guard case let .cooldown(_, strikes) = rl.state(for: yt) else {
            return XCTFail("\(rl.state(for: yt))")
        }
        XCTAssertEqual(strikes, 1, "clean success reset the count")
    }

    func testSetPreferencesCapReclampsWithoutJumping() {
        var rl = RateLimiter(tuning: tuning(streak: 3), preferencesCap: 6)
        for _ in 0..<3 { rl.recordCleanSuccess(host: yt, now: t0) } // cap 3
        rl.setPreferencesCap(2)
        XCTAssertEqual(rl.adaptiveCap, 2)
        rl.setPreferencesCap(6)
        XCTAssertEqual(rl.adaptiveCap, 2, "a raise does not jump the cap")
    }

    func testDisplaySummaryOnlyCoolingOrOpenHosts() {
        var rl = RateLimiter(tuning: tuning(), preferencesCap: 6)
        rl.recordStrike(host: yt, retryAfter: 30, lastErrorKey: "rate_limited", now: t0)
        let summary = rl.displaySummary(now: t0.addingTimeInterval(5))
        XCTAssertEqual(summary.keys.map(\.canonical), ["youtube"])
        XCTAssertEqual(summary[yt]?.lastErrorKey, "rate_limited")
        XCTAssertTrue(summary[yt]?.concurrencyReducedToOne ?? false)
        // once the deadline passes, the host is still tracked (strikes) but not "cooling"
        let later = rl.displaySummary(now: t0.addingTimeInterval(31))
        XCTAssertTrue(later.isEmpty)
    }
}
```

- [ ] **Step 2: Run, verify fail** — `-only-testing:GrabberKitTests/RateLimiterTests`, FAIL `cannot find 'RateLimiter'`.

- [ ] **Step 3: Create `RateLimiter`**

`Sources/GrabberKit/RateLimiting/RateLimiter.swift`:

```swift
import Foundation

struct RateLimiter {
    private var states: [RateHost: RateState] = [:]
    private var lastErrorKey: [RateHost: String] = [:]
    private(set) var adaptiveCap: Int
    private var cleanStreak = 0
    private var strikeLoweredCap = false
    private var preferencesCap: Int
    private let tuning: EngineTuning

    init(tuning: EngineTuning, preferencesCap: Int) {
        self.tuning = tuning
        self.preferencesCap = max(1, preferencesCap)
        adaptiveCap = min(max(1, tuning.adaptiveConcurrencyStart), self.preferencesCap)
    }

    // MARK: Outcomes

    mutating func recordStrike(host: RateHost, retryAfter: Int?, lastErrorKey key: String, now: Date) {
        states[host] = RatePolicy.next(
            state: states[host] ?? .normal,
            event: .strike(retryAfter: retryAfter),
            now: now,
            tuning: tuning
        )
        lastErrorKey[host] = key
        adaptiveCap = 1
        cleanStreak = 0
        strikeLoweredCap = true
    }

    mutating func recordCleanSuccess(host: RateHost, now: Date) {
        if states[host] != nil {
            states[host] = RatePolicy.next(state: states[host]!, event: .cleanSuccess, now: now, tuning: tuning)
            if states[host] == .normal { states[host] = nil }
            lastErrorKey[host] = nil
        }
        cleanStreak += 1
        if cleanStreak >= tuning.cleanStreakToRaise {
            adaptiveCap = min(adaptiveCap + 1, preferencesCap)
            cleanStreak = 0
            if adaptiveCap > 1 { strikeLoweredCap = false }
        }
    }

    // MARK: Queries

    func state(for host: RateHost) -> RateState { states[host] ?? .normal }

    func blocked(host: RateHost, now: Date) -> Bool {
        switch states[host] ?? .normal {
        case .normal: false
        case let .cooldown(until, _): until > now
        case .circuitOpen: true
        }
    }

    var circuitOpenHosts: Set<RateHost> {
        Set(states.compactMap { key, value in
            if case .circuitOpen = value { return key }
            return nil
        })
    }

    func cooldownDeadline(for host: RateHost) -> Date? {
        if case let .cooldown(until, _) = states[host] ?? .normal { return until }
        return nil
    }

    var concurrencyReducedByStrike: Bool { strikeLoweredCap && adaptiveCap == 1 }

    func displaySummary(now: Date) -> [RateHost: HostRateDisplayState] {
        var out: [RateHost: HostRateDisplayState] = [:]
        for (host, state) in states {
            switch state {
            case .normal:
                continue
            case let .cooldown(until, _):
                guard until > now else { continue }
            case .circuitOpen:
                break
            }
            out[host] = HostRateDisplayState(
                state: state,
                lastErrorKey: lastErrorKey[host],
                concurrencyReducedToOne: concurrencyReducedByStrike
            )
        }
        return out
    }

    // MARK: User actions

    mutating func resetCircuit(host: RateHost) {
        if case .circuitOpen = states[host] ?? .normal {
            states[host] = nil
            lastErrorKey[host] = nil
        }
    }

    mutating func resetAllCircuits() {
        for host in circuitOpenHosts {
            states[host] = nil
            lastErrorKey[host] = nil
        }
    }

    // MARK: Concurrency

    mutating func setPreferencesCap(_ cap: Int) {
        preferencesCap = max(1, cap)
        adaptiveCap = min(adaptiveCap, preferencesCap)
    }
}
```

- [ ] **Step 4: Run, verify pass** — same as Step 2. PASS. If `testCleanSuccessResetsStrikeSoLadderRestarts` fails because `recordCleanSuccess` cleared `states[host]` before the next strike — that is correct behavior (strike from `.normal` → rung 1). Keep.

- [ ] **Step 5: Lint** — regenerate; `swiftformat --lint` + `swiftlint --strict`. `cyclomatic_complexity` on `displaySummary` may trip — extract the "is this host visible" test into a private `func isVisible(_ state: RateState, now: Date) -> Bool`.

- [ ] **Step 6: Hand off** — report files, no commit.

---

## Task 6: `CountdownFormat`

**Files:**
- Create: `Sources/GrabberKit/RateLimiting/CountdownFormat.swift`
- Test: `Tests/GrabberKitTests/CountdownFormatTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public enum CountdownFormat { public static func mmss(until: Date, now: Date) -> String }` — `"0:00"` when `until <= now`, `"m:ss"` otherwise, minutes not zero-padded.

- [ ] **Step 1: Failing test**

```swift
@testable import GrabberKit
import XCTest

final class CountdownFormatTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)
    private func s(_ secs: TimeInterval) -> String {
        CountdownFormat.mmss(until: t0.addingTimeInterval(secs), now: t0)
    }
    func testBoundaries() {
        XCTAssertEqual(s(0), "0:00")
        XCTAssertEqual(s(-5), "0:00")
        XCTAssertEqual(s(59), "0:59")
        XCTAssertEqual(s(60), "1:00")
        XCTAssertEqual(s(134), "2:14")
        XCTAssertEqual(s(599), "9:59")
    }
}
```

- [ ] **Step 2: Run, verify fail** — `cannot find 'CountdownFormat'`.

- [ ] **Step 3: Create**

```swift
import Foundation

public enum CountdownFormat {
    public static func mmss(until: Date, now: Date) -> String {
        let remaining = max(0, Int(until.timeIntervalSince(now).rounded()))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}
```

- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Lint** — regenerate, lint.
- [ ] **Step 6: Hand off.**

---

## Task 7: `NetworkPathMonitoring` protocol + fake + live impl

**Files:**
- Create: `Sources/GrabberKit/RateLimiting/NetworkPathMonitoring.swift`
- Create: `Tests/TestSupport/FakeNetworkMonitor.swift`
- Test: `Tests/GrabberKitTests/NetworkPathMonitorTests.swift`

**Interfaces:**
- Consumes: `EngineTuning` (T3) for the debounce constants.
- Produces:
  - `public protocol NetworkPathMonitoring: Sendable { var isOnline: Bool { get async }; var stream: AsyncStream<Bool> { get } }`
  - `public final class NWPathNetworkMonitor: NetworkPathMonitoring` — live, wraps `NWPathMonitor`, debounced by `offlineGrace` / `onlineSettle` seconds
  - `public final class FakeNetworkMonitor: NetworkPathMonitoring` (in `TestSupport`) — `func goOffline()` / `func goOnline()` push raw booleans; no debounce (the engine debounce is what tests exercise via the live impl, so the fake emits immediately and the *engine* task consumes; debounce for the fake is out of scope — see note)

  **Debounce location decision:** the debounce lives in `NWPathNetworkMonitor` (the live impl), driven by `Task.sleep` + the injected values. `FakeNetworkMonitor` emits raw transitions immediately; engine tests that need to prove debounce behavior use a **separate** small test of `NWPathNetworkMonitor` with an injected clock-like sleeper. To keep this task bounded: the live impl takes a `sleep: @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }` injection point; the debounce test drives it with a controllable sleeper.

- [ ] **Step 1: Failing test**

`Tests/GrabberKitTests/NetworkPathMonitorTests.swift`:

```swift
@testable import GrabberKit
import TestSupport
import XCTest

final class NetworkPathMonitorTests: XCTestCase {
    func testFakeEmitsTransitions() async {
        let fake = FakeNetworkMonitor(startOnline: true)
        var received: [Bool] = []
        let task = Task {
            for await v in fake.stream {
                received.append(v)
                if received.count == 2 { break }
            }
        }
        fake.goOffline()
        fake.goOnline()
        await task.value
        XCTAssertEqual(received, [false, true])
    }

    func testLiveImplDebouncesOfflineByGrace() async {
        // controllable sleeper: records the requested durations, returns immediately
        let sleeps = LockedBox<[TimeInterval]>([])
        let monitor = NWPathNetworkMonitor(
            offlineGrace: 2, onlineSettle: 2,
            sleep: { d in sleeps.mutate { $0.append(d) } }
        )
        // drive a raw unsatisfied → satisfied via the test seam
        monitor._test_pushRawPath(satisfied: false)
        var received: [Bool] = []
        let task = Task {
            for await v in monitor.stream { received.append(v); break }
        }
        await task.value
        XCTAssertEqual(received, [false])
        XCTAssertTrue(sleeps.value.contains(2))
    }
}
```

- [ ] **Step 2: Run, verify fail** — `cannot find 'FakeNetworkMonitor'` / `'NWPathNetworkMonitor'`.

- [ ] **Step 3: Create the protocol + live impl**

`Sources/GrabberKit/RateLimiting/NetworkPathMonitoring.swift`:

```swift
import Foundation
import Network

public protocol NetworkPathMonitoring: Sendable {
    var isOnline: Bool { get async }
    var stream: AsyncStream<Bool> { get }
}

public final class NWPathNetworkMonitor: NetworkPathMonitoring, @unchecked Sendable {
    private let offlineGrace: TimeInterval
    private let onlineSettle: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "mg.network-path")
    private let box: LockedBox<State>
    private let continuation: AsyncStream<Bool>.Continuation
    public let stream: AsyncStream<Bool>

    private struct State {
        var lastPublished: Bool
        var pendingTask: Task<Void, Never>?
    }

    public init(
        offlineGrace: TimeInterval,
        onlineSettle: TimeInterval,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.offlineGrace = offlineGrace
        self.onlineSettle = onlineSettle
        self.sleep = sleep
        box = LockedBox(State(lastPublished: true, pendingTask: nil))
        (stream, continuation) = AsyncStream<Bool>.makeStream()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handleRaw(satisfied: path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    public var isOnline: Bool {
        get async { box.value.lastPublished }
    }

    func _test_pushRawPath(satisfied: Bool) { handleRaw(satisfied: satisfied) }

    private func handleRaw(satisfied: Bool) {
        let grace = satisfied ? onlineSettle : offlineGrace
        box.mutate { state in
            state.pendingTask?.cancel()
            state.pendingTask = Task { [weak self] in
                guard let self else { return }
                await self.sleep(grace)
                guard !Task.isCancelled else { return }
                self.box.mutate { s in
                    guard s.lastPublished != satisfied else { return }
                    s.lastPublished = satisfied
                    self.continuation.yield(satisfied)
                }
            }
        }
    }

    deinit {
        monitor.cancel()
        continuation.finish()
    }
}
```

**`LockedBox` is in `Tests/TestSupport/` — `GrabberKit` cannot import it.** So `NWPathNetworkMonitor` above does NOT use `LockedBox`. Rewrite its state handling to serialize on its own `DispatchQueue` (it already has `queue` for the `NWPathMonitor` handler):

```swift
public final class NWPathNetworkMonitor: NetworkPathMonitoring, @unchecked Sendable {
    private let offlineGrace: TimeInterval
    private let onlineSettle: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "mg.network-path")
    private var lastPublished = true          // touched only on `queue`
    private var pendingTask: Task<Void, Never>?
    private let continuation: AsyncStream<Bool>.Continuation
    public let stream: AsyncStream<Bool>

    public init(
        offlineGrace: TimeInterval,
        onlineSettle: TimeInterval,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.offlineGrace = offlineGrace
        self.onlineSettle = onlineSettle
        self.sleep = sleep
        (stream, continuation) = AsyncStream<Bool>.makeStream()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handleRaw(satisfied: path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    public var isOnline: Bool {
        get async { queue.sync { lastPublished } }
    }

    func _test_pushRawPath(satisfied: Bool) { queue.async { self.handleRaw(satisfied: satisfied) } }

    // always called on `queue`
    private func handleRaw(satisfied: Bool) {
        let grace = satisfied ? onlineSettle : offlineGrace
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            guard let self else { return }
            await self.sleep(grace)
            guard !Task.isCancelled else { return }
            self.queue.async {
                guard self.lastPublished != satisfied else { return }
                self.lastPublished = satisfied
                self.continuation.yield(satisfied)
            }
        }
    }

    deinit {
        monitor.cancel()
        continuation.finish()
    }
}
```

`Tests/TestSupport/FakeNetworkMonitor.swift`:

```swift
import Foundation
import GrabberKit

public final class FakeNetworkMonitor: NetworkPathMonitoring, @unchecked Sendable {
    private let box: LockedBox<Bool>   // FakeNetworkMonitor is in TestSupport → LockedBox is available here
    private let continuation: AsyncStream<Bool>.Continuation
    public let stream: AsyncStream<Bool>

    public init(startOnline: Bool = true) {
        box = LockedBox(startOnline)
        (stream, continuation) = AsyncStream<Bool>.makeStream()
    }

    public var isOnline: Bool { get async { box.read { $0 } } }

    public func goOffline() { push(false) }
    public func goOnline() { push(true) }

    private func push(_ online: Bool) {
        box.mutate { $0 = online }
        continuation.yield(online)
    }
}
```

**Also create the production-safe default** — `Sources/GrabberKit/RateLimiting/AlwaysOnlineMonitor.swift`:

```swift
import Foundation

public struct AlwaysOnlineMonitor: NetworkPathMonitoring {
    public init() {}
    public var isOnline: Bool { get async { true } }
    public var stream: AsyncStream<Bool> {
        AsyncStream { $0.finish() }   // never yields
    }
}
```

This is the `EngineDependencies.init` default (Task 11) so the ~10 test files that build `EngineDependencies(` directly do not spin up a real `NWPathMonitor`.

- [ ] **Step 4: Run, verify pass** — the `NetworkPathMonitorTests` from Step 1. Adjust the test's `_test_pushRawPath` timing: **start the `Task { for await … }` consumer before calling `_test_pushRawPath`** (an `AsyncStream` created without buffering drops values yielded before a consumer attaches). PASS.

- [ ] **Step 5: Lint** — regenerate; lint. `NWPathNetworkMonitor` may trip `type_body_length` — if so, move `handleRaw` into a `NWPathNetworkMonitor+Debounce.swift` extension file. `@unchecked Sendable` is required (holds `NWPathMonitor`); the `DispatchQueue` serialization is what makes it sound.

- [ ] **Step 6: Hand off** — report the three files (`NetworkPathMonitoring.swift`, `FakeNetworkMonitor.swift`, `AlwaysOnlineMonitor.swift`), no commit.

---

## Task 8: `JobSnapshot` / `QueueSnapshot` / `QueueHaltReason` field additions

**Files:**
- Modify: `Sources/GrabberKit/Download/JobSnapshot.swift`
- Modify: `Sources/GrabberKit/Download/QueueEvent.swift`
- Modify: `Sources/GrabberKit/Download/DownloadJob.swift` (`var cooldownUntil: Date?`; `snapshot(availableActions:)` stays one-arg)
- Modify: every `JobSnapshot(` / `QueueSnapshot(` construction site (grep in Step 4)
- Test: `Tests/GrabberKitTests/ValueTypesTests.swift` (add cases)

**Interfaces:**
- Consumes: `RateHost` (T1), `HostRateDisplayState` (T2).
- Produces:
  - `JobSnapshot` gains `public let rateHost: RateHost` — in the memberwise `init` **right after `url`**
  - `QueueHaltReason` gains `case networkDown` and `case circuitOpen`
  - `QueueSnapshot` gains `public let hostRateSummary: [RateHost: HostRateDisplayState]` and `public let isOnline: Bool`, both in the memberwise `init` (append after `generatedAt`)
  - `DownloadJob` gains `var cooldownUntil: Date?` (default nil in `init`)
  - `DownloadJob.snapshot(availableActions:)` **stays a one-arg method** — it now reads `RateHost(urlString: request.url)` and `self.cooldownUntil` internally. No new param. (Task 12 sets `job.cooldownUntil` in the re-queue paths.)

- [ ] **Step 1: Write the failing test**

Add to `Tests/GrabberKitTests/ValueTypesTests.swift`:

```swift
func testJobSnapshotCarriesRateHost() {
    let s = JobSnapshot(
        id: UUID(), url: "https://youtu.be/x", rateHost: RateHost(urlString: "https://youtu.be/x"),
        title: nil, state: .queued, progress: nil, kind: .video(maxHeight: 1080),
        durationSeconds: nil, extractor: nil, addedAt: .now, finishedAt: nil,
        destFolder: URL(fileURLWithPath: "/tmp"), outputFiles: [], sizeBytes: nil,
        actualQuality: nil, attempt: 0, cooldownUntil: nil, playerClientUsed: nil,
        playlistGroupID: nil, integrityVerdict: nil, availableActions: []
    )
    XCTAssertEqual(s.rateHost.canonical, "youtube")
}

func testQueueHaltReasonNewCases() {
    XCTAssertNotEqual(QueueHaltReason.networkDown, QueueHaltReason.circuitOpen)
    XCTAssertNotEqual(QueueHaltReason.depMissing, QueueHaltReason.networkDown)
}

func testQueueSnapshotNewFields() {
    let snap = QueueSnapshot(
        jobs: [], revision: 0, queueHalt: nil, generatedAt: .now,
        hostRateSummary: [:], isOnline: false
    )
    XCTAssertFalse(snap.isOnline)
    XCTAssertTrue(snap.hostRateSummary.isEmpty)
}
```

- [ ] **Step 2: Run, verify fail** — compile error on `rateHost:` / `hostRateSummary:` / `.networkDown`.

- [ ] **Step 3: Add the fields**

`JobSnapshot.swift` — in `enum JobState` leave as-is (already has `.cooldown` / `.waitingForNetwork`). In `enum QueueHaltReason`:

```swift
public enum QueueHaltReason: Sendable, Equatable {
    case depMissing
    case networkDown
    case circuitOpen
}
```

In `struct JobSnapshot`: add `public let rateHost: RateHost` right after `public let url: String`, and add `rateHost` to the `init` param list right after `url` and to the assignments.

`QueueEvent.swift` — in `struct QueueSnapshot`: add `public let hostRateSummary: [RateHost: HostRateDisplayState]` and `public let isOnline: Bool` and the matching `init` params (append after `generatedAt`) + assignments.

`DownloadJob.swift` — add `var cooldownUntil: Date?` (set `cooldownUntil = nil` in `init`). `snapshot` stays one-arg:

```swift
func snapshot(availableActions: Set<RowAction>) -> JobSnapshot {
    JobSnapshot(
        id: id,
        url: request.url,
        rateHost: RateHost(urlString: request.url),
        title: title,
        // … unchanged fields …
        cooldownUntil: cooldownUntil,   // the stored field, was hardcoded nil
        // … unchanged …
    )
}
```

- [ ] **Step 4: Update every `JobSnapshot(` / `QueueSnapshot(` construction site**

Run: `grep -rn 'JobSnapshot(' Sources/ Tests/` and `grep -rn 'QueueSnapshot(' Sources/ Tests/`. Fix each:
- `JobSnapshot(` — add `rateHost: RateHost(urlString: <the url arg used>)` right after `url:`. Known sites: `Sources/App/Rows/RowModel.swift` (`patchProgress` — use `known.rateHost`), `Tests/AppUnitTests/RowModelStatusTests.swift`, `RowStoreTests.swift`, `DownloadsTableTests.swift` (2×), `Tests/AppUnitTests/Support/AppModelTestHelpers.swift`, `Tests/GrabberKitTests/SchedulerTests.swift`, `Tests/GrabberKitTests/ValueTypesTests.swift`. The grep is authoritative — fix whatever it returns.
- `QueueSnapshot(` — add `hostRateSummary: [:], isOnline: true` after `generatedAt:` (unless the test is specifically about those fields). Known sites: `Tests/AppUnitTests/Support/AppFakes.swift` (`FakeEngine.State.snapshot`), `AppModelTests.swift`, `AppModelRowActionTests.swift`, `QuitCoordinatorTests.swift`, `DownloadsTableTests.swift`, `Tests/AppUnitTests/Support/AppModelTestHelpers.swift`.
- `DownloadJob.swift`'s `snapshot(availableActions:)` stays one-arg — no call-site change for that method.

- [ ] **Step 5: Run the full test suite**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`
Expected: PASS. Fix any missed construction site (compile errors point straight at them).

- [ ] **Step 6: Lint** — regenerate; `swiftformat --lint` + `swiftlint --strict`. `JobSnapshot`'s `init` is long — pre-existing, acceptable; do not restructure.

- [ ] **Step 7: Hand off** — report all changed files, no commit.

---

## Task 9: `availableActions` — split the `.cooldown` / `.waitingForNetwork` arm

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine+Helpers.swift:4-23` (`availableActions(for:)`)
- Test: `Tests/GrabberKitTests/AvailableActionsTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `availableActions(for: .cooldown(...))` → `[.forceStart, .cancel, .remove, .openInBrowser]`; `availableActions(for: .waitingForNetwork)` → `[.cancel, .remove, .openInBrowser]`.

- [ ] **Step 1: Failing test** — add to `AvailableActionsTests.swift`:

```swift
func testCooldownOffersForceStart() {
    let actions = DownloadEngine.availableActions(for: .cooldown(until: .now))
    XCTAssertTrue(actions.contains(.forceStart))
    XCTAssertTrue(actions.isSuperset(of: [.cancel, .remove, .openInBrowser]))
    XCTAssertFalse(actions.contains(.pause))
}

func testWaitingForNetworkHasNoForceStart() {
    let actions = DownloadEngine.availableActions(for: .waitingForNetwork)
    XCTAssertFalse(actions.contains(.forceStart))
    XCTAssertEqual(actions, [.cancel, .remove, .openInBrowser])
}
```

- [ ] **Step 2: Run, verify fail** — `testCooldownOffersForceStart` fails (`.forceStart` not in the set).

- [ ] **Step 3: Split the arm** in `DownloadEngine+Helpers.swift`:

```swift
case .waitingForNetwork:
    [.cancel, .remove, .openInBrowser]
case .cooldown:
    [.forceStart, .cancel, .remove, .openInBrowser]
```

- [ ] **Step 4: Update the existing breaking test.** `Tests/GrabberKitTests/AvailableActionsTests.swift` → `test_waitingForNetwork_and_cooldown` (around line 58): it currently asserts `actions(.cooldown(...))` has no `.forceStart` and equals `[.cancel, .remove, .openInBrowser]`. Change the `.cooldown` expectation to `[.forceStart, .cancel, .remove, .openInBrowser]`; leave the `.waitingForNetwork` line as-is. If the test asserts both in one `XCTAssertEqual` over an array `[.waitingForNetwork, .cooldown(...)]`, split it into two assertions.

- [ ] **Step 5: Run, verify pass.** Full `AvailableActionsTests` suite green.
- [ ] **Step 6: Lint** — `cyclomatic_complexity` on `availableActions` is near the limit; splitting one arm into two adds one branch. If it trips, extract the `.failed` arm into `private static func failedActions(_ errorClass: ErrorClass) -> Set<RowAction>`.
- [ ] **Step 7: Hand off.**

---

## Task 10: `DeferReason.hostCooldown` + `cancelDeferral` + `fireDueDeferrals` cooldown flip

**Files:**
- Modify: `Sources/GrabberKit/Download/SubmitResult.swift:15` (`enum DeferReason`)
- Modify: `Sources/GrabberKit/Logging/LogEvent.swift:157` (`deferredFields`)
- Modify: `Sources/GrabberKit/Download/DownloadEngine+Deferral.swift`
- Test: `Tests/GrabberKitTests/EngineDeferralTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `DeferReason` gains `case hostCooldown(host: String, strikes: Int)`
  - `DownloadEngine.cancelDeferral(_ id: UUID)` — internal, removes the job's deferral entry and re-arms the timer
  - `fireDueDeferrals()` — before its `evaluateSchedule()` call, any job in `.cooldown(until:)` with `until <= clock.now` returns to `.queued` in place, `cooldownUntil`-carrying snapshot field cleared on the next `buildSnapshot`

- [ ] **Step 1: Failing test** — add to `EngineDeferralTests.swift`. Match this suite's own `engine(clock:runner:probe:cap:)` private helper (positional, `clock` first) and `EventCollector(engine.events)`:

```swift
func testCancelDeferralRemovesEntry() async {
    let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
    let runner = FakeProcessRunner()
    let probe = FakeMetadataProbe()
    probe.result(FakeMetadataProbe.success(title: "Clip"))
    // cap 0 so nothing starts on its own
    let engine = engine(clock: clock, runner: runner, probe: probe, cap: 0)
    let collector = EventCollector(engine.events)
    let id = await submitJob(engine, Fix.request())
    await engine.deferStartForTest(id, until: Date(timeIntervalSince1970: 3600))
    await engine.cancelDeferralForTest(id)
    // deferral gone: the job is a plain .queued candidate again (cap 0 still keeps it queued,
    // but it must NOT be in the deferrals list) — assert via a follow-up cap bump
    await engine.setCap(1)
    _ = await collector.waitForState(id) { $0 == .running }
    XCTAssertEqual(job(collector, id)?.state, .running)
}

// A due .cooldown job returns to .queued when fireDueDeferrals runs.
func testDueCooldownJobReturnsToQueued() async {
    let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
    let runner = FakeProcessRunner()
    let probe = FakeMetadataProbe()
    probe.result(FakeMetadataProbe.success(title: "Clip"))
    let engine = engine(clock: clock, runner: runner, probe: probe, cap: 0)
    let collector = EventCollector(engine.events)
    let id = await submitJob(engine, Fix.request())
    // put the job directly into .cooldown + a matching deferral via the seam
    await engine.enterCooldownForTest(id, until: Date(timeIntervalSince1970: 30))
    XCTAssertEqual(job(collector, id).map { if case .cooldown = $0.state { return true }; return false }, true)
    clock.advance(by: .seconds(30))
    try? await Task.sleep(for: .milliseconds(20))
    XCTAssertEqual(job(collector, id)?.state, .queued)
}
```

Add three `@testable`-only seams to `DownloadEngine` (or `+Deferral`): `func cancelDeferralForTest(_ id: UUID)`, and `func enterCooldownForTest(_ id: UUID, until: Date)` which sets `job.state = .cooldown(until:)`, `job.cooldownUntil = until`, `deferStart(id, until:)`, `bump()`, `emitSnapshot()`. `deferStartForTest` already exists. `setCap` already exists and already re-evaluates.

- [ ] **Step 2: Run, verify fail** — `cannot find 'cancelDeferralForTest'` / `'enterCooldownForTest'`.

- [ ] **Step 3: Implement**

`SubmitResult.swift`:

```swift
public enum DeferReason: Sendable, Equatable {
    case backoff(attempt: Int)
    case hostCooldown(host: String, strikes: Int)
}
```

`LogEvent.swift` `deferredFields`:

```swift
case let .hostCooldown(host, strikes):
    fields["reason"] = "host_cooldown"
    fields["host"] = host
    fields["strikes"] = String(strikes)
```

`DownloadEngine+Deferral.swift`:

```swift
func cancelDeferral(_ id: UUID) {
    deferrals.removeAll { $0.id == id }
    armDeferralTask()
}

func cancelDeferralForTest(_ id: UUID) { cancelDeferral(id) }
```

In `fireDueDeferrals()` (current body: computes `due`, removes them, `deferralTask = nil`, `if !due.isEmpty { evaluateSchedule() }`, `armDeferralTask()`), add the cooldown-flip step before `evaluateSchedule()`:

```swift
private func fireDueDeferrals() {
    let now = dependencies.clock.now
    let due = deferrals.filter { $0.notBefore <= now }
    deferrals.removeAll { $0.notBefore <= now }
    deferralTask = nil
    var flipped = false
    for entry in due {
        flipped = resumeIfCooldownElapsed(entry.id, now: now) || flipped
    }
    if !due.isEmpty {
        if flipped { bump(); emitSnapshot() }
        evaluateSchedule()
    }
    armDeferralTask()
}

private func resumeIfCooldownElapsed(_ id: UUID, now: Date) -> Bool {
    guard let job = jobs.first(where: { $0.id == id }) else { return false }
    guard case let .cooldown(until) = job.state, until <= now else { return false }
    job.state = .queued
    job.cooldownUntil = nil
    return true
}
```

- [ ] **Step 4: Run, verify pass** — both tests. Full `EngineDeferralTests` suite green (the Phase 4 deferral tests are backoff-only, jobs stay `.queued`, so `resumeIfCooldownElapsed` is a no-op for them).
- [ ] **Step 5: Lint** — regenerate; lint.
- [ ] **Step 6: Hand off.**

---

## Task 11: Wire `RateLimiter` + `NetworkPathMonitoring` into the engine (no behavior yet)

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (stored properties, init, `effectiveCap`, `setCap`, `evaluateSchedule` re-clamp)
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` (`EngineDependencies` gains `networkMonitor`, default `AlwaysOnlineMonitor()`)
- Modify: `Tests/GrabberKitTests/DownloadEngineTestHelpers.swift` (`EngineFixture.engine` gains `networkMonitor:` + `clock:` + `tuning:` params)
- Modify: the ~10 direct `EngineDependencies(` sites in tests — they compile unchanged (defaulted param) but confirm none pass a live monitor unintentionally
- Test: `Tests/GrabberKitTests/RateLimiterWiringTests.swift`

**Interfaces:**
- Consumes: `RateLimiter` (T5), `NetworkPathMonitoring` / `FakeNetworkMonitor` / `AlwaysOnlineMonitor` (T7), `EngineTuning` (T3).
- Produces:
  - `DownloadEngine` holds `var rateLimiter: RateLimiter`, seeded `RateLimiter(tuning: dependencies.tuning, preferencesCap: cap)` — **`cap`, the existing computed property** (folds `capOverrideForTests` / `debugFlags.concurrencyCapOverride` / `preferences.maxConcurrentDownloads`), not `preferences.maxConcurrentDownloads` directly.
  - `DownloadEngine` gains `private var effectiveCap: Int { min(rateLimiter.adaptiveCap, cap) }` — the scheduler and `forceStart` eviction both use this (NOT `rateLimiter.adaptiveCap` alone, NOT `cap` alone). This preserves test caps, the `-MGConcurrencyCap` launch arg, and live prefs.
  - `evaluateSchedule()` calls `rateLimiter.setPreferencesCap(cap)` at the top of every pass (cheap; keeps the `RateLimiter` ceiling in sync with a live prefs change or a `setCap` without an observer). Then reads `effectiveCap`.
  - `setCap(_:)` (existing) — after setting `capOverrideForTests`, also `rateLimiter.setPreferencesCap(cap)` before `evaluateSchedule()`.
  - `DownloadEngine` holds `var isOnline = true`, `private var networkTask: Task<Void, Never>?`, subscribes to `dependencies.networkMonitor.stream` **eagerly in `init`**, cancelled in `shutdown()`. The task only sets `isOnline` for now — Task 13 adds the halt/park.
  - `EngineDependencies` gains `public var networkMonitor: any NetworkPathMonitoring`, default `AlwaysOnlineMonitor()` (a no-op — never yields, never touches the system). **Only `EngineDependencies.live(...)` constructs `NWPathNetworkMonitor`.**
  - `adaptiveCapForTest` / `isOnlineForTest` / `effectiveCapForTest` read seams.

- [x] **Step 1: Failing test**

```swift
@testable import GrabberKit
import TestSupport
import XCTest

final class RateLimiterWiringTests: XCTestCase {
    func testEngineSeedsRateLimiterFromTheCapProperty() async {
        let engine = EngineFixture.engine(runner: FakeProcessRunner(), probe: FakeMetadataProbe(), cap: 5)
        XCTAssertEqual(await engine.adaptiveCapForTest, 2)   // adaptiveConcurrencyStart, clamped ≤ 5
        XCTAssertEqual(await engine.effectiveCapForTest, 2)  // min(2, 5)
    }

    func testEffectiveCapRespectsTestCapBelowAdaptive() async {
        // cap 1 must win even though adaptive starts at 2
        let engine = EngineFixture.engine(runner: FakeProcessRunner(), probe: FakeMetadataProbe(), cap: 1)
        XCTAssertEqual(await engine.effectiveCapForTest, 1)
    }

    func testSetCapReclampsRateLimiter() async {
        let engine = EngineFixture.engine(runner: FakeProcessRunner(), probe: FakeMetadataProbe(), cap: 6)
        await engine.setCap(1)
        XCTAssertEqual(await engine.effectiveCapForTest, 1)
    }

    func testEngineTracksOnlineFromMonitor() async {
        let net = FakeNetworkMonitor(startOnline: true)
        let engine = EngineFixture.engine(
            runner: FakeProcessRunner(), probe: FakeMetadataProbe(), networkMonitor: net
        )
        net.goOffline()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(await engine.isOnlineForTest)
    }
}
```

- [x] **Step 2: Run, verify fail** — `EngineFixture.engine` has no `networkMonitor:` param; `adaptiveCapForTest` / `effectiveCapForTest` missing.

- [x] **Step 3: Wire it**

`DownloadEngineProtocol.swift` — `EngineDependencies` gains `public var networkMonitor: any NetworkPathMonitoring`. In `init`, add `networkMonitor: (any NetworkPathMonitoring)? = nil` and `self.networkMonitor = networkMonitor ?? AlwaysOnlineMonitor()`. In `EngineDependencies.live(...)`, pass `networkMonitor: NWPathNetworkMonitor(offlineGrace: TimeInterval(tuning.networkOfflineGraceSeconds), onlineSettle: TimeInterval(tuning.networkOnlineSettleSeconds))` (the `tuning` local is resolved earlier in `.live`).

`DownloadEngine.swift`:

```swift
var rateLimiter: RateLimiter
var isOnline = true
private var networkTask: Task<Void, Never>?

// in init, AFTER `dependencies` and `preferences` are set:
rateLimiter = RateLimiter(tuning: dependencies.tuning, preferencesCap: cap)  // `cap` = the computed property
networkTask = Task { [weak self] in
    guard let self else { return }
    for await online in self.dependencies.networkMonitor.stream {
        await self.applyNetworkChange(online)
    }
}

// the effective cap — used by evaluateSchedule AND forceStart eviction:
private var effectiveCap: Int { min(rateLimiter.adaptiveCap, cap) }

func applyNetworkChange(_ online: Bool) {
    guard online != isOnline else { return }
    isOnline = online
    // Task 13 adds the halt / job-park behavior here
    bump()
    emitSnapshot()
}

var adaptiveCapForTest: Int { rateLimiter.adaptiveCap }
var effectiveCapForTest: Int { effectiveCap }
var isOnlineForTest: Bool { isOnline }
```

In `evaluateSchedule()`, before building `SchedulerInput`: `rateLimiter.setPreferencesCap(cap)`. In `setCap(_:)`, after `capOverrideForTests = value`: `rateLimiter.setPreferencesCap(cap)` (before the existing `evaluateSchedule()`).

`shutdown()` — add `networkTask?.cancel(); networkTask = nil`.

`DownloadEngineTestHelpers.swift` — `EngineFixture.engine` gains four params, needed by Tasks 12–19:
- `networkMonitor: (any NetworkPathMonitoring)? = nil` — passed straight through; `EngineDependencies`'s own default `AlwaysOnlineMonitor` covers nil, but pass a `FakeNetworkMonitor(startOnline: true)` by default here so a test can grab it. (Actually simplest: `networkMonitor: (any NetworkPathMonitoring)? = nil` → `EngineDependencies(networkMonitor:)`; a test that needs to toggle builds its own `FakeNetworkMonitor` and passes it.)
- `clock: FakeClock? = nil` → `EngineDependencies(clock:)`, default `SystemClock`.
- `tuning: EngineTuning = .default` → `EngineDependencies(tuning:)`.
- `maxAutoRetries: Int? = nil` → if set, `prefs.maxAutoRetries = maxAutoRetries` on the built `Preferences`.

- [x] **Step 4: Run, verify pass** — both tests. Full suite for regression (the `EngineDependencies.init` signature change ripples — fix any direct constructions).

- [x] **Step 5: Lint** — regenerate; lint. `EngineDependencies.init` body length may trip — it is pre-existing large; if the new lines tip it, extract the monitor default into `private static func defaultMonitor(_ tuning: EngineTuning) -> any NetworkPathMonitoring`.

- [x] **Step 6: Hand off** — report files, no commit.

---

## Task 12: `recordExit` split — the strike + host-cooldown path

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine+Mutations.swift` (`recordExit`, `reQueueForBackoff`, `markRunning`)
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (`evaluateSchedule` — `cap` swap; `SchedulerInput` build)
- Modify: `Sources/GrabberKit/Download/Scheduler.swift` (`SchedulerInput` + `nextDownloads` filter)
- Test: `Tests/GrabberKitTests/EngineRateLimitTests.swift`

**Interfaces:**
- Consumes: `RateLimiter` (T5, engine-held from T11), `RatePolicy`, `Backoff`, `RateHost`.
- Produces:
  - `SchedulerInput` gains `public var blockedHostIDs: Set<UUID>` and `public var blockedProbeHostIDs: Set<UUID>` (append to `init`, after `deferredIDs`)
  - `Scheduler.nextDownloads` filters out `blockedHostIDs`; `Scheduler.nextProbe` filters out `blockedProbeHostIDs`
  - `evaluateSchedule()` re-clamps `rateLimiter.setPreferencesCap(cap)`, builds both blocked sets from `rateLimiter.blocked(host:now:)`, uses `effectiveCap` (T11) for `SchedulerInput.cap`
  - `recordExit`: **strike is Step A, unconditional** on `.rateLimited` (terminal or not); Step B branches on the retry budget → host-cooldown re-queue / terminal `.failed(.rateLimited)` / Phase 4 backoff / other terminal. A `.completed` → `rateLimiter.recordCleanSuccess`. A cap delta → `adaptiveConcurrencyChanged` log.
  - **Only one `.cooldown` job per host at a time** — the struck job goes `.cooldown` only if no other job for that host is already `.cooldown`; otherwise `.queued` (gated by `blockedHostIDs`).
  - **Already-running siblings are not SIGTERM'd** on a strike.
  - `ErrorSignatures.rateLimited` covers `"HTTP Error 429"`, `"Too Many Requests"`, `"below throttle limit"`, `"The download speed is below the minimum"` (verified present) — no change needed; if a 2026 phrasing is missing, add it here with an `ErrorSignaturesTests` case.

- [x] **Step 0: Confirm the 429 signatures.** Open `Sources/GrabberKit/Download/ErrorSignatures.swift`. The `.rateLimited()` group already lists `"HTTP Error 429"`, `"Too Many Requests"`, `"below throttle limit"`, `"The download speed is below the minimum"`. If yt-dlp's current 429 wording differs, add one string + one `ErrorSignaturesTests` assertion. Otherwise proceed.

- [x] **Step 1: Failing test**

`Tests/GrabberKitTests/EngineRateLimitTests.swift` — uses the **real** harness (`EventCollector(engine.events)`, `runner.script` / `runner.scripts`, `clock.advance`):

```swift
@testable import GrabberKit
import TestSupport
import XCTest

final class EngineRateLimitTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func job(_ c: EventCollector, _ id: UUID) -> JobSnapshot? {
        c.latestSnapshot()?.jobs.first { $0.id == id }
    }
    private func isCooldown(_ s: JobState?) -> Bool {
        if case .cooldown = s { return true }; return false
    }
    private let rl429 = FakeProcessRunner.Script.stderr("ERROR: HTTP Error 429: Too Many Requests", exitCode: 1)

    func testRateLimitedExitStrikesHostAndCoolsTheJob() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1_000))
        let runner = FakeProcessRunner()
        runner.script(rl429, forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, clock: clock, cap: 1)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { self.isCooldown($0) }

        let j = job(collector, id)!
        XCTAssertNotNil(j.cooldownUntil)
        XCTAssertEqual(j.attempt, 1)
        XCTAssertEqual(await engine.adaptiveCapForTest, 1)
        XCTAssertEqual(collector.latestSnapshot()?.hostRateSummary.count, 1)
    }

    func testSecondQueuedJobForSameHostIsBlockedNotMutated() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1_000))
        let runner = FakeProcessRunner()
        // job a always 429s; job b would complete if it ever ran (it must not, while a cools)
        runner.script(rl429, forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, clock: clock, cap: 2)
        let collector = EventCollector(engine.events)

        let a = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=a"))
        let b = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=b"))
        _ = await collector.waitForState(a) { self.isCooldown($0) }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(job(collector, b)?.state, .queued, "sibling not moved to .cooldown, not started")
    }

    func testTwoInFlightBothFailOnlyOneCools() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1_000))
        let runner = FakeProcessRunner()
        runner.script(rl429, forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, clock: clock, cap: 2)
        let collector = EventCollector(engine.events)

        let a = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=a"))
        let b = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=b"))
        _ = await collector.waitForState(a) { self.isCooldown($0) || $0 == .failed(.rateLimited()) }
        _ = await collector.waitForState(b) { $0 != .running && $0 != .probing }
        try? await Task.sleep(for: .milliseconds(50))

        let snap = collector.latestSnapshot()!
        let cooling = snap.jobs.filter { self.isCooldown($0.state) }
        XCTAssertLessThanOrEqual(cooling.count, 1, "at most one .cooldown job per host")
    }

    func testNonRateLimitFailureDoesNotTouchHostState() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
        let runner = FakeProcessRunner()
        runner.script(.stderr("ERROR: unable to write data: No space left on device", exitCode: 1),
                      forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, clock: clock, cap: 1)
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { if case .failed = $0 { return true }; return false }
        XCTAssertTrue(collector.latestSnapshot()!.hostRateSummary.isEmpty)
        XCTAssertEqual(await engine.adaptiveCapForTest, 2, "unchanged by a non-rate-limit failure")
    }

    func testTerminalRateLimitedStillStrikes() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1_000))
        let runner = FakeProcessRunner()
        runner.script(rl429, forPathEndingIn: "yt-dlp")   // every attempt 429s
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        // maxAutoRetries 1 → attempt 0 → cooldown → deadline → attempt 1 → terminal
        let engine = Fix.engine(runner: runner, probe: probe, clock: clock, cap: 1,
                                tuning: EngineTuning.resolved(environment: ["MG_BACKOFF_LADDER": "1"]),
                                maxAutoRetries: 1)
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { self.isCooldown($0) }
        clock.advance(by: .seconds(2))
        try? await Task.sleep(for: .milliseconds(30))
        _ = await collector.waitForState(id) { $0 == .failed(.rateLimited()) }

        XCTAssertFalse(collector.latestSnapshot()!.hostRateSummary.isEmpty,
                       "host still struck even though the job is done retrying")
    }

    func testCleanCompletionResetsHostAndRampsCap() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1_000))
        let runner = FakeProcessRunner()
        // first launch 429s, second completes — Task 0 ordered scripts
        runner.scripts([rl429, FakeProcessRunner.Script(exitCode: 0)], forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, clock: clock, cap: 3,
                                tuning: EngineTuning.resolved(environment: ["MG_BACKOFF_LADDER": "1"]))
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { self.isCooldown($0) }
        clock.advance(by: .seconds(2))
        try? await Task.sleep(for: .milliseconds(30))
        _ = await collector.waitForState(id) { $0 == .completed }

        XCTAssertTrue(collector.latestSnapshot()!.hostRateSummary.isEmpty, "clean success cleared the host")
    }
}
```

`EngineFixture.engine` gains a `maxAutoRetries: Int? = nil` param (→ sets `prefs.maxAutoRetries` on the built `Preferences`) alongside `clock:` / `tuning:` from Task 11.

- [x] **Step 2: Run, verify fail** — `-only-testing:GrabberKitTests/EngineRateLimitTests`. Compile errors / states never reached.

- [x] **Step 3: Implement**

`Scheduler.swift` — `SchedulerInput` gains the two `Set<UUID>` fields (in the stored-property list after `deferredIDs`, and in `init` after `deferredIDs:`). `nextDownloads`'s `isDownloadReady` gains `&& !blockedHostIDs.contains(job.id)` (thread `input.blockedHostIDs` through). `nextProbe`:

```swift
public static func nextProbe(_ input: SchedulerInput) -> UUID? {
    guard input.probeIdle else { return nil }
    return input.queued.first { needsMetadata($0) && !input.blockedProbeHostIDs.contains($0.id) }?.id
}
```

`DownloadEngine.evaluateSchedule()` — add before the `SchedulerInput` build (the guard stays `guard queueHalt == nil` as today; Task 13 makes `.networkDown` a real halt via that same field):

```swift
rateLimiter.setPreferencesCap(cap)
let now = dependencies.clock.now
let blockedDL = Set(jobs.filter {
    $0.state == .queued && rateLimiter.blocked(host: RateHost(urlString: $0.request.url), now: now)
}.map(\.id))
let blockedProbe = Set(jobs.filter {
    probeNeeded($0) && rateLimiter.blocked(host: RateHost(urlString: $0.request.url), now: now)
}.map(\.id))
```

and in the `SchedulerInput(...)` literal: `cap: effectiveCap`, `blockedHostIDs: blockedDL`, `blockedProbeHostIDs: blockedProbe`. Add `private func probeNeeded(_ job: DownloadJob) -> Bool` (mirror the existing metadata-needed check) if not already present under another name.

`recordExit` (`+Mutations.swift`) — the strike is unconditional (Step A), the job fate depends on the budget (Step B). Extract helpers to stay under `function_body_length`:

```swift
func recordExit(_ id: UUID, _ result: ProcessResult, integrity: IntegrityResult?,
                lastError: ErrorClass?, launchFailed: Bool,
                cookiesRequested: Bool = false, extractedZeroCookies: Bool = false) {
    childTasks[id] = nil
    guard let job = jobs.first(where: { $0.id == id }) else { evaluateSchedule(); return }
    guard job.state == .running else { evaluateSchedule(); return }   // parked by pause/evict/offline
    if launchFailed { haltForDepMissing(offending: job); return }
    if result.wasCancelled { markCancelledFromExit(job); return }     // existing behavior, factored

    if result.exitCode == 0, completedCleanly(integrity) {
        recordCleanSuccessFor(job)
        completeJob(job, integrity: integrity)                        // existing completion body
        return
    }
    if case .failed = integrity?.verdict { job.integrityVerdict = integrity?.verdict }

    let errorClass = classifiedFailure(result: result, lastError: lastError,
                                       cookiesRequested: cookiesRequested,
                                       extractedZeroCookies: extractedZeroCookies)
    let host = RateHost(urlString: job.request.url)

    // Step A — strike is about the host, terminal or not
    if case let .rateLimited(retryAfter) = errorClass {
        let before = rateLimiter.adaptiveCap
        rateLimiter.recordStrike(host: host, retryAfter: retryAfter,
                                 lastErrorKey: errorClass.key, now: dependencies.clock.now)
        logHostRateStrike(host, before: before)
    }

    // Step B — the job's fate
    if errorClass.isAutoRetryable, job.attempt < preferences.maxAutoRetries {
        if case .rateLimited = errorClass {
            reQueueForHostRate(job, id: id, host: host)
        } else {
            reQueueForBackoff(job, id: id, errorClass: errorClass)   // Phase 4, + job.cooldownUntil now
        }
        return
    }
    job.state = .failed(errorClass)
    job.finishedAt = .now
    finishTerminal()
}

private func recordCleanSuccessFor(_ job: DownloadJob) {
    let before = rateLimiter.adaptiveCap
    rateLimiter.recordCleanSuccess(host: RateHost(urlString: job.request.url), now: dependencies.clock.now)
    if rateLimiter.adaptiveCap != before {
        logEvent(.adaptiveConcurrencyChanged(from: before, to: rateLimiter.adaptiveCap, reason: "clean_streak"))
    }
}

private func logHostRateStrike(_ host: RateHost, before: Int) {
    let state = rateLimiter.state(for: host)
    logEvent(.hostRateStateChanged(host: host.canonical, from: "", to: describeRateState(state)))
    if case let .circuitOpen(_, strikes) = state {
        logEvent(.circuitOpened(host: host.canonical, strikes: strikes))
    }
    if rateLimiter.adaptiveCap != before {
        logEvent(.adaptiveConcurrencyChanged(from: before, to: rateLimiter.adaptiveCap, reason: "throttle"))
    }
}

// The one-.cooldown-job-per-host rule.
private func reQueueForHostRate(_ job: DownloadJob, id: UUID, host: RateHost) {
    job.attempt += 1
    job.progress = nil
    let anotherCooling = jobs.contains {
        $0.id != id && isCooldownState($0.state)
            && RateHost(urlString: $0.request.url) == host
    }
    if let deadline = rateLimiter.cooldownDeadline(for: host), !anotherCooling {
        job.state = .cooldown(until: deadline)
        job.cooldownUntil = deadline
        logEvent(.jobDeferred(id: id, until: deadline,
                              reason: .hostCooldown(host: host.canonical, strikes: rateLimiter.state(for: host).strikes)))
        deferStart(id, until: deadline)
    } else {
        // circuit is open, OR another job for this host already holds the .cooldown slot
        job.state = .queued
        job.cooldownUntil = nil
        cancelDeferral(id)
    }
    bump(); emitSnapshot()
    evaluateSchedule()
}

func isCooldownState(_ s: JobState) -> Bool { if case .cooldown = s { return true }; return false }

private func describeRateState(_ s: RateState) -> String {
    switch s {
    case .normal: "normal"
    case .cooldown: "cooldown"
    case .circuitOpen: "circuit_open"
    }
}
```

`reQueueForBackoff` (Phase 4) — one added line: `job.cooldownUntil = deadline` (the backoff deadline it already computes). Phase 4 leaves it nil today.

`recordProbeResult` — **not** touched (a probe is not a download completion; only `.completed` resets the host).

- [x] **Step 4: Run, verify pass** — the seven `EngineRateLimitTests` cases. Then the full suite.

  **Existing tests to update:**
  - `EngineRetryTests.swift` — any test that submits a 429 and then `waitForState(id) { $0 == .queued }` now transitions **through** `.cooldown` first. `test_autoRetryableExitDefersWithIncrementedAttempt` and siblings: change the intermediate wait to `{ isCooldown($0) }` (add the local helper), keep the terminal assertions. A 429 test that expects `.failed(.rateLimited())` after budget exhaustion still passes (Step B terminal branch) — but it now goes `.cooldown` → advance clock → retry → `.failed`; if the test does not `clock.advance`, it will hang. Add `clock.advance(by: .seconds(N))` (N ≥ the ladder's first rung; set `MG_BACKOFF_LADDER=1` via the `tuning:` param for speed).
  - `SchedulerTests.swift` — every `SchedulerInput(` gets `blockedHostIDs: [], blockedProbeHostIDs: []`.
  - `EngineDeferralTests.swift` — the `DeferReason` enum is non-`@frozen`; a `switch` over it in a test needs the new `.hostCooldown` case or `default`.

- [x] **Step 5: Lint** — `recordExit` and its helpers: keep each helper < 50 lines, < 10 branches. The extraction above is sized for that. `describeRateState`'s `switch` returning values may trip `void_function_in_ternary` under swiftformat — if so, add explicit `return`s.

- [x] **Step 6: Hand off** — report all changed files, no commit.

---

## Task 13: Network offline/online engine behavior

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (`applyNetworkChange`)
- Modify: `Sources/GrabberKit/Download/DownloadEngine+State.swift` (`buildSnapshot` — `isOnline`)
- Test: `Tests/GrabberKitTests/EngineNetworkTests.swift`

**Interfaces:**
- Consumes: `FakeNetworkMonitor` (T7), engine `isOnline` / `networkTask` (T11).
- Produces:
  - `applyNetworkChange(false)` → `queueHalt = .networkDown`; every `.running` / `.probing` job → `childTasks[id]?.cancel()` (SIGTERM), `.waitingForNetwork`, `attempt` & `.part` unchanged
  - `applyNetworkChange(true)` → if `queueHalt == .networkDown` clear it; `.waitingForNetwork` jobs → `.queued` (moved to tail); `evaluateSchedule()`
  - `buildSnapshot` sets `isOnline: isOnline`; `queueHalt: effectiveQueueHalt()` (Task 14 adds the `.circuitOpen` derivation; here it just returns the raw `queueHalt`)
  - `.queued` jobs are NOT touched on offline
  - the existing `evaluateSchedule()` guard is already `guard queueHalt == nil else { return }` (verified) — so `.networkDown` halts the scheduler for free once set

- [x] **Step 1: Failing test**

To keep a job "running" without a `holdOpen` API, give it a script whose lines drip via `perLineDelay` (or a long `perRunDelay`) so it stays mid-stream while the test toggles the network.

```swift
@testable import GrabberKit
import TestSupport
import XCTest

final class EngineNetworkTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func longRunner(exitCode: Int32 = 0) -> FakeProcessRunner {
        let runner = FakeProcessRunner()
        runner.perLineDelay = .milliseconds(500)   // stays "running" long enough to toggle the net
        runner.script(
            FakeProcessRunner.Script(lines: [Fix.progressLine("10"), Fix.progressLine("50"), Fix.progressLine("90")],
                                     exitCode: exitCode),
            forPathEndingIn: "yt-dlp"
        )
        return runner
    }
    private func job(_ c: EventCollector, _ id: UUID) -> JobSnapshot? {
        c.latestSnapshot()?.jobs.first { $0.id == id }
    }

    func testOfflineHaltsAndParksRunningJobs() async {
        let net = FakeNetworkMonitor(startOnline: true)
        let runner = longRunner()
        let probe = FakeMetadataProbe(); probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, networkMonitor: net, cap: 2)
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .running }

        net.goOffline()
        try? await Task.sleep(for: .milliseconds(80))

        let snap = collector.latestSnapshot()!
        XCTAssertEqual(snap.queueHalt, .networkDown)
        XCTAssertFalse(snap.isOnline)
        XCTAssertEqual(job(collector, id)?.state, .waitingForNetwork)
        XCTAssertEqual(job(collector, id)?.attempt, 0)
    }

    func testOnlineResumesWithoutBurningAttempt() async {
        let net = FakeNetworkMonitor(startOnline: true)
        let runner = FakeProcessRunner()
        runner.perLineDelay = .milliseconds(300)
        runner.scripts([
            FakeProcessRunner.Script(lines: [Fix.progressLine("10"), Fix.progressLine("50")], exitCode: 0),
            FakeProcessRunner.Script(exitCode: 0),
        ], forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe(); probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, networkMonitor: net, cap: 2)
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request())
        _ = await collector.waitForState(id) { $0 == .running }
        net.goOffline(); try? await Task.sleep(for: .milliseconds(80))
        net.goOnline();  try? await Task.sleep(for: .milliseconds(80))

        let snap = collector.latestSnapshot()!
        XCTAssertNil(snap.queueHalt)
        XCTAssertTrue(snap.isOnline)
        XCTAssertEqual(job(collector, id)?.attempt, 0, "no retry attempt burned")
    }

    func testQueuedJobsStayQueuedOnOffline() async {
        let net = FakeNetworkMonitor(startOnline: true)
        let engine = Fix.engine(runner: FakeProcessRunner(), probe: FakeMetadataProbe(), networkMonitor: net, cap: 1)
        _ = await submitJob(engine, Fix.request(url: "https://a.test/1"))
        let b = await submitJob(engine, Fix.request(url: "https://b.test/2"))
        net.goOffline(); try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(job(EventCollector(engine.events), b)?.state ?? (await engine.currentSnapshot().jobs.first { $0.id == b }?.state), .queued)
    }

    func testSubGraceBlipIsNotHonoured_liveMonitorOnly() async {
        // The debounce lives in NWPathNetworkMonitor, exercised in NetworkPathMonitorTests (Task 7).
        // FakeNetworkMonitor emits raw transitions, so this suite does not test debounce.
    }
}
```

- [x] **Step 2: Run, verify fail.**

- [x] **Step 3: Implement `applyNetworkChange`** (Task 11 stubbed it to just set `isOnline`):

```swift
func applyNetworkChange(_ online: Bool) {
    guard online != isOnline else { return }
    isOnline = online
    logEvent(.networkPathChanged(online: online))
    if online {
        if queueHalt == .networkDown { queueHalt = nil }
        let parked = jobs.filter { $0.state == .waitingForNetwork }
        for job in parked {
            job.state = .queued
            move(job, toTail: true)
        }
    } else {
        queueHalt = .networkDown
        let active = jobs.filter { $0.state == .running || $0.state == .probing }
        for job in active {
            childTasks[job.id]?.cancel()
            job.state = .waitingForNetwork
            job.progress = nil
        }
    }
    bump()
    emitSnapshot()
    evaluateSchedule()
}
```

The SIGTERM'd job's `childTasks` closure still calls `recordExit`; the existing `guard job.state == .running` at the top of `recordExit` bails because the job is now `.waitingForNetwork`. No extra guard needed.

`buildSnapshot` in `+State.swift` — add `hostRateSummary: rateLimiter.displaySummary(now: dependencies.clock.now)` and `isOnline: isOnline` to the `QueueSnapshot(...)` literal, and change `queueHalt:` to `queueHalt: effectiveQueueHalt()`. Add:

```swift
func effectiveQueueHalt() -> QueueHaltReason? { queueHalt }   // Task 14 extends this
```

- [x] **Step 4: Run, verify pass** — the tests + full suite. `EngineHaltTests` (Phase 2 `.depMissing`) stays green.

  **Existing tests to update:**
  - `hasActiveJobs` — Task 13 also makes it count `.cooldown` / `.waitingForNetwork`. In `DownloadEngine.swift` `hasActiveJobs()`: `jobs.contains { $0.state == .running || $0.state == .probing || $0.state == .waitingForNetwork || isCooldownState($0.state) }`. Add `testHasActiveJobsCountsParkedStates` to `EngineIntentsTests` (or wherever `hasActiveJobs` is tested). This affects `QuitCoordinatorTests` — a `.cooldown` job now triggers the quit prompt (correct — pending work).

- [x] **Step 5: Lint** — regenerate; lint.

- [x] **Step 6: Hand off.**

---

## Task 14: Derived `queueHalt.circuitOpen` + `forceStart` override + `revalidate` split

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine+State.swift` (`effectiveQueueHalt` — replace the stub from Task 13)
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (`forceStart` accepts `.cooldown`; `revalidate` fix; `resetCircuit` / `resetAllCircuits`)
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` (protocol methods)
- Modify: `Sources/GrabberKit/App/QuitCoordinator.swift` (`quitConfirmation(halt:)` arms)
- Modify: `Tests/AppUnitTests/Support/AppFakes.swift` (`FakeEngine` conformance)
- Test: `Tests/GrabberKitTests/EngineCircuitTests.swift`

**Interfaces:**
- Consumes: `RateLimiter` (T5), engine state (T11–13).
- Produces:
  - `effectiveQueueHalt() -> QueueHaltReason?` — `.depMissing` (raw) → `.networkDown` (raw) → `.circuitOpen` when a circuit is open AND nothing is `.running`/`.probing` AND no `.queued` job could start → else nil
  - **`revalidate()` fixed:** `if queueHalt == .depMissing { queueHalt = nil }` — NOT `queueHalt = nil` (would clobber `.networkDown`). Still re-probes deps, still `guard report.isReadyForDownloads`.
  - `forceStart(_:)` — also accepts a `.cooldown` job (flips it to `.queued` + `cancelDeferral` first); starts it regardless of `blockedHostIDs`; eviction uses `effectiveCap` (T11); host `RateState` untouched; logs `hostBlockOverridden`
  - `resetCircuit(_ host: RateHost) async` / `resetAllCircuits() async` — reset via `RateLimiter`, log `circuitReset(host:byUser: true)` per host, then `afterRateReset()` (`bump` + `emitSnapshot` + `evaluateSchedule`). NOT `revalidate`.
  - `DownloadEngineProtocol` gains `func resetCircuit(_ host: RateHost) async` and `func resetAllCircuits() async`
  - `FakeEngine` (`AppFakes.swift`) gains no-op `resetCircuit` / `resetAllCircuits`
  - `QuitCoordinator.quitConfirmation(halt:)` gains `.networkDown` / `.circuitOpen` message arms

- [x] **Step 1: Failing test** — real harness. To advance a cooldown: `clock.advance(by: .seconds(N))` then `try? await Task.sleep(for: .milliseconds(20))` — `advance` resumes the `deferralTask` awaiting `clock.sleep(until:)`, which runs `fireDueDeferrals`. There is no engine "fire" seam.

```swift
@testable import GrabberKit
import TestSupport
import XCTest

final class EngineCircuitTests: XCTestCase {
    private typealias Fix = EngineFixture
    private let rl429 = FakeProcessRunner.Script.stderr("ERROR: HTTP Error 429: Too Many Requests", exitCode: 1)
    private func job(_ c: EventCollector, _ id: UUID) -> JobSnapshot? {
        c.latestSnapshot()?.jobs.first { $0.id == id }
    }
    private func isCooldown(_ s: JobState?) -> Bool { if case .cooldown = s { return true }; return false }

    private func circuitEngine(_ runner: FakeProcessRunner, _ probe: FakeMetadataProbe, _ clock: FakeClock, cap: Int = 1) -> DownloadEngine {
        Fix.engine(runner: runner, probe: probe, clock: clock, cap: cap,
                   tuning: EngineTuning.resolved(environment: [
                       "MG_CIRCUIT_STRIKE_THRESHOLD": "2", "MG_BACKOFF_LADDER": "1",
                   ]))
    }

    func testCircuitTripsAndSetsDerivedHalt() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1_000))
        let runner = FakeProcessRunner(); runner.script(rl429, forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe(); probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = circuitEngine(runner, probe, clock)
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))

        _ = await collector.waitForState(id) { self.isCooldown($0) }   // strike 1
        clock.advance(by: .seconds(2))
        try? await Task.sleep(for: .milliseconds(40))                  // retry → strike 2 → circuit
        try? await Task.sleep(for: .milliseconds(40))

        let snap = collector.latestSnapshot()!
        XCTAssertEqual(snap.queueHalt, .circuitOpen)
        XCTAssertEqual(snap.hostRateSummary.count, 1)
        XCTAssertEqual(job(collector, id)?.state, .queued, "circuit job stays .queued, not .cooldown")
    }

    func testResetAllCircuitsClears() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1_000))
        let runner = FakeProcessRunner()
        runner.scripts([rl429, rl429, FakeProcessRunner.Script(exitCode: 0)], forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe(); probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = circuitEngine(runner, probe, clock)
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { self.isCooldown($0) }
        clock.advance(by: .seconds(2)); try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(collector.latestSnapshot()?.queueHalt, .circuitOpen)

        await engine.resetAllCircuits()
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertNil(collector.latestSnapshot()?.queueHalt)
        _ = await collector.waitForState(id) { $0 == .completed }      // 3rd script completes
    }

    func testRevalidateDoesNotClearACircuit() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1_000))
        let runner = FakeProcessRunner(); runner.script(rl429, forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe(); probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = circuitEngine(runner, probe, clock)
        let collector = EventCollector(engine.events)
        let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
        _ = await collector.waitForState(id) { self.isCooldown($0) }
        clock.advance(by: .seconds(2)); try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(collector.latestSnapshot()?.queueHalt, .circuitOpen)

        await engine.revalidate()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(collector.latestSnapshot()?.queueHalt, .circuitOpen, "revalidate must not touch the circuit")
    }

    func testForceStartOverridesCooldownWithoutResettingHost() async {
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1_000))
        let runner = FakeProcessRunner()
        // 'a' (first launch) 429s; every later launch completes
        runner.scripts([rl429, FakeProcessRunner.Script(exitCode: 0)], forPathEndingIn: "yt-dlp")
        let probe = FakeMetadataProbe(); probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe, clock: clock, cap: 2)
        let collector = EventCollector(engine.events)
        let a = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=a"))
        let b = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=b"))
        _ = await collector.waitForState(a) { self.isCooldown($0) }

        await engine.forceStart(b)
        _ = await collector.waitForState(b) { $0 == .running || $0 == .completed }

        XCTAssertFalse(collector.latestSnapshot()!.hostRateSummary.isEmpty,
                       "host still cooling — force-start did not reset it")
    }
}
```

- [x] **Step 2: Run, verify fail.**

- [x] **Step 3: Implement**

`effectiveQueueHalt()` in `+State.swift` (replaces the `{ queueHalt }` stub):

```swift
func effectiveQueueHalt() -> QueueHaltReason? {
    if queueHalt == .depMissing { return .depMissing }
    if queueHalt == .networkDown { return .networkDown }
    guard !rateLimiter.circuitOpenHosts.isEmpty else { return nil }
    if jobs.contains(where: { $0.state == .running || $0.state == .probing }) { return nil }
    return startableQueuedJobExists() ? nil : .circuitOpen
}

private func startableQueuedJobExists() -> Bool {
    let now = dependencies.clock.now
    return jobs.contains {
        $0.state == .queued
            && !deferrals.contains(where: { d in d.id == $0.id })
            && !rateLimiter.blocked(host: RateHost(urlString: $0.request.url), now: now)
    }
}
```

The raw `queueHalt` field still drives the `evaluateSchedule` guard — a circuit does NOT hard-stop the pass; `blockedHostIDs` (T12) is what keeps circuit-host jobs from starting.

`revalidate()` in `DownloadEngine.swift` — change the one line:

```swift
public func revalidate() async {
    let report = await dependencies.envProbe.probe()
    guard report.isReadyForDownloads else { return }
    if queueHalt == .depMissing { queueHalt = nil }   // was: queueHalt = nil
    bump()
    emitSnapshot()
    evaluateSchedule()
}
```

`forceStart(_:)` — the current guard is `guard let forced = queuedJob(id) else { return }` (`.queued` only). Widen:

```swift
public func forceStart(_ id: UUID) async {
    guard let forced = jobs.first(where: { $0.id == id }),
          forced.state == .queued || isCooldownState(forced.state)
    else { return }

    let host = RateHost(urlString: forced.request.url)
    if rateLimiter.blocked(host: host, now: dependencies.clock.now) {
        logEvent(.hostBlockOverridden(host: host.canonical, jobID: id))
    }
    if isCooldownState(forced.state) {
        forced.state = .queued
        forced.cooldownUntil = nil
        cancelDeferral(id)
    }

    let victim = runningJobs().count >= effectiveCap ? oldestStartedRunningJob() : nil
    // … the rest of the existing forceStart body unchanged (move victim, move forced, start) …
}
```

(`isCooldownState` was added in Task 12. `effectiveCap` replaces the bare `cap` in the eviction check.)

`resetCircuit` / `resetAllCircuits`:

```swift
public func resetCircuit(_ host: RateHost) async {
    guard rateLimiter.circuitOpenHosts.contains(host) else { return }
    rateLimiter.resetCircuit(host: host)
    logEvent(.circuitReset(host: host.canonical, byUser: true))
    afterRateReset()
}

public func resetAllCircuits() async {
    let hosts = rateLimiter.circuitOpenHosts
    guard !hosts.isEmpty else { return }
    rateLimiter.resetAllCircuits()
    for host in hosts { logEvent(.circuitReset(host: host.canonical, byUser: true)) }
    afterRateReset()
}

private func afterRateReset() {
    bump()
    emitSnapshot()
    evaluateSchedule()
}
```

`DownloadEngineProtocol.swift` — add `func resetCircuit(_ host: RateHost) async` and `func resetAllCircuits() async` to the protocol.

`QuitCoordinator.swift` `quitConfirmation(halt:)` — currently `if halt == .depMissing { … } else { generic }`. Add:

```swift
let message: String
switch halt {
case .depMissing: message = /* existing depMissing text */
case .networkDown: message = "Downloads are paused — no internet connection. They'll resume when you're back online."
case .circuitOpen: message = "Downloads are paused — a site is rate-limiting you. Quit anyway?"
case nil: message = /* existing generic "a download is still running" */
}
```

- [x] **Step 4: Run, verify pass** — the five tests + full suite.

  **Existing tests to update:**
  - `Tests/AppUnitTests/Support/AppFakes.swift` — `FakeEngine` now fails to conform. Add:
    ```swift
    func resetCircuit(_: RateHost) async {}
    func resetAllCircuits() async {}
    ```
  - `EngineIntentsTests` / `EngineForceStartTests` — `forceStart` still starts a `.queued` job the same way; no assertion changes expected, but run them.
  - `QuitCoordinatorTests` — if a test builds a snapshot with `queueHalt: .depMissing` it still works; add a case for `.networkDown` / `.circuitOpen` message if the suite asserts message text.

- [x] **Step 5: Lint** — `forceStart` / `effectiveQueueHalt` risk `function_body_length` — the `startableQueuedJobExists` extraction covers `effectiveQueueHalt`; keep `forceStart`'s eviction in its existing shape.

- [x] **Step 6: Hand off.**

---

## Task 15: `--concurrent-fragments` gated on host state

**Files:**
- Modify: `Sources/GrabberKit/Download/YtDlpArguments.swift` (`build`)
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (`launchDownload` — pass the count)
- Test: `Tests/GrabberKitTests/YtDlpArgumentsTests.swift` + `Tests/GrabberKitTests/EngineRateLimitTests.swift`

**Interfaces:**
- Consumes: `RateLimiter.state(for:)` (T5), `EngineTuning.concurrentFragmentsNormal/Throttled` (T3).
- Produces: `YtDlpArguments.build` gains a **non-defaulted** `concurrentFragments: Int` param → appends `--concurrent-fragments <n>` to the args. Not sensitive → also appears verbatim in `redacted` output.

- [x] **Step 1: Failing test**

First read `YtDlpArgumentsTests.swift` to match its existing arg-assertion helper (it has one — reuse it, don't invent `hasFlagValue`). Then add:

```swift
func testConcurrentFragmentsAppended() {
    let args = YtDlpArguments.build(
        for: EngineFixture.request(), options: GlobalDownloadOptions(),
        tuning: .default, cookieArgument: nil, concurrentFragments: 4
    )
    // adjacent-pair assertion — match the suite's own helper
    let i = args.firstIndex(of: "--concurrent-fragments")
    XCTAssertNotNil(i)
    XCTAssertEqual(args[args.index(after: i!)], "4")
}
```

And in `EngineRateLimitTests.swift` — assert on `runner.launches` (the real property):

```swift
func testLaunchUsesThrottledFragmentsForCoolingHost() async {
    let clock = FakeClock(now: Date(timeIntervalSince1970: 1_000))
    let runner = FakeProcessRunner()
    runner.scripts([rl429, FakeProcessRunner.Script(exitCode: 0)], forPathEndingIn: "yt-dlp")
    let probe = FakeMetadataProbe(); probe.result(FakeMetadataProbe.success(title: "Clip"))
    let engine = Fix.engine(runner: runner, probe: probe, clock: clock, cap: 1,
                            tuning: EngineTuning.resolved(environment: ["MG_BACKOFF_LADDER": "1"]))
    let collector = EventCollector(engine.events)
    let id = await submitJob(engine, Fix.request(url: "https://youtube.com/watch?v=x"))
    _ = await collector.waitForState(id) { self.isCooldown($0) }
    clock.advance(by: .seconds(2))
    try? await Task.sleep(for: .milliseconds(60))   // retry launches while host still cooling

    // the yt-dlp launches: the retry (2nd) carries --concurrent-fragments 1
    let ytLaunches = runner.launches.filter { $0.executableURL.lastPathComponent == "yt-dlp" }
    XCTAssertGreaterThanOrEqual(ytLaunches.count, 2)
    let retryArgs = ytLaunches[1].arguments
    let ci = retryArgs.firstIndex(of: "--concurrent-fragments")!
    XCTAssertEqual(retryArgs[retryArgs.index(after: ci)], "1")

    // and the first launch (host was .normal) used 4
    let firstArgs = ytLaunches[0].arguments
    let fi = firstArgs.firstIndex(of: "--concurrent-fragments")!
    XCTAssertEqual(firstArgs[firstArgs.index(after: fi)], "4")
}
```

- [x] **Step 2: Run, verify fail.**

- [x] **Step 3: Implement**

`YtDlpArguments.build` — add `concurrentFragments: Int` (non-defaulted, after `cookieArgument:`). Append `["--concurrent-fragments", String(concurrentFragments)]` alongside the other pacing flags. `YtDlpArguments.redacted` (if it exists and re-derives) — thread the same value.

`DownloadEngine.launchDownload` — where it currently builds `YtDlpArguments.build(for:options:tuning:cookieArgument:)`, compute and pass:

```swift
let fragments = rateLimiter.state(for: RateHost(urlString: request.url)) == .normal
    ? dependencies.tuning.concurrentFragmentsNormal
    : dependencies.tuning.concurrentFragmentsThrottled
```

- [x] **Step 4: Run, verify pass** — tests + full suite. **Every existing `YtDlpArguments.build(` call site** (grep: `grep -rn 'YtDlpArguments.build' Sources/ Tests/`) needs `concurrentFragments:` — the param is non-defaulted so the compiler lists them all. Use `4` (the normal value) at test call sites unless the test is about throttling.

- [x] **Step 5: Lint** — regenerate; lint. `launchDownload` may tip `function_body_length` — hoist the `fragments` computation into a `private func fragmentCount(for url: String) -> Int`.

- [x] **Step 6: Hand off.**

---

## Task 16: `LogEvent` — the six new events

The real `LogEvent` accessor is **`key`** (verified `LogEvent.swift:44`), not `name`. Other accessors: `category` (44/73), `jobID` (91), `fields` (108). `DeferReason.hostCooldown` was added in Task 10.

**Files:**
- Modify: `Sources/GrabberKit/Logging/LogEvent.swift`
- Test: `Tests/GrabberKitTests/LogEventRateLimitTests.swift` (new — no phase number in the name)

**Interfaces:**
- Consumes: nothing new.
- Produces — `LogEvent` gains (each: a `key`, a `category` = `.scheduler`, a `fields` entry, and `jobID` where it has one):
  - `case hostRateStateChanged(host: String, from: String, to: String)` → key `"host.rate_state_changed"`, fields `{host, from, to}`
  - `case circuitOpened(host: String, strikes: Int)` → `"circuit.opened"`, fields `{host, strikes}`
  - `case circuitReset(host: String, byUser: Bool)` → `"circuit.reset"`, fields `{host, by_user}`
  - `case adaptiveConcurrencyChanged(from: Int, to: Int, reason: String)` → `"scheduler.adaptive_concurrency_changed"`, fields `{from, to, reason}`
  - `case networkPathChanged(online: Bool)` → `"network.path_changed"`, fields `{online}`
  - `case hostBlockOverridden(host: String, jobID: UUID)` → `"scheduler.host_block_overridden"`, fields `{host}`, `jobID` returns the id

- [x] **Step 1: Failing test** — `LogEventRateLimitTests.swift`:

```swift
@testable import GrabberKit
import XCTest

final class LogEventRateLimitTests: XCTestCase {
    func testCircuitOpenedFields() {
        let e = LogEvent.circuitOpened(host: "youtube", strikes: 4)
        XCTAssertEqual(e.key, "circuit.opened")
        XCTAssertEqual(e.fields["host"], "youtube")
        XCTAssertEqual(e.fields["strikes"], "4")
    }

    func testNetworkPathChangedFields() {
        XCTAssertEqual(LogEvent.networkPathChanged(online: false).fields["online"], "false")
    }

    func testCircuitResetByUser() {
        XCTAssertEqual(LogEvent.circuitReset(host: "youtube", byUser: true).fields["by_user"], "true")
    }

    func testAdaptiveConcurrencyChanged() {
        let e = LogEvent.adaptiveConcurrencyChanged(from: 4, to: 1, reason: "throttle")
        XCTAssertEqual(e.fields["from"], "4")
        XCTAssertEqual(e.fields["to"], "1")
        XCTAssertEqual(e.fields["reason"], "throttle")
    }

    func testHostBlockOverriddenCarriesJobID() {
        let id = UUID()
        XCTAssertEqual(LogEvent.hostBlockOverridden(host: "youtube", jobID: id).jobID, id)
    }

    func testDeferReasonHostCooldownFields() {
        let e = LogEvent.jobDeferred(id: UUID(), until: .now, reason: .hostCooldown(host: "youtube", strikes: 2))
        XCTAssertEqual(e.fields["reason"], "host_cooldown")
        XCTAssertEqual(e.fields["strikes"], "2")
    }
}
```

- [x] **Step 2: Run, verify fail.**

- [x] **Step 3: Add the cases** — in `enum LogEvent`, and in the `key` switch, the `category` switch, the `fields` switch, the `jobID` switch. Follow the existing `.jobDeferred` / `.jobForceStarted` pattern exactly. `DeferReason.hostCooldown` in `deferredFields` was done in Task 10 — confirm it is there.

- [x] **Step 4: Run, verify pass** — tests + full suite. `grep -rn 'switch.*LogEvent\|case .jobDeferred\|case .jobForceStarted' Sources/ Tests/` — any exhaustive `switch` over `LogEvent` without a `default` (e.g. in `LogWriter`, `EventCollector`, a diagnostics stub) needs the six new cases. `DeferReason` is also non-frozen — any exhaustive `switch` over it needs `.hostCooldown`.

- [x] **Step 5: Lint** — the switches grow; if `LogEvent.swift` trips `type_body_length`, move the `fields` computation to `LogEvent+Fields.swift`.

- [x] **Step 6: Hand off.**

---

## Task 17: `HealthController` + `ChipInteraction.popover`

**Files:**
- Create: `Sources/App/SiteNames.swift`
- Modify: `Sources/App/Chrome/HealthStrip.swift` (`ChipInteraction` → data, `PopoverKind`, `HealthChip.countdownUntil`, strip renders interaction)
- Create: `Sources/App/Chrome/HealthController.swift`
- Create: `Sources/App/Chrome/HostRatePopover.swift`
- Modify: `Sources/App/AppModel.swift` (own `HealthController`; `healthChips` delegates; `private(set) var hostRateSummary`; `resetCircuit` / `resetAllCircuits`)
- Test: `Tests/AppUnitTests/HealthControllerTests.swift`

**Interfaces:**
- Consumes: `QueueSnapshot.hostRateSummary` / `.isOnline` (T8, T13), `RateHost`, `HostRateDisplayState`, `RateState`, `CountdownFormat` (T6), engine `resetCircuit` / `resetAllCircuits` (T14).
- Produces:
  - `enum SiteNames { static func display(_ canonical: String) -> String }` — keyed by `RateHost.canonical` (`"youtube" → "YouTube"`, `"vimeo.com" → "Vimeo"`, `"archive.org" → "Internet Archive"`, else the canonical string). **Not** `RowModel.siteMap` (keyed by extractor — leave it alone).
  - `enum ChipInteraction: Equatable { case none; case refresh; case popover(PopoverKind) }` — **no closures** (a closure rebuilt each `update` churns SwiftUI identity). Phase 7's `.refresh` becomes payload-free too; the strip view dispatches to `AppModel`.
  - `enum PopoverKind: Equatable { case hostRate }`
  - `HealthChip` gains `let countdownUntil: Date?` — the cooldown chip carries its deadline as **data**; the strip view renders the live `m:ss` via `TimelineView`. The chip's `label` is `"YouTube"` / `"2 sites cooling down"` / `"YouTube — paused"` — no baked countdown.
  - `@MainActor @Observable final class HealthController { private(set) var chips: [HealthChip]; func update(snapshot: QueueSnapshot, now: Date) }`
  - `AppModel.healthChips` → `healthController.chips`; `AppModel` gains `private(set) var hostRateSummary: [RateHost: HostRateDisplayState] = [:]` (set in `runConsumer` from each snapshot — the popover reads it).
  - `AppModel.resetCircuit(host: RateHost) async` / `AppModel.resetAllCircuits() async` → call the engine
  - `HostRatePopover` view — `@Environment(AppModel.self)`, reads `appModel.hostRateSummary`, dispatches `resetCircuit` / `resetAllCircuits` via `Task`

- [x] **Step 1: Failing test**

`Tests/AppUnitTests/HealthControllerTests.swift`:

```swift
@testable import MediaGrabber
@testable import GrabberKit
import XCTest

@MainActor
final class HealthControllerTests: XCTestCase {
    private func snapshot(online: Bool, summary: [RateHost: HostRateDisplayState]) -> QueueSnapshot {
        QueueSnapshot(jobs: [], revision: 1, queueHalt: nil, generatedAt: .now,
                      hostRateSummary: summary, isOnline: online)
    }

    func testOnlineChipAlwaysPresent() {
        let c = HealthController()
        c.update(snapshot: snapshot(online: true, summary: [:]), now: .now)
        XCTAssertEqual(c.chips.count, 1)
        XCTAssertEqual(c.chips[0].label, "online")
    }

    func testOfflineChipLabel() {
        let c = HealthController()
        c.update(snapshot: snapshot(online: false, summary: [:]), now: .now)
        XCTAssertEqual(c.chips[0].label, "offline")
    }

    func testCooldownChipAppearsWithSummary() {
        let yt = RateHost(urlString: "https://youtube.com/x")
        let now = Date(timeIntervalSince1970: 1_000)
        let summary = [yt: HostRateDisplayState(
            state: .cooldown(until: now.addingTimeInterval(134), strikes: 1),
            lastErrorKey: "rate_limited", concurrencyReducedToOne: true
        )]
        let c = HealthController()
        c.update(snapshot: snapshot(online: true, summary: summary), now: now)
        XCTAssertEqual(c.chips.count, 2)
        let cooldown = c.chips[1]
        XCTAssertEqual(cooldown.label, "YouTube — 2:14")
        XCTAssertEqual(cooldown.interaction, .popover(.hostRate))
    }

    func testMultipleHostsCollapseToOneChip() {
        let a = RateHost(urlString: "https://youtube.com/x")
        let b = RateHost(urlString: "https://vimeo.com/1")
        let now = Date(timeIntervalSince1970: 1_000)
        let ds = HostRateDisplayState(state: .cooldown(until: now.addingTimeInterval(60), strikes: 1), lastErrorKey: nil, concurrencyReducedToOne: false)
        let c = HealthController()
        c.update(snapshot: snapshot(online: true, summary: [a: ds, b: ds]), now: now)
        XCTAssertEqual(c.chips.count, 2)
        XCTAssertEqual(c.chips[1].label, "2 sites cooling down")
    }

    func testCircuitOpenChipLabel() {
        let yt = RateHost(urlString: "https://youtube.com/x")
        let now = Date(timeIntervalSince1970: 1_000)
        let summary = [yt: HostRateDisplayState(state: .circuitOpen(since: now, strikes: 4), lastErrorKey: "rate_limited", concurrencyReducedToOne: true)]
        let c = HealthController()
        c.update(snapshot: snapshot(online: true, summary: summary), now: now)
        XCTAssertEqual(c.chips[1].label, "YouTube — paused")
    }
}
```

The `testCooldownChipAppearsWithSummary` label assertion changes to `"YouTube"` (no baked countdown) — the countdown is a `TimelineView` on `chip.countdownUntil` in the strip. Update that test: `XCTAssertEqual(cooldown.label, "YouTube")` and `XCTAssertEqual(cooldown.countdownUntil, now.addingTimeInterval(134))`.

- [x] **Step 2: Run, verify fail.**

- [x] **Step 3: Implement**

`Sources/App/SiteNames.swift`:

```swift
enum SiteNames {
    static func display(_ canonical: String) -> String {
        names[canonical] ?? canonical
    }

    private static let names = [
        "youtube": "YouTube",
        "vimeo.com": "Vimeo",
        "archive.org": "Internet Archive",
    ]
}
```

`HealthStrip.swift` — `ChipInteraction` becomes data, `HealthChip` gains `countdownUntil`:

```swift
enum ChipInteraction: Equatable {
    case none
    case refresh
    case popover(PopoverKind)
}

enum PopoverKind: Equatable {
    case hostRate
}

struct HealthChip: Identifiable {
    let id: String
    let label: String
    let dot: DotState
    let interaction: ChipInteraction
    var countdownUntil: Date? = nil
}
```

The strip's `chipView` — extract the existing pill body into `chipLabel(_:)`, then:

```swift
@Environment(AppModel.self) private var appModel
@State private var openPopoverID: String?

private func chipView(_ chip: HealthChip) -> some View {
    let body = Group {
        if let until = chip.countdownUntil {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                chipLabel(chip, suffix: " — \(CountdownFormat.mmss(until: until, now: ctx.date))")
            }
        } else {
            chipLabel(chip, suffix: "")
        }
    }
    switch chip.interaction {
    case .popover:
        return AnyView(
            Button { openPopoverID = chip.id } label: { body }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(
                    get: { openPopoverID == chip.id },
                    set: { if !$0 { openPopoverID = nil } }
                )) { HostRatePopover() }
        )
    case .none, .refresh:
        return AnyView(body)
    }
}
```

(`chipLabel` gains a `suffix: String` param appended to the `Text`. `.refresh` is unreachable in Phase 6 — Phase 7 wires it.)

`HealthController.swift`:

```swift
import Foundation
import GrabberKit
import Observation

@MainActor
@Observable
final class HealthController {
    private(set) var chips: [HealthChip] = []

    func update(snapshot: QueueSnapshot, now: Date) {
        var next: [HealthChip] = [onlineChip(snapshot.isOnline)]
        if let cooldown = hostRateChip(snapshot.hostRateSummary) {
            next.append(cooldown)
        }
        chips = next
    }

    private func onlineChip(_ online: Bool) -> HealthChip {
        HealthChip(id: "online", label: online ? "online" : "offline",
                   dot: online ? .ok : .attention, interaction: .none)
    }

    private func hostRateChip(_ summary: [RateHost: HostRateDisplayState]) -> HealthChip? {
        guard !summary.isEmpty else { return nil }
        if summary.count == 1, let (host, ds) = summary.first {
            return oneHostChip(host, ds)
        }
        return HealthChip(id: "host-rate", label: "\(summary.count) sites cooling down",
                          dot: .attention, interaction: .popover(.hostRate))
    }

    private func oneHostChip(_ host: RateHost, _ ds: HostRateDisplayState) -> HealthChip {
        let name = SiteNames.display(host.canonical)
        switch ds.state {
        case let .cooldown(until, _):
            return HealthChip(id: "host-rate", label: name, dot: .attention,
                              interaction: .popover(.hostRate), countdownUntil: until)
        case .circuitOpen:
            return HealthChip(id: "host-rate", label: "\(name) — paused", dot: .attention,
                              interaction: .popover(.hostRate))
        case .normal:
            return HealthChip(id: "host-rate", label: name, dot: .attention,
                              interaction: .popover(.hostRate))
        }
    }
}
```

`HostRatePopover.swift` — `@Environment(AppModel.self)`, reads `appModel.hostRateSummary`:

```swift
import GrabberKit
import SwiftUI

struct HostRatePopover: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let summary = appModel.hostRateSummary
        VStack(alignment: .leading, spacing: Spacing.s2) {
            ForEach(summary.keys.sorted(by: { $0.canonical < $1.canonical }), id: \.self) { host in
                if let ds = summary[host] { row(host, ds) }
            }
            if summary.values.contains(where: isCircuitOpen) {
                Button("Retry all") { Task { await appModel.resetAllCircuits() } }
            }
        }
        .padding(Spacing.s3)
        .frame(minWidth: 240)
    }

    private func row(_ host: RateHost, _ ds: HostRateDisplayState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(SiteNames.display(host.canonical)).font(.headline)
            detailText(ds)
            if isCircuitOpen(ds) {
                Button("Retry now") { Task { await appModel.resetCircuit(host: host) } }
            }
        }
    }

    @ViewBuilder
    private func detailText(_ ds: HostRateDisplayState) -> some View {
        let suffix = ds.concurrencyReducedToOne ? " · concurrency reduced to 1" : ""
        switch ds.state {
        case let .cooldown(until, _):
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text("Cooling down — \(CountdownFormat.mmss(until: until, now: ctx.date))\(suffix)")
            }
        case .circuitOpen:
            Text("Rate-limited — paused\(suffix)")
        case .normal:
            EmptyView()
        }
    }

    private func isCircuitOpen(_ ds: HostRateDisplayState) -> Bool {
        if case .circuitOpen = ds.state { return true }
        return false
    }
}
```

`AppModel.swift`:

```swift
let healthController = HealthController()
private(set) var hostRateSummary: [RateHost: HostRateDisplayState] = [:]

var healthChips: [HealthChip] { healthController.chips }

func resetCircuit(host: RateHost) async { await engine.resetCircuit(host) }
func resetAllCircuits() async { await engine.resetAllCircuits() }
```

In `runConsumer`, in the `.snapshot(snapshot)` branch (alongside the existing `applySnapshot(snapshot)`):

```swift
hostRateSummary = snapshot.hostRateSummary
healthController.update(snapshot: snapshot, now: .now)
```

Delete the old `var healthChips: [HealthChip] { [HealthChip(id: "online", …)] }` body — it becomes the delegating one above.

- [x] **Step 4: Run, verify pass** — `HealthControllerTests` + full `AppUnitTests`. `AppModelTests` may assert the old static `healthChips` — update it to drive a snapshot through `runConsumer` and check `healthController.chips`.

- [x] **Step 5: Lint** — `hostRateChip` / `oneHostChip` `cyclomatic_complexity` — the split above keeps each under 10. `HealthStrip.chipView`'s `AnyView` branches — acceptable; if `void_function_in_ternary` trips on `detailText`'s `switch`, add `return`s.

- [x] **Step 6: Hand off.**

---

## Task 18: `BannerReason` resolver + `WarningBanner` optional button + `MainWindow` inset

**Files:**
- Create: `Sources/App/Chrome/BannerResolver.swift`
- Modify: `Sources/App/Chrome/WarningBanner.swift` (`BannerContent` optional button; publish height)
- Modify: `Sources/App/AppModel.swift` (`bannerContent` from the resolver)
- Modify: `Sources/App/MainWindow.swift` (bottom inset)
- Test: `Tests/AppUnitTests/BannerResolverTests.swift`

**Interfaces:**
- Consumes: `QueueSnapshot.queueHalt` / `.hostRateSummary` (T8, T13), `SiteNames.display` (T17), `AppModel.resetAllCircuits` (T17).
- Produces:
  - `enum BannerReason: Equatable { case depMissing; case networkDown; case circuitOpen }` — Phase 7 adds `.potProviderDown`
  - `func resolveBanner(_ active: Set<BannerReason>) -> BannerReason?` — an **explicit** priority list `[.depMissing, .networkDown, .circuitOpen]`, `first(where: active.contains)`
  - `func bannerCopy(for reason: BannerReason, circuitHosts: [String], onRetry: @escaping @Sendable () async -> Void) -> BannerContent?` — named `bannerCopy` NOT `bannerContent` (that is the `AppModel` property). Returns nil for `.depMissing` (onboarding takeover owns it).
  - `struct BannerContent { let text: String; let buttonTitle: String?; let action: (@Sendable () async -> Void)? }` — button + action optional
  - `WarningBanner` renders the button only when both `buttonTitle` and `action` are non-nil
  - `MainWindow` applies a bottom safe-area inset equal to the banner's measured height (+ `Spacing.s4`) on `page` when a banner shows

- [x] **Step 1: Failing test**

`Tests/AppUnitTests/BannerResolverTests.swift`:

```swift
@testable import MediaGrabber
import XCTest

final class BannerResolverTests: XCTestCase {
    func testPriorityOrder() {
        XCTAssertEqual(resolveBanner([.depMissing, .networkDown, .circuitOpen]), .depMissing)
        XCTAssertEqual(resolveBanner([.networkDown, .circuitOpen]), .networkDown)
        XCTAssertEqual(resolveBanner([.circuitOpen]), .circuitOpen)
        XCTAssertNil(resolveBanner([]))
    }

    func testDepMissingHasNoBannerCopy() {
        XCTAssertNil(bannerCopy(for: .depMissing, circuitHosts: []) {})
    }

    func testNetworkDownCopyHasNoButton() {
        let c = bannerCopy(for: .networkDown, circuitHosts: []) {}
        XCTAssertNil(c?.buttonTitle)
        XCTAssertNil(c?.action)
        XCTAssertEqual(c?.text.contains("No internet"), true)
    }

    func testCircuitOpenCopyHasRetryButton() {
        let c = bannerCopy(for: .circuitOpen, circuitHosts: ["YouTube"]) {}
        XCTAssertEqual(c?.buttonTitle, "Retry now")
        XCTAssertNotNil(c?.action)
        XCTAssertEqual(c?.text.contains("YouTube"), true)
    }

    func testCircuitOpenMultipleHostsCopy() {
        let c = bannerCopy(for: .circuitOpen, circuitHosts: ["YouTube", "Vimeo"]) {}
        XCTAssertEqual(c?.text.contains("2 sites"), true)
    }
}
```

- [x] **Step 2: Run, verify fail.**

- [x] **Step 3: Implement**

`BannerResolver.swift`:

```swift
import Foundation

enum BannerReason: Equatable {
    case depMissing
    case networkDown
    case circuitOpen
}

private let bannerPriority: [BannerReason] = [.depMissing, .networkDown, .circuitOpen]

func resolveBanner(_ active: Set<BannerReason>) -> BannerReason? {
    bannerPriority.first(where: active.contains)
}

func bannerCopy(
    for reason: BannerReason,
    circuitHosts: [String],
    onRetry: @escaping @Sendable () async -> Void
) -> BannerContent? {
    switch reason {
    case .depMissing:
        return nil // handled by the onboarding takeover, not a banner
    case .networkDown:
        return BannerContent(
            text: "No internet connection — downloads paused. They'll resume automatically.",
            buttonTitle: nil, action: nil
        )
    case .circuitOpen:
        let subject = circuitHosts.count == 1
            ? "Downloads from \(circuitHosts[0])"
            : "\(circuitHosts.count) sites"
        return BannerContent(
            text: "\(subject) keep getting rate-limited. Wait a while, add browser cookies in Preferences, or turn off a VPN.",
            buttonTitle: "Retry now",
            action: onRetry
        )
    }
}
```

`WarningBanner.swift` — `BannerContent`:

```swift
struct BannerContent {
    let text: String
    let buttonTitle: String?
    let action: (@Sendable () async -> Void)?
}
```

In `body`, render the `Button` only `if let title = content.buttonTitle, let action = content.action`. Add a height report:

```swift
.background(GeometryReader { proxy in
    Color.clear.preference(key: BannerHeightKey.self, value: proxy.size.height)
})
```

with `struct BannerHeightKey: PreferenceKey { static var defaultValue: CGFloat = 0; static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() } }`.

`AppModel.swift` — `bannerContent` (the `@Observable` property) is set from a `recomputeBanner`, called in `runConsumer`'s `.snapshot` branch:

```swift
private func recomputeBanner(_ snapshot: QueueSnapshot) {
    var active: Set<BannerReason> = []
    switch snapshot.queueHalt {
    case .depMissing: active.insert(.depMissing)
    case .networkDown: active.insert(.networkDown)
    case .circuitOpen: active.insert(.circuitOpen)
    case nil: break
    }
    guard let reason = resolveBanner(active) else { bannerContent = nil; return }
    let hosts = snapshot.hostRateSummary
        .filter { if case .circuitOpen = $0.value.state { return true }; return false }
        .keys
        .map { SiteNames.display($0.canonical) }
        .sorted()
    bannerContent = bannerCopy(for: reason, circuitHosts: hosts) { [weak self] in
        await self?.resetAllCircuits()
    }
}
```

`SiteNames` is created in Task 17. `runConsumer`'s `.snapshot(snapshot)` branch now does: `applySnapshot(snapshot)` (existing) + `hostRateSummary = snapshot.hostRateSummary` (T17) + `healthController.update(...)` (T17) + `recomputeBanner(snapshot)`.

**`applySnapshot`** (existing, `AppModel.swift:308`) currently sets `needsOnboarding = true` on `.depMissing`. Leave that; `recomputeBanner` is additive.

`MainWindow.swift` — capture the height and inset the page:

```swift
@State private var bannerHeight: CGFloat = 0

// in the ZStack:
WarningBanner(content: appModel.bannerContent)
    .onPreferenceChange(BannerHeightKey.self) { bannerHeight = $0 }

// the page:
page
    .safeAreaInset(edge: .bottom, spacing: 0) {
        Color.clear.frame(height: appModel.bannerContent == nil ? 0 : bannerHeight + Spacing.s4)
    }
```

- [x] **Step 4: Run, verify pass** — `BannerResolverTests` + full `AppUnitTests`.

- [x] **Step 5: Lint** — `recomputeBanner` `cyclomatic_complexity` — extract the `queueHalt → Set<BannerReason>` map into `private func activeBannerReasons(_:) -> Set<BannerReason>`.

- [x] **Step 6: Hand off.**

---

## Task 19: Status text + `RowStore` threading + Status cell countdown

**The Status cell renders `TablePresentation.statusDisplay(for:)` (verified `DownloadRow.swift:51`), NOT `row.statusText`.** `RowModel.statusText` (from `RowModel.status(for:)`) is used for: the `.failed` copy that `statusDisplay` reuses, and the status **filter value** (`RowStore.filterValue`, `RowStore.swift:206`). So this task touches BOTH — one shared prefix function feeding both, `statusDisplay` gets the lowercase form + the cell adds the live countdown.

**Files:**
- Create: `Sources/App/Rows/RowStatusText.swift` — `enum RowStatusText { static func text(for: JobSnapshot, maxAutoRetries: Int, rate: HostRateDisplayState?) -> String }` (the semantic prefix, Title-case, no countdown)
- Modify: `Sources/App/Rows/RowModel.swift` — `status(for:)` delegates to `RowStatusText.text`; `patch` takes a `rate:` arg; store `private(set) var rateDisplay: HostRateDisplayState?` + `var hostCooldownDeadline: Date?` computed
- Modify: `Sources/App/Table/TablePresentation.swift` — `statusDisplay(for:)` gains the cooling / circuit / retrying prefixes (lowercase)
- Modify: `Sources/App/Rows/RowStore.swift` — carry `snapshot.hostRateSummary` into every `RowModel.init` / `.patch`; the status filter value uses the new prefix
- Modify: `Sources/App/Table/DownloadRow.swift` — wrap `statusDisplay` output in `TimelineView` + `CountdownFormat.mmss` when a future deadline exists
- Test: `Tests/AppUnitTests/RowModelStatusTests.swift`, `RowStoreTests.swift`, `DownloadsTableTests.swift`

**Interfaces:**
- Consumes: `JobSnapshot.rateHost` / `.cooldownUntil` (T8), `QueueSnapshot.hostRateSummary` (T8), `RateState`, `HostRateDisplayState`, `CountdownFormat` (T6).
- Produces:
  - `RowStatusText.text(for:maxAutoRetries:rate:)` — the prefix table from spec §7.4
  - `RowModel.rateDisplay: HostRateDisplayState?` (last patched), `RowModel.hostCooldownDeadline: Date?`
  - `RowModel.patch(_ next: JobSnapshot, queuePosition: Int?, maxAutoRetries: Int = 5, rate: HostRateDisplayState? = nil) -> Bool` — new trailing arg
  - `TablePresentation.statusDisplay(for:)` renders the new prefixes (lowercase)
  - Status cell wraps in `TimelineView` when there is a future deadline

- [x] **Step 1: Failing test** — `RowStatusTextTests.swift` (new):

```swift
@testable import MediaGrabber
@testable import GrabberKit
import XCTest

final class RowStatusTextTests: XCTestCase {
    private func snap(_ state: JobState, host: String = "https://youtube.com/x",
                      cooldownUntil: Date? = nil, attempt: Int = 0) -> JobSnapshot {
        JobSnapshot(
            id: UUID(), url: host, rateHost: RateHost(urlString: host),
            title: "Clip", state: state, progress: nil, kind: .video(maxHeight: 1080),
            durationSeconds: nil, extractor: nil, addedAt: .now, finishedAt: nil,
            destFolder: URL(fileURLWithPath: "/tmp"), outputFiles: [], sizeBytes: nil,
            actualQuality: nil, attempt: attempt, cooldownUntil: cooldownUntil,
            playerClientUsed: nil, playlistGroupID: nil, integrityVerdict: nil, availableActions: []
        )
    }
    private let now = Date(timeIntervalSince1970: 1_000)
    private func cooling(_ secs: TimeInterval) -> HostRateDisplayState {
        HostRateDisplayState(state: .cooldown(until: now.addingTimeInterval(secs), strikes: 1),
                             lastErrorKey: "rate_limited", concurrencyReducedToOne: true)
    }
    private let open = HostRateDisplayState(state: .circuitOpen(since: Date(timeIntervalSince1970: 1_000), strikes: 4),
                                            lastErrorKey: nil, concurrencyReducedToOne: true)

    func testCooldownStateJob() {
        XCTAssertEqual(RowStatusText.text(for: snap(.cooldown(until: now.addingTimeInterval(60)),
                                                    cooldownUntil: now.addingTimeInterval(60)),
                                          maxAutoRetries: 5, rate: nil), "Cooling down")
    }
    func testCoolingHostQueuedJob() {
        XCTAssertEqual(RowStatusText.text(for: snap(.queued), maxAutoRetries: 5, rate: cooling(60)),
                       "Cooling down")
    }
    func testCircuitOpenHostQueuedJob() {
        XCTAssertEqual(RowStatusText.text(for: snap(.queued), maxAutoRetries: 5, rate: open),
                       "Rate-limited — paused")
    }
    func testBackoffQueuedJob() {
        XCTAssertEqual(RowStatusText.text(for: snap(.queued, cooldownUntil: now.addingTimeInterval(60), attempt: 2),
                                          maxAutoRetries: 5, rate: nil), "Retrying")
    }
    func testPlainQueued() {
        XCTAssertEqual(RowStatusText.text(for: snap(.queued), maxAutoRetries: 5, rate: nil), "Queued")
    }
    func testWaitingForNetwork() {
        XCTAssertEqual(RowStatusText.text(for: snap(.waitingForNetwork), maxAutoRetries: 5, rate: nil),
                       "Waiting for network")
    }
}
```

- [x] **Step 2: Run, verify fail.**

- [x] **Step 3: Implement**

`RowStatusText.swift`:

```swift
import Foundation
import GrabberKit

enum RowStatusText {
    static func text(for snapshot: JobSnapshot, maxAutoRetries: Int, rate: HostRateDisplayState?) -> String {
        switch snapshot.state {
        case .cooldown: return "Cooling down"
        case .waitingForNetwork: return "Waiting for network"
        case .queued: return queued(snapshot, rate: rate)
        case .probing: return "Resolving…"
        case .running:
            return snapshot.progress.map { "Downloading \(Int($0.fraction * 100))%" } ?? "Downloading"
        case .paused: return "Paused"
        case .completed: return "Saved"
        case .cancelled: return "Cancelled"
        case let .failed(errorClass): return "Failed — \(errorClass.presentation.sentence)"
        }
    }

    private static func queued(_ snapshot: JobSnapshot, rate: HostRateDisplayState?) -> String {
        if case .circuitOpen = rate?.state { return "Rate-limited — paused" }
        if case .cooldown = rate?.state { return "Cooling down" }
        if snapshot.attempt > 0, let until = snapshot.cooldownUntil, until > .now { return "Retrying" }
        return "Queued"
    }
}
```

`RowModel.swift` — `status(for:maxAutoRetries:)` becomes `status(for:maxAutoRetries:rate:)` delegating to `RowStatusText.text`. Add `private(set) var rateDisplay: HostRateDisplayState?`. `patch` gains `rate: HostRateDisplayState? = nil` — set `self.rateDisplay = rate`, and recompute `statusText` when `stateChanged || rateChanged || (attempt/cooldownUntil changed) || retriesChanged` where `rateChanged = self.rateDisplay != rate` (compare before assigning). Add:

```swift
var hostCooldownDeadline: Date? {
    if case let .cooldown(until, _) = rateDisplay?.state { return until }
    return nil
}
```

`patchProgress` — pass the stored `rateDisplay` when it recomputes `statusText`.

`TablePresentation.statusDisplay(for:)` — currently a `switch` over `row.snapshot.state`. Replace the `.queued` / `.cooldown` / `.waitingForNetwork` arms with a call to a lowercase-mapped `RowStatusText.text(for: row.snapshot, maxAutoRetries: <the row's>, rate: row.rateDisplay).lowercased()` — or simpler, mirror the arms:

```swift
static func statusDisplay(for row: RowModel) -> String {
    if row.snapshot.state == .queued, let badge = row.queueBadge,
       row.rateDisplay == nil, row.snapshot.attempt == 0 {
        return "queued · \(badge)"
    }
    switch row.snapshot.state {
    case .queued:
        if case .circuitOpen = row.rateDisplay?.state { return "rate-limited — paused" }
        if case .cooldown = row.rateDisplay?.state { return "cooling down" }
        if row.snapshot.attempt > 0 { return "retrying" }
        return "queued"
    case .probing: return "probing"
    case .running: return "downloading"
    case .paused: return "paused"
    case .waitingForNetwork: return "waiting for network"
    case .cooldown: return "cooling down"
    case .completed: return "saved"
    case .cancelled: return "cancelled"
    case .failed:
        return row.statusText.replacingOccurrences(of: "Failed — ", with: "")
    }
}
```

`RowStore.swift` — in `applySnapshot`, capture `let summary = snapshot.hostRateSummary` and pass `rate: summary[job.rateHost]` into every `RowModel(...)` init and `existing.patch(...)`. `filterValue` line 206 (`case .status: row.statusText`) — leave as `row.statusText` (it now reflects the prefix). `RowStore` needs no signature change (it already receives the whole `QueueSnapshot`).

`DownloadRow.swift` — the Status cell (`statusCell`, currently `Text(TablePresentation.statusDisplay(for: row))`):

```swift
private var statusCell: some View {
    let deadline = row.snapshot.cooldownUntil ?? row.hostCooldownDeadline
    return HStack(spacing: Spacing.s1) {
        Circle()
            .fill(RowStatusStyle.dotColor(for: row.snapshot.state, palette: theme.palette))
            .frame(width: 6, height: 6)
        if let deadline, deadline > .now {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text("\(TablePresentation.statusDisplay(for: row)) — \(CountdownFormat.mmss(until: deadline, now: ctx.date))")
                    .font(theme.monoFont(11, .medium))
                    .foregroundStyle(RowStatusStyle.textColor(for: row.snapshot.state, palette: theme.palette))
                    .lineLimit(1)
            }
        } else {
            Text(TablePresentation.statusDisplay(for: row))
                .font(theme.monoFont(11, .medium))
                .foregroundStyle(RowStatusStyle.textColor(for: row.snapshot.state, palette: theme.palette))
                .lineLimit(1)
        }
    }
    .padding(.horizontal, Spacing.s2)
}
```

(Extract the styled `Text` into a small `@ViewBuilder func statusText(_ s: String)` to avoid the duplication and `void_function_in_ternary`.)

- [x] **Step 4: Run, verify pass** — `RowStatusTextTests` + `RowModelStatusTests` + `RowStoreTests` + `DownloadsTableTests` + full `AppUnitTests`.

  **Existing tests to update:**
  - `RowModelStatusTests.swift` — the `"Retrying — attempt N of M"` assertion: the prefix is now `"Retrying"` (the count moves to the live countdown per spec §7.4). Change the expectation to `"Retrying"`. Any test calling `RowModel.status(for:maxAutoRetries:)` needs the `rate:` arg (defaulted nil — so only tests asserting the new behavior change).
  - `DownloadsTableTests.swift` — `statusDisplay` for a `.cooldown` row now returns `"cooling down"` (unchanged) but a `.queued` row whose host is circuit-open returns `"rate-limited — paused"` — add/adjust if the suite covers cooldown.
  - `RowStoreTests.swift` — if a test builds a `QueueSnapshot` it now needs `hostRateSummary: [:]` (Task 8 grep covered this).

- [x] **Step 5: Lint** — `RowStatusText.text` / `statusDisplay` `cyclomatic_complexity` — the `queued(_:rate:)` extraction covers `RowStatusText`; `statusDisplay`'s `.queued` arm may need its own `private static func queuedDisplay(_ row: RowModel) -> String`.

- [x] **Step 6: Hand off.**

---

## Task 20: Final verification + spec sync

**Files:**
- Modify: `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` (§5.2, §5.6, §7.4, §7.6, §7.8, §12.1, §12.2)
- Modify: `docs/superpowers/specs/2026-09-04-media-grabber-phase-6.md` (header, §3.2, §4, §5.2, §6.3, §7.1, §7.4, §7.5, §9 — see Step 5)
- Create: nothing.

**Interfaces:** none — docs + a full verification pass.

**Prerequisite:** Tasks 0–19 all handed off and their tests green.

- [x] **Step 1: Run the full test suite once more**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`
Expected: all green.

- [x] **Step 2: Run lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean.

- [x] **Step 3: Build and launch the app**

Run: `make`
Expected: app builds, launches. Paste an `archive.org` URL, confirm a normal download still works (no regression).

- [x] **Step 4: Update the parent design spec** — apply every bullet from the Phase 6 spec's §11 "Parent design spec updates" list:
  - §5.2 — offline indicator is passive, no re-poll control
  - §5.6 — force-start overrides a host cooldown/circuit for the single forced job without clearing `RateState`, still respects the concurrency cap
  - §7.4 — reword to the shipped design (per-host `RateState`, `RateHost` key with YouTube fold, cooldown ladder reusing `Backoff` on the host strike count, per-host circuit tripping on `circuitStrikeThreshold` consecutive strikes including terminal ones, user-only recovery, one global adaptive cap, probes gated on host state)
  - §7.6 — `--concurrent-fragments` is 4 when host `RateState == .normal`, 1 otherwise, `tuning`-controlled, read at spawn
  - §7.8 — `NetworkMonitor` debounced, no reachability probe, single engine-owned subscription publishing `QueueSnapshot.isOnline`, queued jobs stay queued / running jobs park, staleness is a chip (Phase 10) never a banner
  - §12.1 Phase 6 — rewrite the stub to the shipped scope; move engine-freshness chip to Phase 10; note the per-host adaptive-concurrency backlog deferral
  - §12.1 Phase 10 — add the engine-freshness `HealthStrip` chip (Phase 10 emits it from `HealthController`, no Phase 6 slot); staleness is a chip not a banner
  - §12.2 shell table — update the Scheduler loop / `queueHalt` / `JobSnapshot` (note the deliberate `rateHost` struct-edit exception) / `WarningBanner` (priority resolver, optional button) / `HealthStrip` (`HealthController` + online + cooldown chips + `.popover`, strip renders interaction) rows

  **No changelog framing** — state the target design as fact. No "was X now Y", no "Phase 6 changed", no edit tallies. Each §-update rewrites the section to read as the current plan.

- [x] **Step 5: Sync the Phase 6 spec to the implemented signatures** — `docs/superpowers/specs/2026-09-04-media-grabber-phase-6.md`:
  - **Header** — change "Plan: not yet written" to "Plan: `docs/superpowers/plans/2026-09-04-media-grabber-phase-6.md`".
  - **§3.2** — `RatePolicy.next` gains a `jitter:` param (needed so `Backoff.delay`'s jitter is deterministic in tests). Signature: `next(state:event:now:tuning:jitter:)`.
  - **§4** — `RateLimiter.recordStrike` gains `lastErrorKey: String` (feeds `HostRateDisplayState.lastErrorKey`). `displaySummary` takes `now:` (needed to drop expired cooldowns). Add `concurrencyReducedByStrike` to the listed API. `HostRateDisplayState` gains `concurrencyReducedToOne: Bool`.
  - **§6.3** — `QueueSnapshot.isOnline` is set by the engine's debounced monitor (already in the spec); confirm `hostRateSummary` is `[RateHost: HostRateDisplayState]`.
  - **§9** — `DeferReason.hostCooldown` lives in `SubmitResult.swift` (where `DeferReason` is defined), not `LogEvent.swift`. The `LogEvent` accessor is `key`, not `name`. Add `hostBlockOverridden(host:jobID:)` to the event list.
  - **§5.2 / §7.5** — the "one `.cooldown` job per host" rule: only the job whose exit caused the *current* strike enters `.cooldown`; if another job for that host already holds `.cooldown`, this one stays `.queued` (gated by `blockedHostIDs`).
  - **§7.1** — `HealthChip` carries the deadline as data (`countdownUntil: Date?`); the strip renders the live countdown, `HealthController` does not bake it into `label`. `ChipInteraction` is closure-free; actions dispatch through `AppModel`.
  - **§7.4** — the Status text function is `TablePresentation.statusDisplay` (plus the shared `RowStatusText` prefix), not `RowModel.statusText` alone.

  Same "no changelog framing" rule.

- [x] **Step 6: Self-check both specs** — re-read the parent §7.4 / §7.6 / §7.8 / §12.1 / §12.2 and the Phase 6 spec with fresh eyes. No phase-number leakage outside §12. No §7.4 ↔ §12.1 contradiction. No "RESOLVED" / "PARKED" tags.

- [x] **Step 7: Hand off** — report the two changed spec files, confirm the full suite + lint + `make` launch all pass. No commit — the user handles git.

---

## Self-Review

**Spec coverage** (spec § → task):

| Spec § | Task |
|---|---|
| §2 `RateHost` + alias table | Task 1 |
| §3 `RateState` + state machine | Task 2, Task 4 |
| §3.2 `RatePolicy` (with `jitter:`) | Task 4 |
| §4 `RateLimiter` + adaptive concurrency + `effectiveCap` seam | Task 5, Task 11 |
| §5.1 strike definition (Step 0 confirms signatures) | Task 12 |
| §5.2 `recordExit` split — unconditional strike, terminal strike, one-`.cooldown`-per-host, siblings not SIGTERM'd | Task 12 |
| §5.3 scheduler gate (`blockedHostIDs`) + probe gate (`blockedProbeHostIDs`) | Task 12 |
| §5.4 `deferStart` 2nd caller + `cancelDeferral` + `fireDueDeferrals` cooldown flip | Task 10, Task 12 |
| §5.5 network monitor (debounce in the live impl) + offline/online + `isOnline` snapshot field | Task 7, Task 11, Task 13 |
| §5.6 `--concurrent-fragments` gated on `RateState` | Task 15 |
| §5.7 `revalidate` clears only `.depMissing`; `resetCircuit` / `resetAllCircuits` are their own APIs | Task 14 |
| §5.8 `forceStart` overrides a host block, respects `effectiveCap`, doesn't reset `RateState` | Task 14 |
| §5.9 no persistence — fresh `RateLimiter` per init | Task 11 (no restore path to build) |
| §6.1 `QueueHaltReason` + `effectiveQueueHalt()` deriving `.circuitOpen` | Task 8, Task 14 |
| §6.2 per-host circuit behavior | Task 12, Task 14 |
| §6.3 `QueueSnapshot` gains `hostRateSummary` + `isOnline` | Task 8, Task 13 |
| §6.4 `JobSnapshot` gains `rateHost`; `DownloadJob.cooldownUntil` stored, `snapshot()` reads it | Task 8, Task 12 |
| §7.1 `HealthController`, `SiteNames`, data-only `ChipInteraction.popover`, `HealthChip.countdownUntil`, `HostRatePopover` | Task 17 |
| §7.2 `BannerReason` + `resolveBanner` priority list + `bannerCopy` returning `BannerContent?` + optional button + floating-banner inset | Task 18 |
| §7.3 "Retry now" → `resetAllCircuits` / `resetCircuit`, no cooldown reset | Task 14 (engine), Task 17/18 (wiring) |
| §7.4 `RowStatusText` prefix + `TablePresentation.statusDisplay` + Status-cell `TimelineView` countdown | Task 19 |
| §7.5 `JobState.cooldown` / `.waitingForNetwork` made real; `availableActions` split | Task 9, Task 12/13 |
| §8 `EngineTuning` seven fields, **defaulted** `init` params | Task 3 |
| §9 logging — `DeferReason.hostCooldown` (in `SubmitResult.swift`) + six events (keyed via `.key`), all emitted | Task 10, Task 12, Task 13, Task 14, Task 16 |
| §10 testing | every task + Task 20 smoke |
| §11 parent-spec updates + Phase 6 spec sync | Task 20 |

Gaps: none.

**Harness note (the biggest revision from review):** Task 0 adds ordered-script support to `FakeProcessRunner`. Every engine-test body in Tasks 10, 12, 13, 14, 15 is written against the REAL harness — `EventCollector(engine.events)` (positional), `runner.script(_:forPathEndingIn:)` / `runner.scripts([...], forPathEndingIn:)`, `runner.launches`, `FakeMetadataProbe` with an explicit `.result(FakeMetadataProbe.success(...))`, `clock.advance(by:)` + `Task.sleep(20ms)` (no "fire deferrals" seam). No `enqueue`, `attach(to:)`, `recordedLaunches`, `holdOpen`, or `advanceAndFire` — those do not exist.

**Existing tests updated (named in-task):**
- Task 9 → `AvailableActionsTests.test_waitingForNetwork_and_cooldown`
- Task 12 → `EngineRetryTests` 429 tests (wait for `.cooldown` not `.queued`; add `clock.advance`), `SchedulerTests` (`SchedulerInput` arity), `EngineDeferralTests` (`DeferReason` switch)
- Task 13 → `hasActiveJobs` (+ `QuitCoordinatorTests` behavior), `EngineIntentsTests`
- Task 14 → `AppFakes.FakeEngine` (add `resetCircuit` / `resetAllCircuits`), `QuitCoordinatorTests` message arms
- Task 16 → any exhaustive `switch LogEvent` / `switch DeferReason` without `default`
- Task 17 → `AppModelTests` (old static `healthChips`)
- Task 19 → `RowModelStatusTests` ("Retrying" prefix), `DownloadsTableTests` (`statusDisplay` cooldown/circuit)
- Task 8 → every `JobSnapshot(` / `QueueSnapshot(` / `EngineDependencies(` construction site (grep, not a fixed list); `BackoffTests:57` compiles only because Task 3's `EngineTuning` params are defaulted

**Type consistency:**
- `RateHost(urlString:)` — Tasks 1, 8, 12, 14, 15, 17, 19.
- `RateLimiter.recordStrike(host:retryAfter:lastErrorKey:now:)` — Task 5, called in Task 12.
- `RateLimiter.displaySummary(now:)` — Task 5, called in `buildSnapshot` (Task 13).
- `RatePolicy.next(state:event:now:tuning:jitter:)` — Task 4, consumed in Task 5.
- `effectiveCap` = `min(rateLimiter.adaptiveCap, cap)` — Task 11, used by `evaluateSchedule` and `forceStart` (Task 14).
- `HealthController.update(snapshot:now:)` — Task 17, no `isOnline:` param; reads `snapshot.isOnline`.
- `bannerCopy(for:circuitHosts:onRetry:) -> BannerContent?` — Task 18, distinct name from the `AppModel.bannerContent` property.
- `SiteNames.display(_:)` — created in Task 17, used by `HealthController` + `HostRatePopover` + `BannerResolver` (Task 18). `RowModel.siteMap` (extractor-keyed) is a different thing, untouched.
- `DownloadEngineProtocol` gains `resetCircuit(_:) async` + `resetAllCircuits() async` (Task 14); `FakeEngine` + `AppModel` both implement/call (Tasks 14, 17).
- `DownloadJob.cooldownUntil: Date?` stored (Task 8); `snapshot(availableActions:)` one-arg, reads it (Task 8); set in the re-queue paths (Task 12).
- `SchedulerInput` gains `blockedHostIDs` + `blockedProbeHostIDs` (Task 12) — arity change fixed at every call site in that task.
- Test names: no `Phase6` anywhere — `EngineTuningRateLimitTests`, `LogEventRateLimitTests`, `testRateLimitTuningDefaults`.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-04-media-grabber-phase-6.md`. Two execution options:

**1. Subagent-Driven (recommended)** — a fresh subagent per task, two-stage review between tasks, fast iteration.

**2. Inline Execution** — tasks run in the session using executing-plans, batch execution with checkpoints for review.

Note: per the standing no-git rule, whichever path — no commits, no branches. Each task ends by running lint + tests and reporting the changed files to you; you handle version control.

Which approach?
