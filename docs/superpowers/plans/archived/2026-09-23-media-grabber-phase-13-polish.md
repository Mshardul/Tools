# MediaGrabber Phase 13 — Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close MediaGrabber's polish gap — toasts, backgrounded-failure notifications, empty-state gap closure (incl. deduping `hasGrabbedOnce`), live column-width readout, bundled Aurora fonts, a Debug menu, a Share Extension first-enable tip, then a full accessibility sweep — so the app feels finished for everyday use.

**Architecture:** Two new `@MainActor` model types (`ToastCenter`, `NotificationRouter`) sit off `AppModel`, fed by edge-detecting job-state transitions inside `AppModel.runConsumer()` (the engine has no discrete completed/failed event — only snapshots — so transitions are diffed per job ID against the previous `RowStore` state). `hasGrabbedOnce`/`showsTable` move from duplicated `@AppStorage` reads in two views onto `AppModel` as the single source of truth. The Downloads grid's AppKit substrate (`DownloadsGridHeaderView`) gets a small overlay label for live width readout, shown for the duration of the header's own synchronous resize-drag tracking loop. Debug menu items each get their own real mechanism (relaunch for state-affecting flags, a live `AppModel` setter for concurrency cap) rather than pretending `DebugFlags` is a mutable live surface. Fonts are vendored files wired through Tuist's `Project.swift`, not a hand-edited plist.

**Tech Stack:** Swift 6, SwiftUI (App target), AppKit (Downloads grid island), `UserNotifications` framework (native notifications), Tuist (`Project.swift`) for resources/Info.plist, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-23-media-grabber-phase-13-polish-design.md` (this plan implements it in full; read both together — the spec carries the locked decisions and rationale, this plan carries the exact files/code).

## Global Constraints

- Working name stays `MediaGrabber`. No product-name/icon work — that's Phase 14 Step 0.
- No per-job failure toasts, ever (row + Inactive rail badge only) — spec §Locked decisions "Toasts".
- Toast and native notification never double-fire for the same event — spec's double-fire table (Architecture → Feedback path).
- No first-run copy/layout redesign — only close the existing gaps against parent §5.3.
- No Aurora body-face swap (Inter stays the body face) — fonts task only stops silent system fallback.
- Debug menu is **always present** in the shipped app, not `#if DEBUG`-only.
- Share Extension tip must stand alone in its copy if the Settings deep-link fails; not blocking; shown once.
- Full a11y sweep is the **last** task — every other UI task must be done and frozen first.
- No git commands anywhere in this plan or its execution — file moves use `mv`; the user commits.
- Comments: single-line only, only for non-obvious *why*. No `///` doc comments, no stacked `//` blocks.
- Every source file path below is relative to `apps/media-grabber/` unless stated otherwise.
- Lint after every task: `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict` (run from `apps/media-grabber/`).
- Test after every task: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:<Suite>` (never bare `tuist test` while debugging — it hides compiler errors).
- After adding/removing files: `mise exec -- tuist generate --no-open`.

---

### Task 1: Dedupe `hasGrabbedOnce` onto `AppModel`

**Files:**
- Modify: `Sources/App/AppModel.swift`
- Modify: `Sources/App/Home/HomeView.swift:8,19-21,233,300`
- Modify: `Sources/App/MainWindow.swift:10,158-160`
- Test: `Tests/AppUnitTests/AppModelTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `AppModel.hasGrabbedOnce: Bool` (persisted via `UserDefaults`, key `"mg.hasGrabbedOnce"`), `AppModel.showsTable: Bool` (computed: `hasGrabbedOnce || !rowStore.rows.isEmpty`). Later tasks (empty-state audit, Task 5) read `appModel.showsTable` instead of re-deriving it.

`HomeView` and `MainWindow` each currently hold an independent `@AppStorage("mg.hasGrabbedOnce")` and re-derive the same boolean (`showsTable` in `HomeView`, `showsHomeRail` in `MainWindow`). Same key, same app, but two separate SwiftUI property wrappers reading it — nothing stops them from going out of sync if either view's derivation logic changes without the other. Move both onto `AppModel` as the single source of truth.

- [ ] **Step 1: Write the failing test**

Add to `Tests/AppUnitTests/AppModelTests.swift` (follow the file's existing `@MainActor` / `AppModelTestHelpers.makeModel` pattern — read the top of the file for the exact `defaults`/`logDirectory` setup already used by neighboring tests):

```swift
func test_showsTable_isFalseUntilFirstGrabOrNonEmptyQueue() throws {
    let defaults = try makeIsolatedDefaults()
    let logDir = try makeTempDirectory()
    let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDir)

    XCTAssertFalse(model.showsTable)

    model.hasGrabbedOnce = true
    XCTAssertTrue(model.showsTable)
}

func test_showsTable_isTrueWhenQueueNonEmptyEvenWithoutHasGrabbedOnce() throws {
    let defaults = try makeIsolatedDefaults()
    let logDir = try makeTempDirectory()
    let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDir)
    model.rowStore.resync(
        QueueSnapshot(
            jobs: [AppModelTestHelpers.jobSnapshot()],
            revision: 1,
            queueHalt: nil,
            generatedAt: .now,
            hostRateSummary: [:],
            isOnline: true
        )
    )

    XCTAssertTrue(model.showsTable)
}
```

If the file has no `makeIsolatedDefaults()` / `makeTempDirectory()` helpers, check `Tests/AppUnitTests/Support/AppModelTestHelpers.swift` and any existing test in `AppModelTests.swift` for the actual setup pattern (likely `UserDefaults(suiteName:)` + `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`) and match it exactly rather than inventing new helpers.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AppModelTests/test_showsTable_isFalseUntilFirstGrabOrNonEmptyQueue`
Expected: FAIL — `AppModel` has no member `hasGrabbedOnce` or `showsTable`.

- [ ] **Step 3: Add `hasGrabbedOnce` + `showsTable` to `AppModel`**

In `Sources/App/AppModel.swift`, add near the other stored properties (after `var bannerContent: BannerContent?`):

```swift
    private let defaults: UserDefaults

    var hasGrabbedOnce: Bool {
        get { defaults.bool(forKey: "mg.hasGrabbedOnce") }
        set { defaults.set(newValue, forKey: "mg.hasGrabbedOnce") }
    }

    var showsTable: Bool {
        hasGrabbedOnce || !rowStore.rows.isEmpty
    }
```

Add `defaults: UserDefaults = .standard` to `init(...)` parameters (after `prefs: Preferences,`) and `self.defaults = defaults` in the body (mirror how `prefs` is threaded — `Preferences` itself already takes a `defaults: UserDefaults` param per `Sources/GrabberKit/Model/Preferences.swift`, so `AppModel` gains its own independent `UserDefaults` reference for this one flag rather than reaching through `prefs`, since `prefs` is a `GrabberKit` type and `hasGrabbedOnce` is app-UI state).

Update `Tests/AppUnitTests/Support/AppModelTestHelpers.swift`'s `makeModel` to accept and forward a `defaults: UserDefaults` parameter to `AppModel.init` — check whether `makeModel` already takes `defaults` for `Preferences(defaults: defaults)` (it does, per the file read during planning: `defaults: UserDefaults` is already the first parameter). Thread that same `defaults` value into the new `AppModel.init(defaults:)` parameter too.

- [ ] **Step 4: Update `HomeView` to read `appModel.showsTable`**

In `Sources/App/Home/HomeView.swift`:
- Delete line 8 (`@AppStorage("mg.hasGrabbedOnce") private var hasGrabbedOnce = false`).
- Delete lines 19-21 (the `private var showsTable` computed property).
- Line 26: change `if showsTable {` to `if appModel.showsTable {`.
- Line 233 (`grab()` method): change `hasGrabbedOnce = true` to `appModel.hasGrabbedOnce = true`.
- Line 300 (`addPlaylistSelection()`): change `hasGrabbedOnce = true` to `appModel.hasGrabbedOnce = true`.

- [ ] **Step 5: Update `MainWindow` to read `appModel.showsTable`**

In `Sources/App/MainWindow.swift`:
- Delete line 10 (`@AppStorage("mg.hasGrabbedOnce") private var hasGrabbedOnce = false`).
- Delete lines 158-160 (`private var showsHomeRail`).
- Line 148: change `if showsHomeRail {` to `if appModel.showsTable {`.

- [ ] **Step 6: Run test to verify it passes**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AppModelTests`
Expected: PASS, including the two new tests.

- [ ] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint .` then `mise exec -- swiftlint lint --strict`. Fix any violations (do not disable rules).

---

### Task 2: `ToastCenter` + `ToastHost` (queue, auto-dismiss, stacking)

**Files:**
- Create: `Sources/App/Toasts/ToastCenter.swift`
- Create: `Sources/App/Toasts/ToastHost.swift`
- Modify: `Sources/App/MainWindow.swift` (add `ToastHost` overlay, peer to `WarningBanner`/`ConfirmationDialog`)
- Modify: `Sources/App/AppModel.swift` (own a `let toastCenter = ToastCenter()`)
- Test: `Tests/AppUnitTests/ToastCenterTests.swift`

**Interfaces:**
- Consumes: `theme.palette` tokens (existing `Theme`/`PaletteTokens` from `Sources/App/Theme/Theme.swift`), the `BannerContent`-style pattern from `Sources/App/Chrome/WarningBanner.swift` for the `@Sendable async` action closure shape.
- Produces: `ToastItem` (`id: UUID`, `text: String`, `actionTitle: String?`, `action: (@Sendable () async -> Void)?`), `ToastCenter.enqueue(_ item: ToastItem)`, `ToastCenter.items: [ToastItem]` (read-only, `@Observable`). Task 3 calls `appModel.toastCenter.enqueue(...)` directly — no intermediate API.

`ToastCenter` is a small `@MainActor @Observable` FIFO-ish queue: items append to the end, auto-dismiss after ~4s each (independent timers, not a single shared one — a stacked toast added while another is showing must not have its dismiss clock reset). `ToastHost` renders `items` bottom-right, stacked, newest at the bottom (matches design-system §4.4 "stacked").

- [ ] **Step 1: Write the failing test**

Create `Tests/AppUnitTests/ToastCenterTests.swift`:

```swift
import XCTest
@testable import MediaGrabber

@MainActor
final class ToastCenterTests: XCTestCase {
    func test_enqueue_appendsToItems() {
        let center = ToastCenter()
        center.enqueue(ToastItem(text: "Clip.mp4 saved", actionTitle: "Reveal", action: nil))
        XCTAssertEqual(center.items.count, 1)
        XCTAssertEqual(center.items.first?.text, "Clip.mp4 saved")
    }

    func test_enqueue_stacksMultipleInOrder() {
        let center = ToastCenter()
        center.enqueue(ToastItem(text: "First", actionTitle: nil, action: nil))
        center.enqueue(ToastItem(text: "Second", actionTitle: nil, action: nil))
        XCTAssertEqual(center.items.map(\.text), ["First", "Second"])
    }

    func test_dismiss_removesOnlyThatItem() {
        let center = ToastCenter()
        let first = ToastItem(text: "First", actionTitle: nil, action: nil)
        let second = ToastItem(text: "Second", actionTitle: nil, action: nil)
        center.enqueue(first)
        center.enqueue(second)

        center.dismiss(first.id)

        XCTAssertEqual(center.items.map(\.text), ["Second"])
    }

    func test_autoDismiss_removesAfterDelay() async throws {
        let center = ToastCenter(autoDismissDelay: .milliseconds(50))
        center.enqueue(ToastItem(text: "Ephemeral", actionTitle: nil, action: nil))
        XCTAssertEqual(center.items.count, 1)

        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(center.items.count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/ToastCenterTests`
Expected: FAIL — no such type `ToastCenter`/`ToastItem`.

- [ ] **Step 3: Implement `ToastCenter`**

Create `Sources/App/Toasts/ToastCenter.swift`:

```swift
import Foundation
import Observation

struct ToastItem: Identifiable, Sendable {
    let id: UUID
    let text: String
    let actionTitle: String?
    let action: (@Sendable () async -> Void)?

    init(
        id: UUID = UUID(),
        text: String,
        actionTitle: String?,
        action: (@Sendable () async -> Void)?
    ) {
        self.id = id
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
    }
}

@MainActor
@Observable
final class ToastCenter {
    private(set) var items: [ToastItem] = []
    private let autoDismissDelay: Duration
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    init(autoDismissDelay: Duration = .seconds(4)) {
        self.autoDismissDelay = autoDismissDelay
    }

    func enqueue(_ item: ToastItem) {
        items.append(item)
        let id = item.id
        dismissTasks[id] = Task { [weak self, autoDismissDelay] in
            try? await Task.sleep(for: autoDismissDelay)
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/ToastCenterTests`
Expected: PASS.

- [ ] **Step 5: Build `ToastHost` view**

Create `Sources/App/Toasts/ToastHost.swift`. Match `WarningBanner`'s structural pattern (palette tokens, `RoundedRectangle` background, plain button style) but positioned bottom-**right** and stacked (`VStack`, not the single-item `if let` of `WarningBanner`):

```swift
import SwiftUI

struct ToastHost: View {
    let items: [ToastItem]
    let onDismiss: (UUID) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: Spacing.s2) {
            ForEach(items) { item in
                toastRow(item)
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(!items.isEmpty)
    }

    private func toastRow(_ item: ToastItem) -> some View {
        HStack(spacing: Spacing.s3) {
            Text(item.text)
                .font(theme.bodyFont(13, .regular))
                .foregroundStyle(theme.palette.text)
            if let title = item.actionTitle, let action = item.action {
                Button(title) {
                    Task { await action() }
                    onDismiss(item.id)
                }
                .buttonStyle(.plain)
                .font(theme.bodyFont(13, .semibold))
                .foregroundStyle(theme.palette.accent)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(
            theme.palette.panel,
            in: RoundedRectangle(cornerRadius: theme.cardRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius)
                .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
        )
        .frame(maxWidth: 320, alignment: .leading)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
```

If `theme.palette` lacks any of `.text`, `.accent`, `.panel`, `.stroke` — it does not; all four are used elsewhere in `HomeView.swift` and `WarningBanner.swift` already, confirmed during planning — no new palette tokens needed.

- [ ] **Step 6: Wire `ToastCenter` onto `AppModel` and `ToastHost` into `MainWindow`**

In `Sources/App/AppModel.swift`, add near `let rowStore = RowStore()`:

```swift
    let toastCenter = ToastCenter()
```

In `Sources/App/MainWindow.swift`, add `ToastHost` as a peer to `WarningBanner` inside the outer `ZStack` (after the `WarningBanner(...)` line, before `.overlay { ... pendingConfirmation ... }`):

```swift
            ToastHost(items: appModel.toastCenter.items) { id in
                appModel.toastCenter.dismiss(id)
            }
```

- [ ] **Step 7: Run full AppUnitTests suite**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests`
Expected: PASS.

- [ ] **Step 8: Lint**

Run: `mise exec -- swiftformat --lint .` then `mise exec -- swiftlint lint --strict`.

---

### Task 3: Job completion/failure edge detection → toast / `NotificationRouter`

**Files:**
- Create: `Sources/App/Toasts/NotificationRouter.swift`
- Modify: `Sources/App/AppModel.swift` (`runConsumer()`, `init`)
- Test: `Tests/AppUnitTests/NotificationRouterTests.swift`
- Test: `Tests/AppUnitTests/AppModelTests.swift` (edge-detection + toast firing)

**Interfaces:**
- Consumes: `ToastCenter.enqueue(_:)` (Task 2), `RowModel.snapshot: JobSnapshot` (existing, `Sources/App/Rows/RowModel.swift:62`), `RevealSink` protocol (existing, `Sources/App/AppModelTypes.swift:9`) for the toast's Reveal action.
- Produces: `NotificationRouter` protocol-backed type with `func notifyJobFailed(title: String, reason: String) async`, an injectable `isAppActive: @Sendable () -> Bool` closure (so tests don't depend on real `NSApp.isActive`). `AppModel` gains a private edge-detection step inside `runConsumer()` — no new public API beyond what Task 2 already produced.

**The core mechanism.** `QueueEvent` (`Sources/GrabberKit/Download/QueueEvent.swift`) has only `.snapshot` and `.progress` — there is no discrete "job completed" or "job failed" event anywhere in the engine. `AppModel.runConsumer()` (`Sources/App/AppModel.swift:358-384`) is the only place that sees every incoming `QueueSnapshot` in order, and `rowStore.apply(event, ...)` is what turns a snapshot into updated `RowModel`s. To detect a `.* → .completed` or `.* → .failed` edge exactly once per job, capture each job's previous state (keyed by job ID) from `rowStore.rows` **before** calling `rowStore.apply`, then diff against the incoming snapshot's jobs after.

- [ ] **Step 1: Write the failing test for edge detection**

Add to `Tests/AppUnitTests/AppModelTests.swift`:

```swift
func test_jobTransitionToCompleted_whileActive_enqueuesSuccessToast() async throws {
    let defaults = try makeIsolatedDefaults()
    let logDir = try makeTempDirectory()
    let engine = FakeEngine()
    let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDir, engine: engine)
    model.isAppActive = { true }

    let jobID = UUID()
    let running = AppModelTestHelpers.jobSnapshot(id: jobID, state: .running)
    engine.emit(.snapshot(QueueSnapshot(
        jobs: [running], revision: 1, queueHalt: nil, generatedAt: .now,
        hostRateSummary: [:], isOnline: true
    )))
    model.startConsumerForTesting()
    try await Task.sleep(for: .milliseconds(50))

    let completed = AppModelTestHelpers.jobSnapshot(id: jobID, state: .completed)
    engine.emit(.snapshot(QueueSnapshot(
        jobs: [completed], revision: 2, queueHalt: nil, generatedAt: .now,
        hostRateSummary: [:], isOnline: true
    )))
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(model.toastCenter.items.count, 1)
    XCTAssertTrue(model.toastCenter.items.first?.text.contains("saved") ?? false)
}

func test_jobTransitionToFailed_whileBackgrounded_firesNotificationNotToast() async throws {
    let defaults = try makeIsolatedDefaults()
    let logDir = try makeTempDirectory()
    let engine = FakeEngine()
    let router = FakeNotificationRouter()
    let model = AppModelTestHelpers.makeModel(
        defaults: defaults, logDirectory: logDir, engine: engine, notificationRouter: router
    )
    model.isAppActive = { false }

    let jobID = UUID()
    let running = AppModelTestHelpers.jobSnapshot(id: jobID, state: .running)
    engine.emit(.snapshot(QueueSnapshot(
        jobs: [running], revision: 1, queueHalt: nil, generatedAt: .now,
        hostRateSummary: [:], isOnline: true
    )))
    model.startConsumerForTesting()
    try await Task.sleep(for: .milliseconds(50))

    let failed = AppModelTestHelpers.jobSnapshot(id: jobID, state: .failed(.unknown))
    engine.emit(.snapshot(QueueSnapshot(
        jobs: [failed], revision: 2, queueHalt: nil, generatedAt: .now,
        hostRateSummary: [:], isOnline: true
    )))
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(model.toastCenter.items.count, 0)
    XCTAssertEqual(router.notifiedFailures.count, 1)
}
```

This test references `model.isAppActive`, `model.startConsumerForTesting()`, `AppModelTestHelpers.makeModel(..., notificationRouter:)`, and `FakeNotificationRouter` — all introduced in the steps below. If `FakeEngine` has no `.emit(_:)` method for pushing `QueueEvent`s into its `events` stream, check `Tests/GrabberKitTests/DownloadEngineTestHelpers.swift` / wherever `FakeEngine` is defined for its actual event-injection API and use that instead — do not invent a signature that doesn't exist.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AppModelTests/test_jobTransitionToCompleted_whileActive_enqueuesSuccessToast`
Expected: FAIL — no such members.

- [ ] **Step 3: Implement `NotificationRouter`**

Create `Sources/App/Toasts/NotificationRouter.swift`:

```swift
import Foundation
import UserNotifications

@MainActor
protocol NotificationRouting {
    func notifyJobFailed(title: String, reason: String) async
}

@MainActor
final class NotificationRouter: NotificationRouting {
    private var permissionRequested = false

    func notifyJobFailed(title: String, reason: String) async {
        await requestPermissionIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "\(title) failed"
        content.body = reason
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func requestPermissionIfNeeded() async {
        guard !permissionRequested else { return }
        permissionRequested = true
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert])
    }
}
```

Permission is requested lazily on first `notifyJobFailed` call (not at cold launch), per spec. `try? await ... .add(request)` and `try? await ... .requestAuthorization` both silently no-op on denial/failure — the row + Inactive badge already show the failure, per spec's risk mitigation ("Notification permission denied → Silent skip; table / Inactive badge still show failure").

- [ ] **Step 4: Add a `FakeNotificationRouter` test double**

Add to `Tests/AppUnitTests/Support/AppModelTestHelpers.swift`:

```swift
@MainActor
final class FakeNotificationRouter: NotificationRouting {
    private(set) var notifiedFailures: [(title: String, reason: String)] = []

    func notifyJobFailed(title: String, reason: String) async {
        notifiedFailures.append((title, reason))
    }
}
```

- [ ] **Step 5: Wire edge detection into `AppModel`**

In `Sources/App/AppModel.swift`:

Add stored properties (near `let toastCenter = ToastCenter()`):

```swift
    let notificationRouter: any NotificationRouting
    var isAppActive: @Sendable () -> Bool = { NSApp?.isActive ?? true }
```

`NSApp?.isActive` requires `import AppKit` at the top of `AppModel.swift` — add it; the file currently only imports `Foundation`, `GrabberKit`, `Observation`, and `AppModel` is already `@MainActor` so this is safe. (`AppModel.swift` doesn't import AppKit today because nothing in it touches AppKit directly — this is the first thing that does.)

Add `notificationRouter: any NotificationRouting = NotificationRouter()` to `init(...)`'s parameter list (after `debugFlags:`), and `self.notificationRouter = notificationRouter` in the body.

Replace `runConsumer()` (currently lines 358-384) with a version that snapshots previous states before applying, then diffs after:

```swift
    private func runConsumer() async {
        while !Task.isCancelled {
            for await event in engine.events {
                let previousStates = Dictionary(
                    uniqueKeysWithValues: rowStore.rows.map { ($0.id, $0.snapshot.state) }
                )
                rowStore.apply(
                    event,
                    maxAutoRetries: prefs.maxAutoRetries,
                    vpnActive: vpnDetector.isVPNActive
                )
                if case let .snapshot(snapshot) = event {
                    handleJobTransitions(snapshot, previousStates: previousStates)
                    rowStore.applyGroups(playlistGroups)
                    hostRateSummary = snapshot.hostRateSummary
                    healthController.update(snapshot: snapshot, now: .now, environmentReport: latestEnvironmentReport)
                    recomputeBanner(snapshot)
                    applySnapshot(snapshot)
                }
            }
            await log.log(.consumerStreamEnded)
            try? await Task.sleep(for: .seconds(1))
            let snapshot = await engine.currentSnapshot()
            await rowStore.resync(
                snapshot,
                maxAutoRetries: prefs.maxAutoRetries,
                vpnActive: vpnDetector.isVPNActive
            )
            await rowStore.applyGroups(playlistGroups)
        }
    }

    private func handleJobTransitions(
        _ snapshot: QueueSnapshot,
        previousStates: [UUID: JobState]
    ) {
        for job in snapshot.jobs {
            guard let previous = previousStates[job.id], previous != job.state else { continue }
            switch job.state {
            case .completed:
                handleJobCompleted(job)
            case let .failed(errorClass):
                handleJobFailed(job, errorClass: errorClass)
            default:
                break
            }
        }
    }

    private func handleJobCompleted(_ job: JobSnapshot) {
        guard isAppActive() else { return }
        let title = job.title ?? job.url
        toastCenter.enqueue(ToastItem(
            text: "\(title) saved",
            actionTitle: "Reveal",
            action: { [revealSink] in
                await MainActor.run { revealSink.reveal(job.outputFiles) }
            }
        ))
    }

    private func handleJobFailed(_ job: JobSnapshot, errorClass: ErrorClass) {
        guard !isAppActive() else { return }
        let title = job.title ?? job.url
        Task { [notificationRouter] in
            await notificationRouter.notifyJobFailed(
                title: title,
                reason: errorClass.failureReasonSentence
            )
        }
    }
```

`ErrorClass.failureReasonSentence` — check `Sources/GrabberKit/**/*.swift` for the actual existing accessor that turns an `ErrorClass` into its user-facing sentence (Phase 4 built `ErrorClass` cases + failure-reason sentences per `ticket-backlog.md` Phase 4 — the property name may differ; grep `ErrorClass` for the real accessor name and use it verbatim, do not invent a new one).

Add a test-only consumer starter that bypasses `onAppear()`'s full launch sequence (mirrors the existing `startConsumerIfNeeded()` but callable directly from tests without going through `onAppear`):

```swift
    #if DEBUG
    func startConsumerForTesting() {
        startConsumerIfNeeded()
    }
    #endif
```

Update `AppModelTestHelpers.makeModel` in `Tests/AppUnitTests/Support/AppModelTestHelpers.swift` to accept `notificationRouter: (any NotificationRouting)? = nil` and forward `notificationRouter ?? FakeNotificationRouter()` to `AppModel.init`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AppModelTests`
Expected: PASS.

- [ ] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint .` then `mise exec -- swiftlint lint --strict`.

- [ ] **Step 8: Commit checkpoint (no git — hand off)**

Nothing to do here beyond confirming lint + tests are green; the user commits separately.

---

### Task 4: Chip-refresh failure → error toast

**Files:**
- Modify: `Sources/App/AppModelDiagnostics.swift`
- Modify: `Sources/App/MainWindow.swift` (shield/engine chip handlers)
- Test: `Tests/AppUnitTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `ToastCenter.enqueue(_:)` (Task 2), `YtDlpUpdateResult` (existing, `.success(newVersion:)` / `.failure(reason:)`, `Sources/GrabberKit/Diagnostics/YtDlpUpdater.swift`).
- Produces: `AppModelDiagnostics.restartShield()` and `.restartYtDlp()` now report failure via `toastCenter`; no new public signatures (both stay `func ... async`, callers in `MainWindow.swift` are unchanged).

Per spec's double-fire table, chip-refresh failures always toast (app active or not — they're not "download failed while away", spec §Architecture explicitly separates this case). `restartShield()` currently returns `Void` with no success/failure signal at all (`DownloadEngineProtocol.swift:31`) — that's an engine-layer gap this task must also close, since there's nothing to toast about otherwise.

- [ ] **Step 1: Write the failing test**

Add to `Tests/AppUnitTests/AppModelTests.swift`:

```swift
func test_restartYtDlp_onFailure_enqueuesErrorToast() async throws {
    let defaults = try makeIsolatedDefaults()
    let logDir = try makeTempDirectory()
    let updater = FakeYtDlpUpdater(result: .failure(reason: "network unreachable"))
    let model = AppModelTestHelpers.makeModel(
        defaults: defaults, logDirectory: logDir, ytDlpUpdater: updater
    )

    await model.restartYtDlp()

    XCTAssertEqual(model.toastCenter.items.count, 1)
    XCTAssertTrue(model.toastCenter.items.first?.text.contains("network unreachable") ?? false)
}

func test_restartYtDlp_onSuccess_doesNotToast() async throws {
    let defaults = try makeIsolatedDefaults()
    let logDir = try makeTempDirectory()
    let updater = FakeYtDlpUpdater(result: .success(newVersion: "2026.09.01"))
    let model = AppModelTestHelpers.makeModel(
        defaults: defaults, logDirectory: logDir, ytDlpUpdater: updater
    )

    await model.restartYtDlp()

    XCTAssertEqual(model.toastCenter.items.count, 0)
}
```

Check `Tests/AppUnitTests/Support/AppModelTestHelpers.swift` / `Tests/GrabberKitTests/` for an existing `FakeYtDlpUpdater` — `YtDlpUpdating` is a narrow one-method protocol (`Sources/GrabberKit/Diagnostics/YtDlpUpdater.swift:8`) so a fake likely already exists somewhere in the test targets; grep for it before writing a new one, and if `AppModelTestHelpers.makeModel` doesn't yet forward a `ytDlpUpdater:` parameter to `AppModel.init`, add it (mirroring how `envProbe:` is already forwarded).

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AppModelTests/test_restartYtDlp_onFailure_enqueuesErrorToast`
Expected: FAIL — `restartYtDlp()` never touches `toastCenter`.

- [ ] **Step 3: Give `restartShield()` a result type**

`DownloadEngineProtocol.restartShield()` (`Sources/GrabberKit/Download/DownloadEngineProtocol.swift:31`) and its implementation (`Sources/GrabberKit/Download/DownloadEngine+Preview.swift:36`) currently return `Void`. Change both to return a `Bool` (`true` = shield now running):

In `Sources/GrabberKit/Download/DownloadEngineProtocol.swift`, change:
```swift
    func restartShield() async
```
to:
```swift
    func restartShield() async -> Bool
```

In `Sources/GrabberKit/Download/DownloadEngine+Preview.swift`, find `func restartShield() async { ... }` (line 36) and change its signature to `func restartShield() async -> Bool { ... }`, returning `true`/`false` based on the shield's post-restart status (the method body already calls whatever re-launches the shield process and presumably checks `shieldStatus` afterward — read the existing body during implementation and return `shieldStatus == .running` at the end rather than guessing at intermediate state).

Check every other conformer of `DownloadEngineProtocol` (`FakeEngine` in test helpers, any other implementation) and update their `restartShield()` signature to match, returning a sensible default (`true` unless the fake is specifically testing failure).

- [ ] **Step 4: Update `AppModelDiagnostics` to toast on failure**

Rewrite `Sources/App/AppModelDiagnostics.swift`:

```swift
import Foundation
import GrabberKit

extension AppModel {
    func restartShield() async {
        let succeeded = await engine.restartShield()
        if !succeeded {
            toastCenter.enqueue(ToastItem(
                text: "Bot-check shield restart failed",
                actionTitle: nil,
                action: nil
            ))
        }
    }

    func restartYtDlp() async {
        healthController.markBusy(chipID: "engine")
        let result = await ytDlpUpdater.reinstallToMinimum()
        let report = await envProbe.probe()
        setLatestEnvironmentReport(report)
        let snapshot = await engine.currentSnapshot()
        healthController.update(snapshot: snapshot, now: .now, environmentReport: report)
        healthController.clearBusy(chipID: "engine")
        if case let .failure(reason) = result {
            toastCenter.enqueue(ToastItem(text: "yt-dlp update failed: \(reason)", actionTitle: nil, action: nil))
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AppModelTests`
Expected: PASS.

- [ ] **Step 6: Run the full GrabberKit + App test suites** (the `restartShield()` signature change touches the engine layer)

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`
Expected: PASS. Fix any other call site of `restartShield()` that assumed `Void`.

- [ ] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint .` then `mise exec -- swiftlint lint --strict`.

---

### Task 5: Empty-state gap audit (AppKit grid emptied vs filtered)

**Files:**
- Modify: `Sources/App/Table/DownloadsGridController.swift` or `DownloadsGridView.swift` (whichever renders the empty-queue message — locate during implementation)
- Modify: `Sources/App/Home/HomeView.swift` (if the audit finds `showsTable`/rail gaps beyond Task 1's dedupe)
- Test: `Tests/AppUnitTests/` (whichever suite covers `TablePresentation` / empty predicates)

**Interfaces:**
- Consumes: `TablePresentation.emptyQueueMessage` / `.filteredEmptyMessage` (existing, per spec — locate the actual type during implementation with `grep -rn "emptyQueueMessage" Sources/`), `appModel.showsTable` (Task 1).
- Produces: no new public API — this task closes gaps in existing wiring, it does not introduce new types.

This is an audit task, not a build-from-scratch task — the spec is explicit that the model (`hasGrabbedOnce`/`showsTable`, `TablePresentation.emptyQueueMessage`/`.filteredEmptyMessage`) already exists; Task 1 already fixed the dedup gap. What's left per spec: "rail / Columns visibility, first Grab flipping `hasGrabbedOnce`, emptied vs filtered empty in the AppKit grid."

- [ ] **Step 1: Locate the current empty-state rendering in the AppKit grid**

Run: `grep -rn "emptyQueueMessage\|filteredEmptyMessage\|TablePresentation" Sources/App/Table/` to find the exact file(s) and confirm both messages are actually wired to distinct conditions (queue genuinely empty vs. rows exist but the active rail filter/column filter hides all of them). This determines whether Steps 2+ are "write a regression test for existing correct behavior" or "fix a real gap" — do not assume which before checking.

- [ ] **Step 2: Write a test asserting emptied-queue and filtered-empty are distinct**

Once the real predicate location is known (likely on `RowStore` or a computed property the grid controller reads), write a test in the matching existing test file (do not create a new file if `RowStoreTests.swift` or similar already exists — check `Tests/AppUnitTests/` first) asserting:
- Zero rows in `rowStore.rows` at all → emptied message.
- Non-zero `rowStore.rows` but zero `rowStore.visibleRows` after a rail/column filter → filtered message, not the emptied one.

Write the exact test body once Step 1's grep result shows the real property names — do not guess signatures here; this step is intentionally left to reference real names discovered in Step 1, per this plan's "no placeholders" rule the implementer must fill in the concrete assertions using the types found, following the same `@MainActor` / `RowStore()` direct-construction pattern used in `RowStoreTests.swift` if it exists, else `AppModelTestHelpers.makeModel`.

- [ ] **Step 3: Fix any gap found**

If Step 1/2 finds the two messages are already correctly distinguished, skip to Step 4 (no code change — audit passed). If not, the fix is scoped to whichever single property conflates the two conditions — fix it in place, do not restructure surrounding code.

- [ ] **Step 4: Verify rail/Columns visibility gate matches parent §5.3**

Confirm (via `MainWindow.swift`'s `rail` computed property, already reading `appModel.showsTable` after Task 1) that first-run truly shows no rail and no Columns button. Grep `Sources/App/Home/HomeView.swift` and `Sources/App/Table/DownloadsTable.swift` for a "Columns" button/menu and confirm it's gated behind the same `showsTable`-driven `tableLayout` branch (it already is, per the `HomeView.body` read during planning — `tableLayout` vs `firstRunLayout` — but confirm the Columns control specifically lives inside `tableLayout`, not rendered unconditionally).

- [ ] **Step 5: Run tests**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests`
Expected: PASS.

- [ ] **Step 6: Lint**

Run: `mise exec -- swiftformat --lint .` then `mise exec -- swiftlint lint --strict`.

---

### Task 6: Live column-width readout during resize

**Files:**
- Modify: `Sources/App/Table/DownloadsGridHeaders.swift` (`DownloadsGridHeaderView`)
- Create: `Sources/App/Table/ColumnWidthReadoutView.swift`
- Test: `Tests/AppUnitTests/` — AppKit drag interaction is not meaningfully unit-testable; this task's test coverage is the width-formatting helper only (see Step 1), the show/hide behavior is manual/UI-smoke per spec's testing notes.

**Interfaces:**
- Consumes: `DownloadsGridHeaderView.mouseDown(with:)` (existing, `Sources/App/Table/DownloadsGridHeaders.swift:115`), `NSTableColumn.width` (AppKit).
- Produces: `ColumnWidthReadoutView` (a small borderless `NSView`/`NSTextField` overlay), no changes to any existing public closure signature (`onColumnWidthChange` stays as-is — the readout is purely visual, it doesn't feed back into persistence, which continues through the existing `tableViewColumnDidResize` → `onColumnWidthChange` → `ColumnConfig` path unchanged).

**The mechanism.** `DownloadsGridHeaderView.mouseDown(with:)` currently falls through to `super.mouseDown(with: event)` (line 132) whenever the click isn't a double-click-on-divider or a sort/filter affordance hit. That `super` call is `NSTableHeaderView`'s own column-resize drag-tracking loop — it runs synchronously and does not return until the user releases the mouse button. That means wrapping that one call is sufficient to show the readout before the drag starts and hide it right after the drag ends, with no separate mouse-up tracking needed.

- [ ] **Step 1: Write the failing test for the pt-formatting helper**

Create the formatting helper as a pure function so it's actually testable (the drag interaction itself isn't). Add to `Tests/AppUnitTests/ColumnWidthReadoutTests.swift`:

```swift
import XCTest
@testable import MediaGrabber

final class ColumnWidthReadoutTests: XCTestCase {
    func test_format_roundsToNearestIntegerPoint() {
        XCTAssertEqual(ColumnWidthReadout.format(120.4), "120 pt")
        XCTAssertEqual(ColumnWidthReadout.format(120.6), "121 pt")
        XCTAssertEqual(ColumnWidthReadout.format(80.0), "80 pt")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/ColumnWidthReadoutTests`
Expected: FAIL — no such type.

- [ ] **Step 3: Implement `ColumnWidthReadout` (formatting) + `ColumnWidthReadoutView` (the overlay)**

Create `Sources/App/Table/ColumnWidthReadoutView.swift`:

```swift
import AppKit

enum ColumnWidthReadout {
    static func format(_ width: CGFloat) -> String {
        "\(Int(width.rounded())) pt"
    }
}

final class ColumnWidthReadoutView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
        layer?.cornerRadius = 4
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(width: CGFloat, near point: NSPoint) {
        label.stringValue = ColumnWidthReadout.format(width)
        label.sizeToFit()
        frame = NSRect(
            x: point.x - label.frame.width / 2 - 6,
            y: point.y - 24,
            width: label.frame.width + 12,
            height: label.frame.height + 4
        )
    }
}
```

- [ ] **Step 4: Wire show/hide around the resize-drag tracking loop**

In `Sources/App/Table/DownloadsGridHeaders.swift`, add a stored `readoutView: ColumnWidthReadoutView?` and a `resizingColumnIndex: Int?` to `DownloadsGridHeaderView`, and wrap the `super.mouseDown(with: event)` fallthrough:

```swift
final class DownloadsGridHeaderView: NSTableHeaderView {
    var onDoubleClickDivider: ((Int) -> Void)?
    var onHeaderAffordanceClick: ((Int, GridHeaderHit, NSEvent) -> Void)?

    private var readoutView: ColumnWidthReadoutView?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, let columnIndex = resizeHandleColumnIndex(at: point) {
            onDoubleClickDivider?(columnIndex)
            return
        }

        let columnIndex = column(at: point)
        if let headerCell = headerCell(at: columnIndex) {
            let columnFrame = headerRect(ofColumn: columnIndex)
            let hit = headerCell.hitTest(point, in: columnFrame)
            if hit == .sort || hit == .filter {
                onHeaderAffordanceClick?(columnIndex, hit, event)
                return
            }
        }

        if let resizingIndex = resizeHandleColumnIndex(at: point) {
            beginWidthReadout(columnIndex: resizingIndex)
            super.mouseDown(with: event)
            endWidthReadout()
            return
        }

        super.mouseDown(with: event)
    }

    private func beginWidthReadout(columnIndex: Int) {
        guard let tableView else { return }
        let view = ColumnWidthReadoutView(frame: .zero)
        addSubview(view)
        readoutView = view
        updateWidthReadout(columnIndex: columnIndex)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLiveResize(_:)),
            name: NSTableView.columnDidResizeNotification,
            object: tableView
        )
        objc_setAssociatedObject(self, &Self.resizingColumnKey, columnIndex, .OBJC_ASSOCIATION_RETAIN)
    }

    @objc
    private func handleLiveResize(_: Notification) {
        guard let index = objc_getAssociatedObject(self, &Self.resizingColumnKey) as? Int else { return }
        updateWidthReadout(columnIndex: index)
    }

    private func updateWidthReadout(columnIndex: Int) {
        guard let tableView, columnIndex < tableView.tableColumns.count else { return }
        let column = tableView.tableColumns[columnIndex]
        let headerRect = headerRect(ofColumn: columnIndex)
        let point = NSPoint(x: headerRect.maxX, y: headerRect.midY)
        readoutView?.update(width: column.width, near: point)
    }

    private func endWidthReadout() {
        NotificationCenter.default.removeObserver(self, name: NSTableView.columnDidResizeNotification, object: tableView)
        readoutView?.removeFromSuperview()
        readoutView = nil
    }

    private static var resizingColumnKey: UInt8 = 0

    // ... existing headerCell(at:), resizeHandleColumnIndex(at:) unchanged
}
```

Using `NotificationCenter` + `NSTableView.columnDidResizeNotification` rather than trying to read the drag's live position directly, since `NSTableHeaderView`'s built-in resize loop doesn't expose a per-tick callback — it posts that notification on every width change during the drag, which `DownloadsGridController.tableViewColumnDidResize(_:)` (`Sources/App/Table/DownloadsGridController+Columns.swift:7`) already observes for persistence. This adds a second, narrower observer scoped to just the header view's lifetime during one drag, not a permanent one, so it doesn't interfere with the controller's existing handling — both fire off the same underlying notification independently.

- [ ] **Step 5: Manual verification (no automated test for the drag interaction itself)**

Run `make` from `apps/media-grabber/`, open the Downloads table with at least one row, drag a resizable column's divider. Confirm: readout appears near the divider showing the live integer pt width, updates continuously while dragging, disappears immediately on mouse-up. Confirm width still persists to `columns.json` afterward (unchanged behavior — verify by quitting and relaunching).

- [ ] **Step 6: Run tests**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/ColumnWidthReadoutTests`
Expected: PASS.

- [ ] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint .` then `mise exec -- swiftlint lint --strict`. Note: `swiftlint`'s `strict` mode may flag the `objc_setAssociatedObject` pattern as non-idiomatic Swift — if so, replace it with a plain stored `private var resizingColumnIndex: Int?` on `DownloadsGridHeaderView` instead (simpler, and avoids the associated-object indirection entirely — it was only sketched via associated object above to keep the class's existing stored-property list minimal; a direct stored property is the better implementation and should be preferred over the associated-object version shown here).

---

### Task 7: Bundle Aurora fonts (Sora, Inter, JetBrains Mono)

**Files:**
- Create: `Resources/Fonts/Sora/` (vendored `.ttf`/`.otf` files, OFL-licensed)
- Create: `Resources/Fonts/Inter/`
- Create: `Resources/Fonts/JetBrainsMono/`
- Create: `Resources/Fonts/LICENSE-OFL.txt` (or per-family license files, matching upstream)
- Modify: `Project.swift:30,57`
- Modify: `README.md` (or wherever "Known Phase 1 gaps" lives — `CLAUDE.md` "Known Phase 1 gaps" section)
- Test: `Tests/AppUnitTests/FontBundlingTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: no API change — `Theme.resolvedFont` (`Sources/App/Theme/Theme.swift:46`) already does the right lookup (`NSFont(name: family, size: size)`); this task's only job is making that lookup succeed instead of silently falling back.

- [ ] **Step 1: Obtain the font files**

Download OFL-licensed release files for Sora, Inter, and JetBrains Mono (these are the well-known open-source families at fonts.google.com/specimen/Sora, fonts.google.com/specimen/Inter, and jetbrains.com/lp/mono — use each project's official OFL.txt as the license file). Place the `.ttf` (or `.otf`) files under `apps/media-grabber/Resources/Fonts/<Family>/` and copy each family's `OFL.txt` alongside its files. This step requires network access outside this repo — if unavailable in the execution environment, flag to the user rather than fabricating font bytes.

- [ ] **Step 2: Write the failing smoke test**

Create `Tests/AppUnitTests/FontBundlingTests.swift`:

```swift
import XCTest
@testable import MediaGrabber

final class FontBundlingTests: XCTestCase {
    func test_soraFamily_resolvesAfterBundling() {
        XCTAssertNotNil(NSFont(name: "Sora", size: 14), "Sora must resolve once bundled — check ATSApplicationFontsPath")
    }

    func test_interFamily_resolvesAfterBundling() {
        XCTAssertNotNil(NSFont(name: "Inter", size: 14))
    }

    func test_jetBrainsMonoFamily_resolvesAfterBundling() {
        XCTAssertNotNil(NSFont(name: "JetBrains Mono", size: 14))
    }
}
```

This test only passes when run against the actual built `.app` bundle (Info.plist + Resources) — it exercises real font registration, not a mock. Add it to `AppUnitTests` (which already depends on the `MediaGrabber` app target/scheme per `CLAUDE.md`'s note that "The `MediaGrabber` scheme only exists because `AppUnitTests` depends on it").

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/FontBundlingTests`
Expected: FAIL — all three `NSFont(name:...)` calls return `nil` (system fallback).

- [ ] **Step 4: Wire fonts through `Project.swift`**

Read `Project.swift:1-60` in full before editing (the exact key ordering/style must match what's already there — do not guess at the surrounding structure).

Add `"ATSApplicationFontsPath": "Fonts"` to the `infoPlist: .extendingDefault(with: [...])` dictionary at line 30 (alongside the existing `LSMinimumSystemVersion`, `CFBundleDisplayName`, etc. keys).

Change the `resources:` array at line 57 from:
```swift
resources: ["PRIVACY.md"],
```
to:
```swift
resources: ["PRIVACY.md", "Resources/Fonts/**"],
```

`ATSApplicationFontsPath` is relative to the app bundle's `Resources/` directory — since Tuist's `resources:` glob copies `Resources/Fonts/**` into the bundle's `Resources/Fonts/`, the plist value `"Fonts"` (not `"Resources/Fonts"`) is correct; verify this against the actual copied bundle layout in Step 6 rather than assuming.

- [ ] **Step 5: Regenerate the Tuist project**

Run: `mise exec -- tuist generate --no-open`

- [ ] **Step 6: Run test to verify it passes**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/FontBundlingTests`
Expected: PASS. If it still fails, inspect the built `.app`'s `Contents/Resources/Fonts/` layout (`find build/Build/Products/Debug/MediaGrabber.app/Contents/Resources/Fonts`) to confirm the glob copied files to the path the `ATSApplicationFontsPath` value expects, and adjust the plist value (not the glob) to match reality.

- [ ] **Step 7: Verify AppKit grid cells resolve the same families**

Grep `Sources/App/Table/*.swift` for any `NSFont(...)` construction that doesn't go through `Theme.resolvedFont` — the spec calls out "AppKit grid cells that use custom/`NSFont` must resolve the same family names after registration." If any cell builds its own `NSFont` by family name string directly (rather than via `Theme`), confirm it uses the same literal family name strings (`"Sora"`, `"Inter"`, `"JetBrains Mono"`) — case and spacing must match exactly what the font files declare internally, which may not be what's assumed; verify with `fc-scan` or Font Book after Step 1's files are in place.

- [ ] **Step 8: Document the license + path**

In `CLAUDE.md`'s "Known Phase 1 gaps" section, remove the "Aurora typefaces ... are not bundled" bullet (it's closed now) and add a short note under a new "Fonts" or similar heading pointing to `Resources/Fonts/<Family>/OFL.txt` for each family's license — one line, matching the file's existing terse style, not a new prose section.

- [ ] **Step 9: Lint**

Run: `mise exec -- swiftformat --lint .` then `mise exec -- swiftlint lint --strict`.

---

### Task 8: Debug menu — relaunch actions (Force Onboarding, Reset State) + live Concurrency Cap

**Files:**
- Create: `Sources/App/Debug/DebugMenuCommands.swift`
- Create: `Sources/App/Debug/AppRelauncher.swift`
- Modify: `Sources/App/MediaGrabberApp.swift` (`.commands { ... }`)
- Modify: `Sources/App/AppModel.swift` (live concurrency override setter)
- Test: `Tests/AppUnitTests/AppRelauncherTests.swift`
- Test: `Tests/AppUnitTests/AppModelTests.swift` (live concurrency override)

**Interfaces:**
- Consumes: `DebugFlags.parse(_:)` (existing, `Sources/App/DebugFlags.swift`), `AppModel.maxConcurrentDownloads` (existing computed property, `Sources/App/AppModel.swift:76-78`).
- Produces: `AppRelauncher.relaunch(withExtraArguments: [String])` (protocol-backed, injectable for tests), `AppModel.debugConcurrencyCapOverride: Int?` (settable, live — replaces the read-only `debugFlags.concurrencyCapOverride` as the value `maxConcurrentDownloads` resolves against).

- [ ] **Step 1: Write the failing test for live concurrency override**

Add to `Tests/AppUnitTests/AppModelTests.swift`:

```swift
func test_setDebugConcurrencyCapOverride_changesMaxConcurrentDownloadsLive() throws {
    let defaults = try makeIsolatedDefaults()
    let logDir = try makeTempDirectory()
    let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDir)
    let originalDefault = model.maxConcurrentDownloads

    model.debugConcurrencyCapOverride = 1

    XCTAssertEqual(model.maxConcurrentDownloads, 1)
    XCTAssertNotEqual(model.maxConcurrentDownloads, originalDefault, "guard against prefs already defaulting to 1")
}
```

If `originalDefault` happens to already be `1` in test defaults, adjust the guard assertion's setup rather than deleting it — the point is confirming the override actually takes effect, not merely that reading it twice returns the same number.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AppModelTests/test_setDebugConcurrencyCapOverride_changesMaxConcurrentDownloadsLive`
Expected: FAIL — no such member `debugConcurrencyCapOverride`.

- [ ] **Step 3: Make the concurrency cap override live-settable**

In `Sources/App/AppModel.swift`, replace the existing computed property:
```swift
    var maxConcurrentDownloads: Int {
        debugFlags.concurrencyCapOverride ?? prefs.maxConcurrentDownloads
    }
```
with:
```swift
    var debugConcurrencyCapOverride: Int?

    var maxConcurrentDownloads: Int {
        debugConcurrencyCapOverride ?? debugFlags.concurrencyCapOverride ?? prefs.maxConcurrentDownloads
    }
```

In `init(...)`, seed the live override from the launch-time flag so CLI-launched debug sessions keep working unchanged:
```swift
        self.debugConcurrencyCapOverride = debugFlags.concurrencyCapOverride
```
(add this line in the body, near where `self.debugFlags = debugFlags` is already set).

Check whether `maxConcurrentDownloads` actually feeds a live scheduler read (i.e., whether the engine re-reads it on every scheduling pass, or only at construction via `EngineDebugFlags(concurrencyCapOverride:)` in `MediaGrabberApp.swift:21-22`) — if the engine only reads the cap once at construction, this live setter changes `AppModel.maxConcurrentDownloads` but won't actually affect the running engine's concurrency. Grep `Sources/GrabberKit/` for where `EngineDebugFlags.concurrencyCapOverride` or `Preferences.maxConcurrentDownloads` is read during scheduling to confirm; if it's construction-only, this task's "live" claim needs the engine to expose a live setter too (`engine.setConcurrencyCap(_:)` or similar) — add one if missing, following whatever pattern `DownloadEngineProtocol` already uses for other live-mutable settings (e.g. how `prefs.maxConcurrentDownloads` changes propagate today, if they do at all).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AppModelTests/test_setDebugConcurrencyCapOverride_changesMaxConcurrentDownloadsLive`
Expected: PASS.

- [ ] **Step 5: Write the failing test for `AppRelauncher`**

Create `Tests/AppUnitTests/AppRelauncherTests.swift`:

```swift
import XCTest
@testable import MediaGrabber

final class AppRelauncherTests: XCTestCase {
    func test_relaunch_buildsCommandWithExtraArguments() {
        let spy = SpyProcessLauncher()
        let relauncher = AppRelauncher(launcher: spy)

        relauncher.relaunch(withExtraArguments: ["-MGForceOnboarding"])

        XCTAssertEqual(spy.launchedArguments, ["-MGForceOnboarding"])
    }
}

final class SpyProcessLauncher: RelaunchProcessLaunching {
    private(set) var launchedArguments: [String] = []

    func launch(executablePath: String, arguments: [String]) {
        launchedArguments = arguments
    }
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AppRelauncherTests`
Expected: FAIL — no such types.

- [ ] **Step 7: Implement `AppRelauncher`**

Create `Sources/App/Debug/AppRelauncher.swift`:

```swift
import Foundation

protocol RelaunchProcessLaunching {
    func launch(executablePath: String, arguments: [String])
}

struct SystemProcessLauncher: RelaunchProcessLaunching {
    func launch(executablePath: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        try? process.run()
    }
}

struct AppRelauncher {
    private let launcher: RelaunchProcessLaunching

    init(launcher: RelaunchProcessLaunching = SystemProcessLauncher()) {
        self.launcher = launcher
    }

    func relaunch(withExtraArguments extraArguments: [String]) {
        guard let executablePath = Bundle.main.executablePath else { return }
        launcher.launch(executablePath: executablePath, arguments: extraArguments)
        NSApplication.shared.terminate(nil)
    }
}
```

`AppRelauncher` needs `import AppKit` for `NSApplication` — add it.

- [ ] **Step 8: Run test to verify it passes**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AppRelauncherTests`
Expected: PASS.

- [ ] **Step 9: Build the Debug menu commands**

Create `Sources/App/Debug/DebugMenuCommands.swift`:

```swift
import SwiftUI

struct DebugMenuCommands: Commands {
    let appModel: AppModel
    let relauncher: AppRelauncher

    @State private var pendingResetConfirmation = false

    var body: some Commands {
        CommandMenu("Debug") {
            Button("Force Onboarding (Relaunch)") {
                relauncher.relaunch(withExtraArguments: ["-MGForceOnboarding"])
            }
            Button("Reset State (Relaunch)…") {
                confirmAndReset()
            }
            Divider()
            Menu("Concurrency Cap") {
                ForEach([1, 2, 3, 4, 6, 8], id: \.self) { cap in
                    Button("\(cap)") {
                        appModel.debugConcurrencyCapOverride = cap
                    }
                }
                Button("Default (Preferences)") {
                    appModel.debugConcurrencyCapOverride = nil
                }
            }
        }
    }

    private func confirmAndReset() {
        let alert = NSAlert()
        alert.messageText = "Reset all local state?"
        alert.informativeText = "This wipes the download queue, history, and preferences, then relaunches. This cannot be undone."
        alert.addButton(withTitle: "Reset and Relaunch")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        relauncher.relaunch(withExtraArguments: ["-MGResetState"])
    }
}
```

`DebugMenuCommands` needs `import AppKit` for `NSAlert` — add it. `SwiftUI.Commands` bodies can't easily host an async confirmation dialog inline without extra plumbing, so this uses a synchronous `NSAlert.runModal()` (blocking, modal) for the destructive Reset State path specifically — that's an accepted, standard AppKit pattern for a one-shot destructive confirmation triggered from a menu command, not a SwiftUI sheet (which would need a hosting window context the `Commands` body doesn't have).

- [ ] **Step 10: Wire `DebugMenuCommands` into the app scene**

In `Sources/App/MediaGrabberApp.swift`, add `.commands { DebugMenuCommands(appModel: appModel, relauncher: AppRelauncher()) }` to the `WindowGroup` scene, after `.windowResizability(.contentMinSize)`:

```swift
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            DebugMenuCommands(appModel: appModel, relauncher: AppRelauncher())
        }
```

- [ ] **Step 11: Run full test suite**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests`
Expected: PASS.

- [ ] **Step 12: Manual verification**

Run `make`, open the Debug menu in the menu bar, confirm it's present and always visible (not `#if DEBUG`-gated). Click "Force Onboarding (Relaunch)" and confirm the app relaunches straight into Onboarding. Click "Reset State (Relaunch)…" and confirm the confirm dialog appears, Cancel does nothing, confirming wipes state and relaunches to first-run. Change Concurrency Cap and confirm (via Diagnostics or by queuing several jobs) that the running count of simultaneous downloads respects the new cap without relaunching.

- [ ] **Step 13: Lint**

Run: `mise exec -- swiftformat --lint .` then `mise exec -- swiftlint lint --strict`.

---

### Task 9: Share Extension first-enable tip

**Files:**
- Create: `Sources/App/Home/ShareExtensionTipView.swift`
- Modify: `Sources/App/Home/HomeView.swift` (surface the tip after first Grab, inside `tableLayout`)
- Test: `Tests/AppUnitTests/AppModelTests.swift` or a new `ShareExtensionTipTests.swift` (dismiss-forever persistence)

**Interfaces:**
- Consumes: `AppModel.hasGrabbedOnce` (Task 1), `WorkspaceOpenURLSink`/`OpenURLSink` (existing, `Sources/App/AppModelTypes.swift:22-33`) for the best-effort Settings deep-link.
- Produces: `ShareExtensionTipView` (SwiftUI), an `AppStorage`-backed `mg.shareExtensionTipDismissed` flag (kept as plain `@AppStorage` in the view itself, per spec — this one is genuinely view-local one-shot UI state, unlike `hasGrabbedOnce` which needed cross-view agreement; no dedup concern here since only one view ever reads it).

- [ ] **Step 1: Write the failing test for dismiss-forever behavior**

Add to `Tests/AppUnitTests/AppModelTests.swift` or create `Tests/AppUnitTests/ShareExtensionTipTests.swift` (prefer the latter — it's a self-contained concern, matches the file-per-feature pattern the rest of this plan already uses for `ToastCenterTests`, `AppRelauncherTests`, etc.):

```swift
import XCTest
@testable import MediaGrabber

final class ShareExtensionTipTests: XCTestCase {
    func test_dismissedFlag_persistsAcrossReads() {
        let suiteName = "ShareExtensionTipTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(defaults.bool(forKey: "mg.shareExtensionTipDismissed"))
        defaults.set(true, forKey: "mg.shareExtensionTipDismissed")
        XCTAssertTrue(defaults.bool(forKey: "mg.shareExtensionTipDismissed"))
    }
}
```

This test only proves `UserDefaults` semantics — it's a thin guard, not a real behavior test, because the interesting behavior (tip shows once, after first Grab, stays hidden forever) lives in SwiftUI view state that's better verified manually (Step 5) than through XCTest, same as Task 6's drag interaction. Keep this test anyway since it costs nothing and documents the key name.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/ShareExtensionTipTests`
Expected: PASS immediately (this test doesn't depend on any new production code — it's pure `UserDefaults`). Since TDD's red step doesn't apply here, proceed directly; note this in the PR description rather than forcing an artificial failure.

- [ ] **Step 3: Build `ShareExtensionTipView`**

Create `Sources/App/Home/ShareExtensionTipView.swift`. Follow the visual pattern of `WarningBanner`/toast rows (palette tokens, `RoundedRectangle` background) but as a dismissible card, not a bottom-docked banner:

```swift
import SwiftUI

struct ShareExtensionTipView: View {
    @AppStorage("mg.shareExtensionTipDismissed") private var dismissed = false
    @Environment(\.theme) private var theme
    let openURLSink: OpenURLSink

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: Spacing.s3) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Enable the Share Extension")
                        .font(theme.bodyFont(13, .semibold))
                        .foregroundStyle(theme.palette.text)
                    Text("Turn on MediaGrabber under System Settings → Extensions to grab links from Safari's Share menu.")
                        .font(theme.bodyFont(12, .regular))
                        .foregroundStyle(theme.palette.dim)
                }
                Spacer(minLength: Spacing.s3)
                VStack(spacing: Spacing.s2) {
                    Button("Open System Settings") {
                        openSettingsPane()
                    }
                    .buttonStyle(.plain)
                    .font(theme.bodyFont(12, .semibold))
                    .foregroundStyle(theme.palette.accent)
                    Button("Dismiss") {
                        dismissed = true
                    }
                    .buttonStyle(.plain)
                    .font(theme.bodyFont(12, .regular))
                    .foregroundStyle(theme.palette.dim)
                }
            }
            .padding(Spacing.s4)
            .background(theme.palette.panel, in: RoundedRectangle(cornerRadius: theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: theme.cardRadius)
                    .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
            )
        }
    }

    private func openSettingsPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            openURLSink.open(url)
        }
    }
}
```

`x-apple.systempreferences:com.apple.ExtensionsPreferences` is a best-effort guess at the Extensions pane's URL scheme (there is no Apple-documented stable identifier for it, unlike the Privacy pane used elsewhere in this app at `CookiePaneModel.swift:72`) — verify it actually opens the right pane on the CI/dev macOS version during Step 5's manual check; if it doesn't resolve or opens the wrong pane, fall back to the generic `x-apple.systempreferences:` (opens System Settings' root) rather than a guessed sub-pane identifier, per spec's "else 'Open System Settings'" fallback.

- [ ] **Step 4: Surface the tip in `HomeView`'s `tableLayout`**

In `Sources/App/Home/HomeView.swift`'s `tableLayout` (the `extension HomeView` block, inside the `VStack` after `pasteBlock(...)`, before the `HStack` containing `DownloadsTable`), add:

```swift
            if appModel.hasGrabbedOnce {
                ShareExtensionTipView(openURLSink: appModel.openURLSink)
                    .padding(.horizontal, Spacing.s6)
                    .padding(.top, Spacing.s3)
            }
```

Confirm `appModel.openURLSink` is accessible (it's declared `let openURLSink: OpenURLSink` on `AppModel` per `AppModel.swift:87` — already `internal`, not `private`, so this is a direct read, no new accessor needed).

- [ ] **Step 5: Manual verification**

Run `make`. Perform a first Grab. Confirm the tip appears above the table after the grab completes. Click "Open System Settings" and confirm it opens *something* reasonable (Extensions pane if the URL resolves, System Settings root otherwise — do not fail this check if it lands on the root, per spec's best-effort framing). Click Dismiss, relaunch the app, confirm the tip does not reappear.

- [ ] **Step 6: Run tests**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests`
Expected: PASS.

- [ ] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint .` then `mise exec -- swiftlint lint --strict`.

---

### Task 10: Full accessibility sweep (last — after every UI task above is frozen)

**Files:**
- Modify: any view flagged during the sweep (Home, Preferences, About, Onboarding, playlist picker, Downloads AppKit island, plus every new view from Tasks 2-9: `ToastHost`, `ShareExtensionTipView`, Debug menu items, `ColumnWidthReadoutView`)
- Test: manual VoiceOver + keyboard smoke per spec's testing notes; no new automated a11y test infra is introduced (none exists in the codebase to extend — confirm via `grep -rn "accessibilityLabel\|accessibilityIdentifier" Sources/App/` before assuming any pattern to follow).

**Interfaces:**
- Consumes: every existing view surface in the app.
- Produces: no new types — this task adds `.accessibilityLabel(...)`, `.accessibilityHidden(...)`, keyboard focus modifiers, and `prefers-reduced-motion` gating to existing views.

This task only starts once Tasks 1-9 are done and merged/frozen — a11y work done against UI that's still changing gets thrown away. Do not begin until the rest of this plan's tasks are complete.

- [ ] **Step 1: Keyboard navigation audit**

Manually Tab through Home (paste field → runway slots → Grab → rail → Columns → table headers → row actions), Preferences (rail → panes → controls), About (tabs → content), Onboarding (steps → buttons), the playlist picker sheet, and the Downloads AppKit island (`NSTableView` — confirm it participates in the key-view loop: `tableView.nextKeyView`/`previousKeyView` chain, since AppKit tables don't automatically join SwiftUI's focus chain the way native SwiftUI controls do). Note every control that Tab skips or that has no visible focus ring.

- [ ] **Step 2: Fix keyboard gaps found in Step 1**

For each SwiftUI control missing focus visibility, add `.focusable()` / confirm it's a native focusable control (`Button`, `TextField`) rather than a custom tap-only view. For the AppKit island specifically, check whether `DownloadsGridController`'s `tableView` already sets `refusesFirstResponder = false` (default) and whether row-action buttons (drawn as `NSButton` per `DownloadsGridCells.swift`) are individually tab-reachable — if row actions are currently only mouse-reachable, this is the task's largest single fix; budget time accordingly per spec's explicit callout ("Budget explicit VO + keyboard smoke on the AppKit grid — heavier than SwiftUI screens").

- [ ] **Step 3: VoiceOver labels on icon-only controls**

Turn on VoiceOver (`Cmd+F5`). Navigate every icon-only control: row action icons, the chip `↻` refresh icons (`HealthStrip`), the batch bar's action icons, the Columns menu trigger, the playlist group's collapse caret. Every one needs `.accessibilityLabel("...")` with a plain-language description (e.g. `↻` on the shield chip → "Restart bot-check shield"). Add missing labels directly in each view file — do not create a centralized label registry, match the codebase's existing inline-modifier style.

- [ ] **Step 4: `prefers-reduced-motion`**

Grep `Sources/App/**/*.swift` for the existing reduced-motion seam mentioned in the spec ("HealthStrip already has a seam — verify globally"): `grep -rn "reduceMotion\|accessibilityReduceMotion" Sources/App/`. Confirm the motif (`MotifView`, referenced in `MainWindow.swift:86`) stops spinning under reduced motion, and that every other spin/pulse animation added in this plan (chip busy states, if any new ones were introduced — Tasks 2-9 didn't add new spinners, so this is primarily about the pre-existing `MotifView` and `HealthChip` busy-spin) also respects the same environment value. If `MotifView` doesn't already read `\.accessibilityReduceMotion`, add it.

- [ ] **Step 5: Remark / hover-only detail keyboard reachability**

Per parent §5.4, Remark detail must not be hover-only. Confirm (in `DownloadsGridCellViews.swift` or wherever Remark is rendered) that a keyboard-focused row can reveal its Remark text via some non-hover mechanism — VoiceOver reading the cell's accessibility value is likely sufficient if the Remark text is already included in the row's accessibility description; if Remark is currently `NSView`-drawn only on hover with no accessibility value set, add one.

- [ ] **Step 6: New Phase 13 UI — sweep it too**

Explicitly re-check every view this plan added: `ToastHost` (toast text + Reveal button need VoiceOver labels and the toast itself should be announced — consider `.accessibilityAddTraits(.updatesFrequently)` or posting an `NSAccessibility.post(element:notification:.announcementRequested)` when a toast appears, since transient bottom-corner UI is easy to miss without VoiceOver), `ShareExtensionTipView` (dismiss/open buttons need labels — likely fine as plain `Button(String)` since the visible text already serves as the label, verify), Debug menu items (native `Menu`/`Button` in `.commands` — these get standard menu accessibility for free, verify with VoiceOver anyway), `ColumnWidthReadoutView` (this is a transient visual-only aid during a mouse drag — no accessibility action needed since keyboard users don't drag column dividers this way in the first place; confirm no `NSAccessibility` complaint by testing with VoiceOver running during a drag).

- [ ] **Step 7: Run full test suite one final time**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`
Expected: PASS, full suite (`GrabberKitTests` + `AppUnitTests`), confirming nothing in the a11y pass broke existing behavior.

- [ ] **Step 8: Lint**

Run: `mise exec -- swiftformat --lint .` then `mise exec -- swiftlint lint --strict`.

- [ ] **Step 9: Update phase-tracking docs**

Per this plan's Definition of Done (spec §Definition of done, last bullet): update `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1's Phase 13 stub to `*(shipped)*` (matching the style of Phase 11/12's existing stub entries), update `apps/media-grabber/ticket-backlog.md`'s Phase 13 entry to `*(shipped)*`, move this plan and its spec to `docs/superpowers/plans/archived/` and `docs/superpowers/specs/archived/` respectively via `mv` (no git commands), and update `apps/media-grabber/CLAUDE.md`'s "Next: Phase 13" line to "Next: Phase 14" plus add Phase 13 to the shipped-phases list at the top of the file, matching the exact format of the Phase 12 entry immediately before it.

---

## Self-Review Notes

- **Spec coverage:** every "Locked decisions" row and every "Architecture" subsection has a task — Toasts/Notifications (Tasks 2-4), Empty states (Task 1 + 5), Width readout (Task 6), Fonts (Task 7), Debug menu (Task 8), Share tip (Task 9), A11y (Task 10). Build order in the plan matches the spec's Build order section (fonts could run anytime relative to toasts since they're independent — plan sequences fonts first only because Task 7 is self-contained infra with no dependency on Tasks 2-6; this doesn't violate the spec's build order, which is about UI freezing before the a11y pass, not a strict task-1-before-task-2 requirement for independent subsystems).
- **Placeholder scan:** Task 5 Step 2 and Task 8 Step 3's engine-cap-liveness check are the two spots where this plan defers exact code to a discovery step rather than writing it blind — both are flagged as "verify against real code, don't guess" specifically because the planning pass either didn't have the exact file (Task 5's `TablePresentation` location) or found a genuine unknown (whether the engine's concurrency cap is live-readable) that would be fabrication to resolve without inspection. This is a bounded, explicit unknown, not a placeholder in the banned sense (no code is skipped — the surrounding wiring is fully specified).
- **Type consistency:** `ToastItem`/`ToastCenter` (Task 2) are used identically in Tasks 3-4 (`toastCenter.enqueue(ToastItem(...))`). `NotificationRouting`/`NotificationRouter`/`FakeNotificationRouter` (Task 3) share one signature (`notifyJobFailed(title:reason:) async`) throughout. `AppModel.showsTable`/`hasGrabbedOnce` (Task 1) are referenced with matching names in Task 5 and Task 9. `AppRelauncher`/`RelaunchProcessLaunching` (Task 8) are self-contained to that task with no downstream consumers to drift.
