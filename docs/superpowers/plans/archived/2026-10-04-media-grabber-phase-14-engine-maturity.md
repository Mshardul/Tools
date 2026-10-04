# MediaGrabber Phase 14 — Engine Maturity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close MediaGrabber's engine-maturity gaps — per-host adaptive concurrency, `.userReset` through `RatePolicy`, visible metadata-probe waits, and engine-owned playlist-group state — so queue behaviour matches the design instead of silent globals / UI-only roll-ups.

**Architecture:** `RateLimiter` moves its adaptive-cap trio onto a per-`RateHost` map; the scheduler keeps a global prefs ceiling and additionally skips hosts that are already at their own adaptive slot count. Circuit reset stops deleting dict entries and applies `RatePolicyEvent.userReset`. `MetadataTokenBucket.acquire` reports wait deadlines through an optional callback so `DownloadEngine` can set `JobSnapshot.probeWaitUntil` while a probe is blocked. Playlist group registry + collapse move into the engine and ride `QueueSnapshot.playlistGroups`; `AppModel` / `RowStore` consume that snapshot instead of owning a parallel registry.

**Tech Stack:** Swift 6, GrabberKit actors, XCTest, Tuist-generated Xcode project.

**Spec:** `docs/superpowers/specs/2026-10-04-media-grabber-phase-14-engine-maturity-design.md` (this plan implements it in full; read both together — the spec carries the locked decisions and rationale, this plan carries the exact files/code).

## Global Constraints

- Working name stays `MediaGrabber`. No product-name/icon work — that's Phase 17.
- No new `JobState` for probe wait — Remark + `probeWaitUntil` only (spec locked decision).
- `.shieldDown` queue halt is **dropped** — do not add `QueueHaltReason.shieldDown`.
- `.userReset` **ships** — circuit reset goes through `RatePolicy`, not out-of-band dict deletes.
- Per-host adaptive concurrency: prefs cap remains the **global** concurrent-download ceiling; host caps only limit that host's share.
- Playlist persistence API (`QueuePersisting.savePlaylistGroups` / `loadPlaylistGroups`) stays; engine becomes the writer of truth that AppModel used to hold.
- No git commands anywhere in this plan or its execution — the user commits.
- Comments: single-line only, only for non-obvious *why*. No `///` doc comments, no stacked `//` blocks.
- Every source file path below is relative to `apps/media-grabber/` unless stated otherwise.
- Lint after every task: `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict` (run from `apps/media-grabber/`).
- Test after every task: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:<Suite>` (never bare `tuist test` while debugging).
- After adding/removing files: `mise exec -- tuist generate --no-open`.

## Review Focus

- Two hosts downloading under a prefs cap of 4, each with adaptiveCap 1 after a strike — unrelated host must still get slots up to its own cap; total running never exceeds 4.
- Probe wait cancelled mid-sleep — `probeWaitUntil` clears and the job does not stay "Waiting for probe slot" forever.
- Playlist group loaded from disk whose children were all removed — group must not reappear empty on the next snapshot.
- Circuit reset while host is only in cooldown (not circuit-open) — reset is a no-op for cooldown today; keep that (only `.circuitOpen` resets), still routed through policy when it does fire.
- `setPreferencesCap` lowered below every host's adaptiveCap — every host clamps; no host keeps a stale higher cap.

---

### Task 1: Wire `.userReset` through `RatePolicy`

**Files:**
- Modify: `Sources/GrabberKit/RateLimiting/RateLimiter.swift` (`resetCircuit`, `resetAllCircuits`)
- Modify: `Tests/GrabberKitTests/RateLimiterTests.swift`

**Interfaces:**
- Consumes: `RatePolicy.next(state:event:now:tuning:)` with `.userReset` (already tested in `RatePolicyTests`).
- Produces: `resetCircuit` / `resetAllCircuits` that apply policy instead of `states[host] = nil` when the host is `.circuitOpen`.

Today `resetCircuit` only clears when `circuitOpen`, by assigning `nil`. Keep the same gate (only circuit-open hosts), but the transition must go through `RatePolicy.next(..., .userReset, ...)` and then drop the entry when the result is `.normal` (same pattern as `recordCleanSuccess`).

- [ ] **Step 1: Write the failing test**

Add to `RateLimiterTests.swift`:

```swift
func testResetCircuitUsesUserResetPolicyPath() {
    var limiter = RateLimiter(tuning: tuning(threshold: 2), preferencesCap: 6)
    limiter.recordStrike(host: yt, retryAfter: 1, lastErrorKey: "rate_limited", now: t0)
    limiter.recordStrike(
        host: yt, retryAfter: 1, lastErrorKey: "rate_limited", now: t0.addingTimeInterval(5)
    )
    XCTAssertEqual(limiter.circuitOpenHosts, [yt])
    limiter.resetCircuit(host: yt)
    XCTAssertTrue(limiter.circuitOpenHosts.isEmpty)
    XCTAssertEqual(limiter.state(for: yt), .normal)
    XCTAssertNil(limiter.displaySummary(now: t0.addingTimeInterval(999))[yt])
}
```

(Existing `testCircuitTripAndReset` may already cover emptiness — keep both; the new test pins `.normal` via `state(for:)`.)

- [ ] **Step 2: Run test to verify current behaviour still passes (or adjust expectation)**

Run: `xcodebuild … test -only-testing:GrabberKitTests/RateLimiterTests/testResetCircuitUsesUserResetPolicyPath`  
Expected: PASS already if behaviour is equivalent — then Step 3 still rewrites the implementation to use policy (behaviour-preserving refactor with the test locking the outcome). If you can distinguish policy vs nil-assign only via code review, add a `RatePolicy` spy is overkill — the rewrite in Step 3 is still mandatory per spec.

- [ ] **Step 3: Implement policy-based reset**

Replace `resetCircuit` / `resetAllCircuits` bodies:

```swift
mutating func resetCircuit(host: RateHost) {
    guard case .circuitOpen = states[host] ?? .normal else { return }
    let next = RatePolicy.next(
        state: states[host] ?? .normal,
        event: .userReset,
        now: Date(),
        tuning: tuning
    )
    states[host] = next == .normal ? nil : next
    lastErrorKey[host] = nil
}

mutating func resetAllCircuits() {
    for host in circuitOpenHosts {
        resetCircuit(host: host)
    }
}
```

Use `dependencies.clock.now` only if `RateLimiter` already has a clock — it does not today; `Date()` matches other call sites that pass `now` from the engine. Prefer threading `now: Date` into `resetCircuit(host:now:)` and update `DownloadEngine+RateControl` to pass `dependencies.clock.now` — that is the better end-state; do that if the engine call sites are one-liners.

- [ ] **Step 4: Run RateLimiterTests**

Run: `xcodebuild … test -only-testing:GrabberKitTests/RateLimiterTests`  
Expected: PASS.

- [ ] **Step 5: Lint**

Run swiftformat + swiftlint from `apps/media-grabber/`.

---

### Task 2: Per-host adaptive concurrency

**Files:**
- Modify: `Sources/GrabberKit/RateLimiting/RateLimiter.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine+RateControl.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (evaluateSchedule / effectiveCap usage)
- Modify: `Sources/GrabberKit/Download/Scheduler.swift` (only if you choose to pass an extra blocked-ID set — preferred: keep Scheduler unchanged and precompute host-cap blocks in RateControl)
- Modify: `Tests/GrabberKitTests/RateLimiterTests.swift`
- Modify: `Tests/GrabberKitTests/SchedulerTests.swift` (if SchedulerInput gains fields — prefer not)
- Modify: any `adaptiveCapForTest` callers in `EngineRateLimitTests` / `RateLimiterWiringTests`

**Interfaces:**
- Consumes: existing `recordStrike` / `recordCleanSuccess` / `setPreferencesCap`.
- Produces: `adaptiveCap(for: RateHost) -> Int`, `concurrencyReducedToOne(for: RateHost) -> Bool`, `hostCapBlockedIDs(jobs:running:now:) -> Set<UUID>` (or equivalent private helper on the engine). Global `adaptiveCap` property is removed or becomes a test-only aggregate — prefer removal and update tests to per-host.

**Design (locked by this plan):**

```text
globalSlots = preferencesCap − running.count
hostFree(host) = adaptiveCap(host) − running.count(where rateHost == host)
A queued job is schedulable only if globalSlots > 0 AND hostFree(job.rateHost) > 0
  AND not rate-blocked AND not deferred AND has metadata
```

Implement host-cap pressure by adding those job IDs into the same `blockedHostIDs` set the scheduler already consults (union of rate-blocked + host-at-cap), **or** a second set merged before `SchedulerInput` construction. Do not change `Scheduler.nextDownloads` signature unless the union approach is cleaner as a named `blockedDownloadIDs`.

- [ ] **Step 1: Write failing RateLimiter tests for per-host caps**

Replace global-cap assertions. Example shape:

```swift
func testStrikeOnOneHostDoesNotSerialiseAnother() {
    var limiter = RateLimiter(tuning: tuning(streak: 3), preferencesCap: 6)
    for _ in 0 ..< 3 { limiter.recordCleanSuccess(host: yt, now: t0) }
    XCTAssertEqual(limiter.adaptiveCap(for: yt), 3)
    XCTAssertEqual(limiter.adaptiveCap(for: vimeo), 2) // start value
    limiter.recordStrike(host: yt, retryAfter: nil, lastErrorKey: "rate_limited", now: t0)
    XCTAssertEqual(limiter.adaptiveCap(for: yt), 1)
    XCTAssertEqual(limiter.adaptiveCap(for: vimeo), 2)
    XCTAssertTrue(limiter.concurrencyReducedToOne(for: yt))
    XCTAssertFalse(limiter.concurrencyReducedToOne(for: vimeo))
}

func testCleanStreakRaisesOnlyThatHost() {
    var limiter = RateLimiter(tuning: tuning(streak: 3), preferencesCap: 4)
    for _ in 0 ..< 3 { limiter.recordCleanSuccess(host: yt, now: t0) }
    XCTAssertEqual(limiter.adaptiveCap(for: yt), 3)
    XCTAssertEqual(limiter.adaptiveCap(for: vimeo), 2)
}
```

Update `testAdaptiveCapStartsClamped`, `testSetPreferencesCapReclampsWithoutJumping`, and `displaySummary` concurrency flag tests to the per-host API. `HostRateDisplayState.concurrencyReducedToOne` must use the **host's** flag.

- [ ] **Step 2: Run tests — expect FAIL** (missing `adaptiveCap(for:)`).

- [ ] **Step 3: Implement per-host trio in `RateLimiter`**

```swift
private struct HostConcurrency {
    var adaptiveCap: Int
    var cleanStreak: Int = 0
    var strikeLoweredCap: Bool = false
}

private var concurrency: [RateHost: HostConcurrency] = [:]
```

- Lazy-create a host entry on first strike/clean using `adaptiveConcurrencyStart` clamped to `preferencesCap`.
- `adaptiveCap(for:)` returns the host entry's cap, or the start value if never touched.
- `recordStrike` / `recordCleanSuccess` mutate only that host's entry.
- `setPreferencesCap` reclamps every entry's `adaptiveCap`.
- `displaySummary` sets `concurrencyReducedToOne: concurrencyReducedToOne(for: host)`.

- [ ] **Step 4: Wire engine scheduling**

In `DownloadEngine+RateControl.swift` / evaluateSchedule path:

- Pass `cap: preferencesCap` (the global ceiling) into `SchedulerInput`, **not** `min(globalAdaptive, prefs)`.
- Union host-at-cap job IDs into the blocked set:

```swift
func hostCapBlockedIDs(running: [DownloadJob]) -> Set<UUID> {
    let runningCounts = Dictionary(grouping: running, by: { RateHost(urlString: $0.request.url) })
        .mapValues(\.count)
    return Set(jobs.filter { job in
        guard job.state == .queued else { return false }
        let host = RateHost(urlString: job.request.url)
        let limit = rateLimiter.adaptiveCap(for: host)
        return (runningCounts[host] ?? 0) >= limit
    }.map(\.id))
}
```

Remove or rewrite `effectiveCap` / `adaptiveCapForTest` to per-host test seams (`adaptiveCapForTest(_ host: RateHost)`).

- [ ] **Step 5: Update engine rate-limit tests**

Fix `EngineRateLimitTests` / `RateLimiterWiringTests` for the new API. Add one engine-level test if feasible: two hosts, prefs cap 2, strike host A → host B can still run while A is limited to 1 — use existing fake runner patterns in those suites.

- [ ] **Step 6: Run GrabberKitTests rate + scheduler suites**

Run: `xcodebuild … test -only-testing:GrabberKitTests/RateLimiterTests` and `…/SchedulerTests` and `…/EngineRateLimitTests`  
Expected: PASS.

- [ ] **Step 7: Lint**

---

### Task 3: Probe-wait visibility

**Files:**
- Modify: `Sources/GrabberKit/Download/MetadataTokenBucket.swift`
- Modify: `Sources/GrabberKit/Download/MetadataProbe.swift`
- Modify: `Sources/GrabberKit/Download/JobSnapshot.swift`
- Modify: `Sources/GrabberKit/Download/DownloadJob.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine+Launch.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine+Mutations.swift` (clear wait on probe finish / cancel)
- Modify: `Sources/App/Rows/RowStatusText.swift` (`RowRemarkText`)
- Modify: `Sources/App/Rows/RowModel.swift` (`RowFieldChanges` must notice `probeWaitUntil`)
- Test: `Tests/GrabberKitTests/MetadataTokenBucketTests.swift`
- Test: `Tests/AppUnitTests/RowStatusTextTests.swift` (or new remark test)

**Interfaces:**
- Consumes: existing live `MetadataTokenBucket` in `EngineDependencies.live`.
- Produces: `JobSnapshot.probeWaitUntil: Date?`, Remark line while waiting, bucket `acquire(onWait:)`.

- [ ] **Step 1: Failing bucket test for wait reporting**

```swift
func testAcquireReportsWaitDeadlineThenClears() async {
    let clock = FakeClock(now: Date(timeIntervalSince1970: 1000))
    let bucket = MetadataTokenBucket(limit: 1, windowSeconds: 60, clock: clock)
    await bucket.acquire(onWait: nil) // consume the only token
    var reported: [Date?] = []
    let waiter = Task {
        await bucket.acquire { reported.append($0) }
    }
    await clock.advance(seconds: 0) // allow waiter to hit sleep if FakeClock supports pending sleeps
    // Assert the last non-nil report ≈ 1000+60, then advance past window, then assert a nil clear.
    await waiter.value
    XCTAssertTrue(reported.contains { $0 != nil })
    XCTAssertEqual(reported.last!, nil) // if using Optional; adjust if you use a different callback shape
}
```

Match the real `FakeClock` API in `Tests/TestSupport` / GrabberKit tests — read `MetadataTokenBucketTests.swift` and reuse its clock pattern. If the existing fake cannot observe mid-wait, assert via a `RecordingBucket` test double injected into `MetadataProbe` instead, and keep a unit test on `MetadataTokenBucket` that only checks it eventually acquires after the window (existing tests) plus a small recording wrapper test for the callback contract.

- [ ] **Step 2: Extend the protocol**

```swift
public protocol MetadataTokenBucketing: Sendable {
    func acquire(onWait: (@Sendable (Date?) -> Void)?) async
}

public extension MetadataTokenBucketing {
    func acquire() async { await acquire(onWait: nil) }
}
```

`UnlimitedMetadataTokenBucket.acquire(onWait:)` calls `onWait?(nil)` once (or never calls — prefer one `nil` so callers clear state).

`MetadataTokenBucket`: before `clock.sleep`, compute `next = oldest.addingTimeInterval(window)`, call `onWait?(next)`; after a successful stamp append, call `onWait?(nil)`.

- [ ] **Step 3: Thread onWait through MetadataProbe → engine**

Add optional `onWait` to the probe enqueue path (concrete `MetadataProbe` method is enough if `MetadataProbing` gains a defaulted overload). In `DownloadEngine.launchProbe`:

```swift
let result = await probe.probe(url, context: context) { [weak self] until in
    Task { await self?.setProbeWait(id, until: until) }
}
```

`setProbeWait` sets `job.probeWaitUntil`, `bump()`, `emitSnapshot()`. Clear in `recordProbeResult` and on probe-task cancel.

Add `var probeWaitUntil: Date?` on `DownloadJob` and `JobSnapshot` (default `nil` in memberwise init — update every `JobSnapshot(...)` call site; test helpers use default).

- [ ] **Step 4: Remark**

In `RowRemarkText`, for `.probing`:

```swift
case .probing:
    if let until = snapshot.probeWaitUntil {
        return "Waiting for probe slot · " + CountdownFormat.mmss(until: until, now: .now)
    }
    return ""
```

Also consider `.queued` if wait can start before `markProbing` — today `markProbing` runs first; keep Remark on `.probing` only unless you observe queued-wait in practice.

Update `RowFieldChanges` to treat `probeWaitUntil` as a refreshStatus trigger.

- [ ] **Step 5: Tests + lint**

Run MetadataTokenBucketTests, RowStatusTextTests / remark tests, and a focused engine probe test if one exists. Lint.

---

### Task 4: Engine-owned playlist groups

**Files:**
- Create: `Sources/GrabberKit/Download/PlaylistGroupSnapshot.swift` (or colocate in `QueueEvent.swift` if tiny)
- Modify: `Sources/GrabberKit/Download/QueueEvent.swift` (`QueueSnapshot.playlistGroups`)
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` + new `DownloadEngine+PlaylistGroups.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` (engine API)
- Modify: `Sources/App/AppModel.swift` / `AppModelPlaylist.swift` / `AppModelRowActions.swift`
- Modify: `Sources/App/Rows/RowStore+Groups.swift` / `RowStore.swift`
- Test: `Tests/GrabberKitTests/PersistenceGroupTests.swift` (still valid)
- Create: `Tests/GrabberKitTests/EnginePlaylistGroupTests.swift`
- Modify: `Tests/AppUnitTests/RowStoreGroupTests.swift` / playlist AppModel tests

**Interfaces:**
- Consumes: `PersistedPlaylistGroup`, existing persistence load/save.
- Produces:

```swift
public struct PlaylistGroupSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let sourceURL: String
    public let isCollapsed: Bool
    public let totalCount: Int
    public let completedCount: Int
    public let failedCount: Int
    public let runningCount: Int
    public let cancellableCount: Int
    public let rollupFraction: Double
}

// DownloadEngineProtocol / DownloadEngine:
func upsertPlaylistGroup(_ group: PersistedPlaylistGroup) async
func setPlaylistGroupCollapsed(id: UUID, _ collapsed: Bool) async
func loadPlaylistGroupsFromPersistence() async  // or take [PersistedPlaylistGroup] from AppModel once at boot
```

`QueueSnapshot` gains `playlistGroups: [PlaylistGroupSnapshot]` (default `[]` for call-site churn control).

Roll-up counts are computed in the engine when emitting a snapshot from child jobs that share `playlistGroupID`, using the same predicates `RowStore` uses today (`completed` / failed / running / cancellable). Port those predicates into GrabberKit (pure functions) so UI and engine share one definition — put them on `PlaylistGroupSnapshot` as `static func rollup(from jobs: [JobSnapshot], registry: PersistedPlaylistGroup) -> PlaylistGroupSnapshot`.

- [ ] **Step 1: Failing roll-up unit test (pure)**

```swift
func testPlaylistGroupSnapshotRollupCountsChildren() {
    let id = UUID()
    let registry = PersistedPlaylistGroup(id: id, title: "PL", sourceURL: "https://x", isCollapsed: false)
    let jobs = [
        // build JobSnapshots with playlistGroupID: id and states completed/failed/running
    ]
    let snap = PlaylistGroupSnapshot.rollup(from: jobs, registry: registry)
    XCTAssertEqual(snap.totalCount, jobs.count)
    XCTAssertEqual(snap.completedCount, /* … */)
    XCTAssertEqual(snap.isCollapsed, false)
}
```

- [ ] **Step 2: Implement `PlaylistGroupSnapshot` + `QueueSnapshot` field**

- [ ] **Step 3: Engine registry**

Engine stores `[UUID: PersistedPlaylistGroup]`. `upsertPlaylistGroup` inserts/updates and persists via `dependencies.persistence.savePlaylistGroups(Array(registry.values))`. `setPlaylistGroupCollapsed` updates `isCollapsed`, persists, `emitSnapshot()`. Snapshot emission maps registry → rollup with current jobs; drop registry entries with zero live children (same filter AppModel `loadPlaylistGroups` uses today).

- [ ] **Step 4: Point AppModel / RowStore at engine snapshots**

- `registerPlaylistGroup` → `await engine.upsertPlaylistGroup(...)` (remove `AppModel.playlistGroups` append as source of truth; keep a cache only if UI still needs sync access, otherwise delete the array).
- Collapse toggle → `await engine.setPlaylistGroupCollapsed`.
- On snapshot apply: `rowStore.applyGroups(from: snapshot.playlistGroups)` — adapt `applyGroups` to accept `[PlaylistGroupSnapshot]` or map to `PersistedPlaylistGroup` + prefer engine roll-up fields when building `PlaylistGroup` UI models (avoid double-counting: if snapshot already has counts, `RowStore` should use them instead of recomputing).

Preferred end-state: `RowStore` uses engine-provided counts/collapse and only handles visibility/filter/sort of children.

- [ ] **Step 5: Engine + App unit tests**

Cover: upsert → snapshot contains group; collapse flips `isCollapsed` on next snapshot; removing all children drops the group from the next snapshot after prune; AppModel playlist submit still registers a group.

- [ ] **Step 6: Lint + full GrabberKitTests + AppUnitTests playlist/group suites**

---

### Task 5: Drop `.shieldDown` parking + phase-tracking docs

**Files:**
- Modify: `docs/state-flow.md` §4 — ensure `.shieldDown` row is gone (already removed in the design pass; verify; add a one-line note under parked table that halt-on-dead-shield was rejected in Phase 14 if useful).
- Modify: parent §12.1 Phase 14 stub only when shipping (leave `*(scope locked)*` until the phase completes — this task runs at end of implementation and flips to `*(shipped)*`).
- Modify: `apps/media-grabber/ticket-backlog.md`, `apps/media-grabber/CLAUDE.md` — mark Phase 14 shipped, Next: Phase 15.
- Move: design + this plan to `docs/superpowers/{specs,plans}/archived/` via `mv` (no git).

- [ ] **Step 1: Verify state-flow has no `.shieldDown` park row**

- [ ] **Step 2: Run full test suite**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`  
Expected: PASS.

- [ ] **Step 3: Lint**

- [ ] **Step 4: Update phase-tracking docs + archive**

Same style as Phase 13 ship: parent stub `*(shipped)*`, backlog, CLAUDE Next → Phase 15, `mv` spec + plan into archived.

---

## Self-Review Notes

- **Spec coverage:** `.userReset` → Task 1; per-host adaptive concurrency → Task 2; probe-wait visibility → Task 3; playlist-group engine state → Task 4; `.shieldDown` drop + DoD docs → Task 5. Sibling phases 15–17 are documentation-only here (already stubbed in parent).
- **Placeholder scan:** Task 3's FakeClock mid-wait assertion tells the implementer to match the real fake API — not a skipped test. Task 4's JobSnapshot fixtures say "build snapshots" — implementer copies helpers from `RowStoreGroupTests` / `AppModelTestHelpers.jobSnapshot()`.
- **Type consistency:** `adaptiveCap(for:)`, `probeWaitUntil`, `PlaylistGroupSnapshot`, `upsertPlaylistGroup` names are stable across tasks.
- **Review Focus:** each line maps to Task 2 (multi-host caps + prefs clamp), Task 3 (cancel clears wait), Task 4 (empty group prune), Task 1 (reset only circuit-open).
