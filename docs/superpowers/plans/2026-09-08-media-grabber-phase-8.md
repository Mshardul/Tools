# MediaGrabber Phase 8 — Playlist — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** YouTube `PL` playlist pages open a picker, then enqueue one job per checked video under a group header; watch URLs stay one video.

**Architecture:** Classify the paste first. Playlist pages get one `-J --flat-playlist` dump (token-bucketed). Add M batch-submits independent jobs with `playlistGroupID` + `playlistIndex`. `RowStore` aggregates the header/spine. Probes are cancellable per job.

**Tech Stack:** Swift 6, Tuist, XCTest. Targets: `GrabberKit`, `MediaGrabber`, `TestSupport`, `GrabberKitTests`, `AppUnitTests`.

**Spec:** `docs/superpowers/specs/2026-09-08-media-grabber-phase-8.md` — read it alongside this plan. Every task's "why" is there; this plan is the "how".

## Global Constraints

- **No git.** This plan contains no `git` commands. Each task ends by running lint + tests and handing the changed files to the user. Do not create branches, do not commit, do not stage.
- **No phase / ticket / epic numbers anywhere in source or UI copy.** Not in comments, not in log strings, not in SwiftUI `Text`. The spec and this plan are the only places "Phase 8" appears.
- **Comments: single-line only, only the *why*, only when names don't carry it.** No `///`. No stacked `//` blocks. Default to zero comments. `// MARK:` is fine.
- **UI copy:** never "POT", "yt-dlp", or `player_client` in a user-visible string (existing onboarding "yt-dlp is missing" is unchanged). Playlist copy is spec §10.
- **Swift 6 concurrency:** `NSLock` banned in async. `LockedBox` is TestSupport-only. Actors reentrant across `await`. `XCTestCase` is not `Sendable`.
- **Lint after every task:** from `apps/media-grabber/`: `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict`. Traps: `function_body_length` 50, `type_body_length` 250, `cyclomatic_complexity` 10, `opening_brace` vs swiftformat — extract helpers.
- **Build after adding/removing files:** `mise exec -- tuist generate --no-open` from `apps/media-grabber/`.
- **Test command:** from `apps/media-grabber/`: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`. Single suite: `-only-testing:GrabberKitTests/<SuiteName>` or `-only-testing:AppUnitTests/<SuiteName>`. Do NOT use `tuist test` while developing. The workspace file is gitignored — generate first if missing.
- **Engine tests are not `@MainActor`.** Read state via `await engine.currentSnapshot()` or `EventCollector`.
- **Test names carry no phase number.**
- **Do not use `XCTAssertTrue(await …)`** — bind to a `let`, then assert.
- All source paths below are relative to `apps/media-grabber/` unless they start with `docs/`.
- **`playlistGroupID` already exists** on `JobSnapshot` / `PersistedJob` / `DownloadJob.snapshot` (hardcoded `nil`). Fill it; do not add a second group-id field.
- **Do not add `playlist` / `PlaylistSelection` to `DownloadRequest`.**
- **Do not call `--playlist-items`.** Downloads stay `--no-playlist` per watch URL.
- **`EngineFixture.engine(...)`** lives in `Tests/GrabberKitTests/DownloadEngineTestHelpers.swift`.

## Lint traps (apply the fix pre-emptively)

- `swiftlint cyclomatic_complexity` (limit 10) — URL classify and dump decode will trip this; split into helpers (`isWatchPath`, `isChannelVideosPath`, `watchURL(from:)`).
- `swiftlint function_body_length` (limit 50) — `submitPlaylistItems` and `recomputeVisible` will trip; hoist.
- `swiftlint type_body_length` (limit 250) — `RowStoreTests`, `PersistenceTests`, `AppFakes.FakeEngine` — split a sibling `*MoreTests.swift` or extract helpers rather than stuffing more tests into a 250-line type.
- `swiftformat` vs `opening_brace` on wrapped `if` — extract a named predicate.

## File Structure

**New — `GrabberKit/Download/`:**

| File | Responsibility |
|---|---|
| `PlaylistLink.swift` | `PlaylistLinkKind` + `PlaylistLink.classify`. |
| `PlaylistDump.swift` | `PlaylistDump`, `PlaylistEntry`, JSON decode. |
| `MetadataTokenBucket.swift` | `MetadataTokenBucketing`, `UnlimitedMetadataTokenBucket`, `MetadataTokenBucket`. |
| `PlaylistSubmitItem.swift` | Batch enqueue item (request, force, prefetch, group id, index). |

**Modified — `GrabberKit`:**

| File | Change |
|---|---|
| `Model/EngineTuning.swift` | `metadataProbeLimit` (3), `metadataProbeWindowSeconds` (60) + env keys. |
| `Download/MetadataProbe.swift` | Bucket acquire; `probePlaylist`; cancel-safe tail; `MetadataProbing` grows `probePlaylist`. |
| `Download/JobSnapshot.swift` | `playlistIndex: Int? = nil` after `playlistGroupID`. |
| `Download/DownloadJob.swift` | Store `playlistGroupID` / `playlistIndex`; `snapshot` writes them. |
| `Model/PersistedJob.swift` | `playlistIndex`; decodeIfPresent. |
| `Download/DownloadEngine+State.swift` | Persist/restore group id + index (stop forcing `nil`). |
| `Download/DownloadEngineProtocol.swift` | `previewPlaylist`, `submitPlaylistItems`; `NoopPersisting` groups. |
| `Download/DownloadEngine+Preview.swift` | `previewPlaylist`. |
| `Download/DownloadEngine.swift` | Batch submit; cancel probing via `probeTask`. |
| `Download/DownloadEngine+Mutations.swift` | `recordProbeResult` ignores `state != .probing`. |
| `Download/DownloadEngine+Launch.swift` | Probe cancel already via `probeTask` once cancel() points at it. |
| `Model/Persistence.swift` | `QueueFile.groups`; merge jobs+groups; `savePlaylistGroups` / `loadPlaylistGroups`. |
| `Logging/LogEvent.swift` | `playlistEnqueued(groupID:count:)`; exhaustive switches. |

**Modified — App:**

| File | Change |
|---|---|
| `AppModel.swift` | Classify; `ResolvedLink`; picker; registry; Add M; restore groups. |
| `AppModelDialogs.swift` | Unsupported-link copy; cancel-all confirm. |
| `AppModelRowActions.swift` | Group pause/retry/cancel-all. |
| `Home/HomeView.swift` | Picker sheet; resolved enum. |
| `Home/PlaylistPickerModel.swift` | **New.** Checks, warnings, footer, filter. |
| `Home/PlaylistPickerView.swift` | **New.** Modal UI. |
| `Rows/RequestBuilder.swift` | `build(from: PlaylistEntry, …)`. |
| `Rows/RowStore.swift` | Fill `PlaylistGroup`; `visibleItems`; 10% buckets. |
| `Table/DownloadsTable.swift` | Header + spine + group actions. |
| `Table/PlaylistGroupHeader.swift` | **New.** Header row. |
| `Table/DownloadRow.swift` | Child indent + spine when grouped. |

**Tests:** new suites named in each task. Both `FakeEngine`s (`AppFakes.swift`, `QuitCoordinatorTests.swift`). Both `FakeMetadataProbe`s (TestSupport + AppFakes). `NoopPersisting`.

**Docs (Task 16):** `screens.html` §5; verify parent / design-system / backlog (already updated in the design pass — verify, fill mockup).

**Fixture:** `Tests/GrabberKitTests/Fixtures/ytdlp-J-flat-playlist.json`.

---

## Task 0: `EngineTuning` probe budget

**Files:**
- Modify: `Sources/GrabberKit/Model/EngineTuning.swift`
- Test: `Tests/GrabberKitTests/EngineTuningTests.swift` (extend; split sibling if `type_body_length`)

**Interfaces:**
- Consumes: existing defaulted `init` tail (`potRestartBackoffSeconds`).
- Produces: `metadataProbeLimit: Int` (default 3), `metadataProbeWindowSeconds: Int` (default 60); `resolved()` reads `MG_METADATA_PROBE_LIMIT`, `MG_METADATA_PROBE_WINDOW_SECONDS`.

- [ ] **Step 1: Write the failing test**

```swift
func testMetadataProbeTuningDefaults() {
    XCTAssertEqual(EngineTuning.default.metadataProbeLimit, 3)
    XCTAssertEqual(EngineTuning.default.metadataProbeWindowSeconds, 60)
}

func testMetadataProbeTuningReadsEnv() {
    let tun = EngineTuning.resolved(environment: [
        "MG_METADATA_PROBE_LIMIT": "5",
        "MG_METADATA_PROBE_WINDOW_SECONDS": "90"
    ])
    XCTAssertEqual(tun.metadataProbeLimit, 5)
    XCTAssertEqual(tun.metadataProbeWindowSeconds, 90)
}
```

- [ ] **Step 2: Run to see fail** — `xcodebuild … -only-testing:GrabberKitTests/EngineTuningTests`
- [ ] **Step 3:** Add the two stored properties as **defaulted `init` params at the end** so existing `EngineTuning(ytDlp:backoffLadder:backoffCap:)` call sites still compile. Set them on `.default`. Parse in `resolved()` with the existing `intValue` helper at the `return EngineTuning(` site (do not widen `RateLimitTuningValues`).
- [ ] **Step 4: Tests pass.** Lint.
- [ ] **Step 5: Hand files to the user.** No git.

---

## Task 1: `PlaylistLink`

**Files:**
- Create: `Sources/GrabberKit/Download/PlaylistLink.swift`
- Test: `Tests/GrabberKitTests/PlaylistLinkTests.swift`

**Interfaces:**
- Consumes: `RateHost(urlString:).canonical`.
- Produces:

```swift
public enum PlaylistLinkKind: Sendable, Equatable {
    case singleVideo
    case youtubePlaylist
    case youtubeUnsupported
}

public enum PlaylistLink {
    public static func classify(_ urlString: String) -> PlaylistLinkKind
}
```

- [ ] **Step 1: Write the failing tests** (trim; YouTube family hosts from `RateHost` aliases):

```swift
func testWatchWithListIsSingleVideo() {
    XCTAssertEqual(
        PlaylistLink.classify("https://www.youtube.com/watch?v=abc123abc12&list=PLdeadbeef"),
        .singleVideo
    )
}

func testShortsAndYoutuBeAreSingleVideo() {
    XCTAssertEqual(PlaylistLink.classify("https://youtu.be/abc123abc12"), .singleVideo)
    XCTAssertEqual(
        PlaylistLink.classify("https://www.youtube.com/shorts/abc123abc12"),
        .singleVideo
    )
}

func testPLPlaylistPage() {
    XCTAssertEqual(
        PlaylistLink.classify("https://www.youtube.com/playlist?list=PLbpi6ZahtOH6"),
        .youtubePlaylist
    )
    XCTAssertEqual(
        PlaylistLink.classify("https://music.youtube.com/playlist?list=PLbpi6ZahtOH6"),
        .youtubePlaylist
    )
}

func testMixWatchLaterLikedUploadsChannelUnsupported() {
    let samples = [
        "https://www.youtube.com/playlist?list=RDxxxxxxxx",
        "https://www.youtube.com/playlist?list=WL",
        "https://www.youtube.com/playlist?list=LL",
        "https://www.youtube.com/playlist?list=UUxxxxxxxx",
        "https://www.youtube.com/playlist?list=OLxxxxxxxx",
        "https://www.youtube.com/@foo/videos",
        "https://www.youtube.com/channel/UCxxx/videos",
        "https://www.youtube.com/c/foo/videos",
        "https://www.youtube.com/user/foo/videos"
    ]
    for url in samples {
        XCTAssertEqual(PlaylistLink.classify(url), .youtubeUnsupported, url)
    }
}

func testNonYouTubeIsSingleVideo() {
    XCTAssertEqual(
        PlaylistLink.classify("https://archive.org/details/foo"),
        .singleVideo
    )
}
```

- [ ] **Step 2: Run to see fail.**
- [ ] **Step 3: Implement.** Trim whitespace. If `RateHost` canonical is not `"youtube"` → `.singleVideo`. Parse `URLComponents`. Helpers (keep cyclomatic down):

  - `isWatchPath`: path has `/watch`, `/shorts/`, `/live/`, `/embed/`, or host is youtu.be and path is not `/playlist`.
  - `isChannelVideosPath`: last path component is `videos` (and path contains `/@`, `/channel/`, `/c/`, `/user/`, or is exactly `/videos`).
  - `list` query: if path contains `/playlist` and list hasPrefix `"PL"` → `.youtubePlaylist`; any other `/playlist` → `.youtubeUnsupported`.
  - Watch-like paths win over `list=` (spec: `&list=` ignored).

- [ ] **Step 4: Tests pass.** Lint. `tuist generate` after adding the file.
- [ ] **Step 5: Hand files to the user.** No git.

---

## Task 2: `PlaylistDump` decode

**Files:**
- Create: `Sources/GrabberKit/Download/PlaylistDump.swift`
- Create: `Tests/GrabberKitTests/Fixtures/ytdlp-J-flat-playlist.json`
- Test: `Tests/GrabberKitTests/PlaylistDumpTests.swift`

**Interfaces:**
- Produces:

```swift
public struct PlaylistDump: Sendable, Equatable {
    public var title: String
    public var uploader: String?
    public var extractor: String?
    public var sourceURL: String
    public var entries: [PlaylistEntry]
}

public struct PlaylistEntry: Sendable, Equatable {
    public var watchURL: String
    public var title: String
    public var durationSeconds: Int?
    public var thumbnailURL: String?
    public var extractor: String?
    public var playlistIndex: Int
}

public enum PlaylistDump {
    public static func decode(_ stdout: String, pasteURL: String) -> Result<PlaylistDump, MetadataError>
    public static func decodeForTest(_ stdout: String, pasteURL: String) -> Result<PlaylistDump, MetadataError>
}
```

(`decodeForTest` can be `decode` if the type is already a public enum namespace — if that collides with the struct name, use `enum PlaylistDumpDecoder` **or** static methods on the struct: `PlaylistDump.decode`. Prefer **`extension PlaylistDump { static func decode(...) }`** and drop the extra enum.)

- [ ] **Step 1: Fixture** `ytdlp-J-flat-playlist.json`:

```json
{
  "_type": "playlist",
  "title": "Focus — deep work",
  "uploader": "Ambient Dept",
  "extractor": "youtube",
  "webpage_url": "https://www.youtube.com/playlist?list=PLbpi6ZahtOH6",
  "entries": [
    {
      "id": "aaaaaaaaaaa",
      "title": "01 — Sunrise Loop",
      "duration": 252,
      "ie_key": "Youtube",
      "playlist_index": 1,
      "thumbnail": "https://i.ytimg.com/vi/aaaaaaaaaaa/default.jpg"
    },
    {
      "_type": "playlist",
      "title": "nested"
    },
    {
      "id": "bbbbbbbbbbb",
      "title": "02 — Tidewater",
      "duration": 390.4,
      "webpage_url": "https://www.youtube.com/watch?v=bbbbbbbbbbb",
      "playlist_index": 2
    }
  ]
}
```

- [ ] **Step 2: Failing tests**

```swift
func testDecodesEntriesAndBuildsWatchURLFromId() throws {
    let json = Fixture.text("ytdlp-J-flat-playlist.json")
    let dump = try PlaylistDump.decode(json, pasteURL: "https://example.com/x").get()
    XCTAssertEqual(dump.title, "Focus — deep work")
    XCTAssertEqual(dump.uploader, "Ambient Dept")
    XCTAssertEqual(dump.sourceURL, "https://www.youtube.com/playlist?list=PLbpi6ZahtOH6")
    XCTAssertEqual(dump.entries.count, 2)
    XCTAssertEqual(dump.entries[0].watchURL, "https://www.youtube.com/watch?v=aaaaaaaaaaa")
    XCTAssertEqual(dump.entries[0].durationSeconds, 252)
    XCTAssertEqual(dump.entries[0].extractor, "Youtube")
    XCTAssertEqual(dump.entries[0].playlistIndex, 1)
    XCTAssertEqual(dump.entries[1].watchURL, "https://www.youtube.com/watch?v=bbbbbbbbbbb")
    XCTAssertEqual(dump.entries[1].durationSeconds, 390)
}

func testEmptyEntriesIsMalformed() {
    let json = #"{"title":"Empty","_type":"playlist","entries":[]}"#
    XCTAssertEqual(
        PlaylistDump.decode(json, pasteURL: "https://x"),
        .failure(.malformedOutput)
    )
}
```

Use the same `Fixture.text` helper other probe tests use (TestSupport). If the helper wants a name without `.json`, match `MetadataProbeTests`'s bundle lookup.

- [ ] **Step 3: Implement decode.** Skip nested `_type == playlist`. Watch URL: `webpage_url` or `url` if it has an `http` prefix, else YouTube `id` → `https://www.youtube.com/watch?v=<id>`, else skip. Title: `title` or `id`. Duration: same coercion as `MetadataProbe.durationSeconds` — **extract a shared `JSONDuration` helper** in `PlaylistDump.swift` or call into `MetadataProbe` if you expose the existing private as `package`/`internal` for tests only. Do **not** duplicate a third copy later; if extracting from `MetadataProbe` is a bigger diff, copy the 15-line function into `PlaylistDump` as `private static func durationSeconds` (YAGNI vs a new file — copy is OK this task). Extractor: entry `ie_key` ?? `extractor` ?? playlist extractor. Index: `playlist_index` int or 1-based enumeration of **kept** entries. `sourceURL` = `webpage_url` ?? `pasteURL`. Missing title on the playlist object → `.malformedOutput`.
- [ ] **Step 4: Tests pass.** Lint. Generate.
- [ ] **Step 5: Hand files to the user.** No git.

---

## Task 3: `MetadataTokenBucket`

**Files:**
- Create: `Sources/GrabberKit/Download/MetadataTokenBucket.swift`
- Test: `Tests/GrabberKitTests/MetadataTokenBucketTests.swift`

**Interfaces:**
- Consumes: Task 0 tuning numbers (tests pass 3 and 60 explicitly); `Clock` / `FakeClock`.
- Produces:

```swift
public protocol MetadataTokenBucketing: Sendable {
    func acquire() async
}

public struct UnlimitedMetadataTokenBucket: MetadataTokenBucketing {
    public init() {}
    public func acquire() async {}
}

public actor MetadataTokenBucket: MetadataTokenBucketing {
    public init(limit: Int, windowSeconds: Int, clock: any Clock)
    public func acquire() async
}
```

- [ ] **Step 1: Failing tests**

```swift
func testThirdAcquireIsImmediateFourthWaitsUntilWindowRolls() async {
    let clock = FakeClock(now: Date(timeIntervalSince1970: 0))
    let bucket = MetadataTokenBucket(limit: 3, windowSeconds: 60, clock: clock)
    await bucket.acquire()
    await bucket.acquire()
    await bucket.acquire()
    let fourth = Task { await bucket.acquire() }
    await Task.yield()
    XCTAssertFalse(fourth.isCancelled)
    var finished = false
    Task { _ = await fourth.value; finished = true }
    await Task.yield()
    XCTAssertFalse(finished)
    clock.advance(by: .seconds(60))
    _ = await fourth.value
    XCTAssertTrue(finished)
}
```

Cancel test: a `Clock` in the test file whose `sleep` loops `Task.yield()` until `Task.isCancelled` or `now >= deadline`. Start `acquire` after filling the window; cancel that `Task`; assert it returns and a following `acquire` still waits (no stolen token).

Do **not** use `XCTAssertTrue(await …)`.

- [ ] **Step 2: Run to see fail.**
- [ ] **Step 3: Implement.** Rolling stamps. `acquire`: prune stamps older than `now - window`; if `count < limit`, append `now` and return; else `await clock.sleep(until: oldest + window)` and loop. **If `Task.isCancelled` after sleep or at loop head, return without appending.** `limit = max(1, limit)`.
- [ ] **Step 4: Tests pass.** Lint. Generate.
- [ ] **Step 5: Hand files to the user.** No git.

---

## Task 4: `MetadataProbe` playlist + bucket + cancel

**Files:**
- Modify: `Sources/GrabberKit/Download/MetadataProbe.swift`
- Modify: `Tests/TestSupport/FakeMetadataProbe.swift`
- Modify: `Tests/AppUnitTests/Support/AppFakes.swift` (`FakeMetadataProbe`)
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` (`EngineDependencies.live` constructs the paced bucket)
- Test: `Tests/GrabberKitTests/MetadataProbePlaylistTests.swift` (new; do not balloon `MetadataProbeTests`)

**Interfaces:**
- Consumes: Task 2 decode, Task 3 bucket.
- Produces: `MetadataProbing.probePlaylist(_ url: String, context: ExtractorContext) async -> Result<PlaylistDump, MetadataError>`; `MetadataProbe.init(ytDlpURL:runner:bucket:)` with `bucket: any MetadataTokenBucketing = UnlimitedMetadataTokenBucket()`.

- [ ] **Step 1: Protocol + fakes.** Add `probePlaylist` to `MetadataProbing` with a protocol extension defaulting to `.failure(.malformedOutput)` **or** implement it on both fakes returning `.failure(.malformedOutput)` / a scripted dump. Prefer **explicit fake methods** (no silent default that hides a missed live path). TestSupport fake: store `playlistResult` like video `fallback`. AppFakes fake: same.
- [ ] **Step 2: Failing tests** (FakeProcessRunner + unlimited bucket):

  - `probePlaylist` argv contains `-J`, `--flat-playlist`, `--no-warnings`, `--no-update`, and the URL; does **not** contain `--no-playlist`.
  - Fixture stdout → dump title + 2 entries.
  - Cancel in-flight: `runner.perRunDelay = .seconds(5)`; `let task = Task { await probe.probe(url) }`; yield; `task.cancel()`; `_ = await task.value`. Assert `runner.cancelledCount >= 1`. Do **not** add a `MetadataError` case. On `wasCancelled` / `Task.isCancelled`, return without calling `classify` (use `.failure(.malformedOutput)` as the Result filler — Home's paste `Task` already bails on cancel; engine Task 10 ignores non-`.probing`).
  - Tail: probe A delayed; start B; cancel A; B still succeeds from a second script.

- [ ] **Step 3: Implement `runProbe` / `runPlaylistProbe`.** `await bucket.acquire()` after the tail predecessor and **check `Task.isCancelled` after acquire**. Playlist argv: `["-J", "--flat-playlist", "--no-warnings", "--no-update"] + extractorFlags + [url]`. Decode via Task 2. On `wasCancelled`, skip `classify` and return `.failure(.malformedOutput)`. Tail `Task` still finishes so B is not stuck.
- [ ] **Step 4:** `EngineDependencies.live` — `let bucket = MetadataTokenBucket(limit: tuning.metadataProbeLimit, windowSeconds: tuning.metadataProbeWindowSeconds, clock: SystemClock())`; `MetadataProbe(ytDlpURL:runner:bucket:)`. Tests constructing `MetadataProbe(ytDlpURL:runner:)` stay unlimited.
- [ ] **Step 5: Tests pass.** Lint. Generate.
- [ ] **Step 6: Hand files to the user.** No git.

---

## Task 5: `playlistIndex` + fill `playlistGroupID`

**Files:**
- Modify: `Sources/GrabberKit/Download/JobSnapshot.swift`
- Modify: `Sources/GrabberKit/Download/DownloadJob.swift`
- Modify: `Sources/GrabberKit/Model/PersistedJob.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine+State.swift` (`persistedJob` / `downloadJob(from:)`)
- Modify: `Sources/App/Rows/RowModel.swift` if it forwards snapshot fields (only if needed)
- Test: `Tests/GrabberKitTests/PersistenceTests.swift` or new `PersistedJobPlaylistTests.swift`

**Interfaces:**
- Produces: `JobSnapshot.playlistIndex: Int?` defaulted `nil` (existing labeled inits compile). `DownloadJob.playlistGroupID` / `playlistIndex` stored, `snapshot` writes them (today `playlistGroupID: nil`). `PersistedJob.playlistIndex` decodeIfPresent. Restore copies both onto `DownloadJob`.

- [ ] **Step 1: Failing test** — persist a job with `playlistGroupID` + `playlistIndex` 3; encode/decode; `XCTAssertEqual`. Also: `DownloadJob.snapshot` includes the id (construct a job, set the two fields, snapshot).
- [ ] **Step 2: Run to see fail.**
- [ ] **Step 3: Implement.** Default `playlistIndex: Int? = nil` on `JobSnapshot.init` **after** `playlistGroupID`. `DownloadJob.init` leaves both nil. `persistedJob(from:)` passes `job.playlistGroupID` and `job.playlistIndex` (stop `nil`). `downloadJob(from:)` assigns both.
- [ ] **Step 4: Tests pass.** Full `GrabberKitTests` if many fixtures break (they should not — defaulted param). Lint.
- [ ] **Step 5: Hand files to the user.** No git.

---

## Task 6: `LogEvent.playlistEnqueued`

**Files:**
- Modify: `Sources/GrabberKit/Logging/LogEvent.swift` (`key`, `category`, `fields`, `jobID` if needed)
- Test: `Tests/GrabberKitTests/LogEventPlaylistTests.swift`

**Interfaces:**
- Produces: `case playlistEnqueued(groupID: UUID, count: Int)` — `key`: `"playlist.enqueued"`; category `.scheduler`; fields `group_id`, `count`.

- [ ] **Step 1:** Add the test asserting `key` / `category` / `fields`. Compile will fail until all switches are exhaustive — that **is** the implementation.
- [ ] **Step 2: Implement the case in every switch** (`key`, `category`, `fields`, `jobID` → `nil`).
- [ ] **Step 3: Tests pass.** Lint.
- [ ] **Step 4: Hand files to the user.** No git.

---

## Task 7: Persistence groups merge

**Files:**
- Modify: `Sources/GrabberKit/Model/Persistence.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` (`QueuePersisting`, `NoopPersisting`)
- Test: `Tests/GrabberKitTests/PersistenceGroupTests.swift` (new)

**Interfaces:**
- Produces:

```swift
public struct PersistedPlaylistGroup: Codable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var sourceURL: String
    public var isCollapsed: Bool
}

public struct QueueFile: Codable, Sendable {
    public var schemaVersion: Int
    public var jobs: [PersistedJob]
    public var groups: [PersistedPlaylistGroup]
}

public protocol QueuePersisting: Sendable {
    func saveQueue(_ jobs: [PersistedJob])
    func saveHistory(_ jobs: [PersistedJob])
    func saveColumns(_ config: ColumnConfig)
    func savePlaylistGroups(_ groups: [PersistedPlaylistGroup])
    func flushNow() async
    func loadQueue() -> [PersistedJob]
    func loadHistory() -> [PersistedJob]
    func loadColumns() -> ColumnConfig?
    func loadPlaylistGroups() -> [PersistedPlaylistGroup]
}
```

`QueueFile.groups` `decodeIfPresent` → `[]`. Schema version stays **1**. `NoopPersisting.savePlaylistGroups` no-op; `loadPlaylistGroups` → `[]`.

- [ ] **Step 1: Failing tests**

  - Round-trip `QueueFile` with two jobs + one group.
  - JSON **without** `groups` key decodes `groups == []`.
  - Merge: `saveQueue([job])` then `flushNow`; `savePlaylistGroups([group])` then `flushNow`; `loadQueue()` still has the job **and** `loadPlaylistGroups()` has the group (jobs-only write must not wipe groups). Reverse order too.

- [ ] **Step 2: Run to see fail.**
- [ ] **Step 3: Implement.** `Pending` gains `groups`. Keep `lastQueueJobs` / `lastPlaylistGroups` on `Persistence` (in-memory, updated whenever either saves). `writePending` for `queue.json` writes `QueueFile(schemaVersion: 1, jobs: pending.queue ?? lastQueueJobs, groups: pending.groups ?? lastPlaylistGroups)`. On `loadQueue` / `loadPlaylistGroups`, read the same file (decode `QueueFile`); `loadQueue` can keep using `loadJobs` **if** `QueueFile` still has `jobs` — then `loadPlaylistGroups` decodes the same path and returns `file.groups`. If `loadJobs` generic `SchemaVersioned` assumes no groups, **stop using it for queue.json** and decode `QueueFile` directly in both loaders (history stays `HistoryFile`).
- [ ] **Step 4: Tests pass.** Existing `test_roundTripQueueFile` — update encode if `groups` is required (always encode `[]`). Lint.
- [ ] **Step 5: Hand files to the user.** No git.

---

## Task 8: Protocol `previewPlaylist` + `submitPlaylistItems` + fakes

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift`
- Create: `Sources/GrabberKit/Download/PlaylistSubmitItem.swift`
- Modify: `Tests/AppUnitTests/Support/AppFakes.swift` `FakeEngine`
- Modify: `Tests/GrabberKitTests/QuitCoordinatorTests.swift` private `FakeEngine`

**Interfaces:**
- Produces:

```swift
public struct PlaylistSubmitItem: Sendable {
    public var request: DownloadRequest
    public var force: Bool
    public var prefetched: MediaMetadata?
    public var playlistGroupID: UUID
    public var playlistIndex: Int
}

func previewPlaylist(_ url: String) async -> Result<PlaylistDump, MetadataError>
func submitPlaylistItems(_ items: [PlaylistSubmitItem]) async -> [UUID]
```

Fakes: `previewPlaylist` default `.failure(.malformedOutput)`; `submitPlaylistItems` default `[]`. Record `previewPlaylist` URLs like `preview`. Compile the whole test target.

- [ ] **Step 1:** Add the methods with empty/fake bodies so the **workspace compiles**. `DownloadEngine` stubs: `previewPlaylist` → `.failure(.malformedOutput)`; `submitPlaylistItems` → `[]`. Real bodies are Task 9.
- [ ] **Step 2:** `xcodebuild … test` smoke (or build) — must compile.
- [ ] **Step 3: Lint.** Generate if new file.
- [ ] **Step 4: Hand files to the user.** No git.

---

## Task 9: Engine `previewPlaylist` + `submitPlaylistItems`

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine+Preview.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (`submit` stays; add batch)
- Test: `Tests/GrabberKitTests/EnginePlaylistSubmitTests.swift`

**Interfaces:**
- Consumes: Task 4 `probe.probePlaylist`, Task 5 job fields, Task 6 log, Task 8 types.
- Produces: real `previewPlaylist` (same gates as `preview`: network halt, host block, `makeContext` attempt 0); `submitPlaylistItems` appends all jobs then **one** snapshot + one `evaluateSchedule`.

- [ ] **Step 1: Failing tests** (EngineFixture + FakeMetadataProbe playlist result + FakeProcessRunner unused):

  - `previewPlaylist` on success returns dump; blocked host → `.hostBlocked`; `queueHalt == .networkDown` → `.network`.
  - Submit two items same `playlistGroupID`, indices 1 and 2, prefetch title/extractor/duration → snapshot has two jobs, both group ids set, **neither** goes `.probing` (scheduler skip). Use `EventCollector` or `currentSnapshot`. Assert **one** revision bump for the batch (revision increases once, not twice) — `submitPlaylistItems` must not call `emitSnapshot` per item.
  - `force: true` on a duplicate URL still creates a second job.
  - `force: false` duplicate in the batch: skip that item, still enqueue the rest; returned UUID array omits the skip.
  - Log: `playlistEnqueued` with count 2 (inject `LogWriter` to a temp dir or a test spy if one exists; if logging is hard to spy, skip log assert and rely on snapshot — still **emit** the event).

- [ ] **Step 2: Run to see fail.**
- [ ] **Step 3: Implement.** `previewPlaylist` clones `preview` but calls `probe.probePlaylist`. `submitPlaylistItems`: for each item, if `!force`, existing `jobs.first(where: { $0.request == item.request })` → skip; else `DownloadJob`, set prefetch fields, `playlistGroupID`, `playlistIndex`, `jobs.append`. After the loop: `bump()` once, `emitSnapshot()` once, `logEvent(.playlistEnqueued(…))`, per-item `jobEnqueued`, `evaluateSchedule()` once. Extract a private `makeJob(from: PlaylistSubmitItem) -> DownloadJob?` to stay under body-length 50.
- [ ] **Step 4: Tests pass.** Lint.
- [ ] **Step 5: Hand files to the user.** No git.

---

## Task 10: Probe cancel on job cancel/remove

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (`cancel`, `remove`)
- Modify: `Sources/GrabberKit/Download/DownloadEngine+Mutations.swift` (`recordProbeResult`)
- Test: `Tests/GrabberKitTests/EngineProbeCancelTests.swift`

**Interfaces:**
- Consumes: Task 4 cancel-safe probe; existing `probeTask`.
- Produces: cancel/remove of `.probing` cancels `probeTask` (not only `childTasks[id]`). `recordProbeResult` no-ops on `state != .probing` except clearing `probeInFlight` / `probeTask` and `evaluateSchedule()`.

- [ ] **Step 1: Failing test** — FakeMetadataProbe `perProbeDelay` (TestSupport already has it). Submit a job **without** prefetch so it probes. Wait until snapshot state is `.probing`. `await engine.cancel(id)`. Assert probe `cancelled` / probed task finished and job is `.cancelled`, not later overwritten to `.queued` when the delayed probe completes. Wait the delay after cancel; snapshot stays `.cancelled`.
- [ ] **Step 2: Run to see fail** (today cancel probing does not cancel `probeTask`, so the job may flip back).
- [ ] **Step 3:** `cancel` / `remove`: if `.probing`, `probeTask?.cancel()` (and `cancelChild` if you also store it — probes are **not** in `childTasks`). `recordProbeResult`: `defer { probeInFlight = false; probeTask = nil }`; if job missing or `job.state != .probing` { `evaluateSchedule()`; return }.
- [ ] **Step 4: Tests pass.** Lint.
- [ ] **Step 5: Hand files to the user.** No git.

---

## Task 11: `RequestBuilder` + `PlaylistPickerModel`

**Files:**
- Modify: `Sources/App/Rows/RequestBuilder.swift`
- Create: `Sources/App/Home/PlaylistPickerModel.swift`
- Test: `Tests/AppUnitTests/RequestBuilderTests.swift` (extend)
- Test: `Tests/AppUnitTests/PlaylistPickerModelTests.swift`

**Interfaces:**
- Consumes: `PlaylistDump`, `PlaylistEntry`, `RunwayOverrides`, `Preferences`.
- Produces:

```swift
extension RequestBuilder {
    static func build(
        from entry: PlaylistEntry,
        prefs: Preferences,
        overrides: RunwayOverrides
    ) -> DownloadRequest
}

struct PlaylistPickerModel: Equatable {
    var dump: PlaylistDump
    var checked: Set<Int> // playlistIndex
    var filter: String
    var warnings: [Int: PlaylistRowWarning] // playlistIndex
    var showPlaylistBanner: Bool
}

enum PlaylistRowWarning: Equatable {
    case inQueue
    case alreadySaved
}
```

Footer helpers on the model: `selectedCount`, `overlapCount` (checked ∩ warned), `durationSum`, `filteredEntries`, `selectAllFiltered()`, `selectNoneFiltered()`, `footerLine: String`.

Warning: `watchURL` equals any provided `existing: [(url: String, completed: Bool)]`. Completed → `.alreadySaved`, else `.inQueue`.

Defaults: `checked = all indices minus warned`. `showPlaylistBanner` passed in (AppModel decides live group).

Duration format: `H:MM:SS` if sum ≥ 3600 else `M:SS`. Footer: `M of N selected · K already in queue · ≈ H:MM:SS`; omit ` · K already in queue` when K==0.

- [ ] **Step 1: Failing tests** — RequestBuilder: entry watch URL + overrides kind/language/folder. Picker: all checked except warned; select all on filter `"Tide"` only checks that row; footer omits K when 0; sum skips nil durations.
- [ ] **Step 2: Implement.** `RequestBuilder.build(from:entry:)` same as video builder but `url: entry.watchURL`. Prefetch metadata helper:

```swift
static func prefetch(from entry: PlaylistEntry) -> MediaMetadata {
    MediaMetadata(
        title: entry.title,
        durationSeconds: entry.durationSeconds,
        isPlaylist: false,
        sourceURL: entry.watchURL,
        extractor: entry.extractor
    )
}
```

Put `prefetch` on `RequestBuilder` or `PlaylistEntry` — **`RequestBuilder.prefetch(from:)`**.

- [ ] **Step 3: Tests pass.** Lint. Generate.
- [ ] **Step 4: Hand files to the user.** No git.

---

## Task 12: `AppModel` classify, dump, Add M, registry

**Files:**
- Modify: `Sources/App/AppModel.swift`
- Modify: `Sources/App/AppModelDialogs.swift`
- Modify: `Tests/AppUnitTests/Support/AppModelTestHelpers.swift` if `resolved` type changes
- Test: `Tests/AppUnitTests/AppModelPlaylistTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 8–11, 7 `savePlaylistGroups`.
- Produces:

```swift
enum ResolvedLink: Equatable {
    case video(MediaMetadata)
    case playlist(PlaylistDump)
}
```

Replace `resolved: MediaMetadata?` with `resolved: ResolvedLink?`. Computed `resolvedVideo: MediaMetadata?` for Home catalog seeding if that keeps Home small.

`playlistGroups: [PersistedPlaylistGroup]`
`isPlaylistPickerPresented: Bool`

`resolvePasted`: classify → unsupported copy **This link isn't a video or a playlist.** (no engine) → playlist `previewPlaylist` then present picker → else `preview`.

`grab`: if playlist, `isPlaylistPickerPresented = true`; else today's submit.

`addPlaylistSelection(model:overrides:)`: compute group id (match `sourceURL` on registry **if any current snapshot job still has that id** — AppModel should use `rowStore.rows` / last snapshot URLs). `submitPlaylistItems`. `savePlaylistGroups`. Set `hasGrabbedOnce` the same way single grab does (Home `@AppStorage` — if grab currently sets it via Home, keep that: Home already sets on grab success; playlist Add M must set it too — **HomeView on Add M**). Persist groups after mutate.

Load on init: `loadPlaylistGroups()` after restore. Drop orphan groups (no job in snapshot has that id). Missing title fallback is engine/RowStore **"Playlist"** — registry should still have a title from dump.

- [ ] **Step 1: Failing tests** (FakeEngine):

  - classify unsupported → `probeError` set, `previewedURLs` empty, `previewPlaylist` not called (add `previewPlaylistURLs` on FakeEngine).
  - playlist success → `resolved == .playlist`, `isPlaylistPickerPresented == true`.
  - `addPlaylistSelection` submits items with inherited kind; join: pre-seed registry + fake snapshot jobs with group id + same sourceURL → submitted items reuse that UUID.

- [ ] **Step 2: Implement.** Update every `resolved` reader (`HomeView`, tests). `AppModelDialogs.unsupportedPlaylistLink` message. FakeEngine: `previewPlaylistResult`, `previewPlaylistURLs`, `submittedPlaylistItems`.
- [ ] **Step 3: Tests pass.** Lint.
- [ ] **Step 4: Hand files to the user.** No git.

---

## Task 13: `PlaylistPickerView` + Home sheet

**Files:**
- Create: `Sources/App/Home/PlaylistPickerView.swift`
- Modify: `Sources/App/Home/HomeView.swift`
- Test: `Tests/AppUnitTests/PlaylistPickerModelTests.swift` already covers logic; add a thin `PlaylistPickerView` existence test only if the target already snapshot-tests views — **if not, skip UI snapshot.** Wire Home: `.sheet(isPresented:)` / `.overlay` matching other modals (confirmation is a dialog host — picker is a **sheet/overlay** like design-system modal). Match `ConfirmationDialog` styling tokens (`theme`, `Spacing`).

**Interfaces:**
- Consumes: `PlaylistPickerModel`, `AppModel.addPlaylistSelection`.
- Produces: visible modal: header, optional banner, Select all/none, filter, lazy list, footer, Cancel, Add M.

- [ ] **Step 1:** Thumbnails: `AsyncImage` (or `NSImage` loader) for `thumbnailURL`; placeholder `RoundedRectangle`. LazyVStack. Whole-row tap toggles check. Add M disabled at 0. Grab on playlist calls `appModel.grab` which only presents; **Add M** calls `addPlaylistSelection` then dismisses.
- [ ] **Step 2:** Home `onChange` of `resolved`: seed catalog only for `.video`. Playlist dump: do not rewrite quality rungs from formats (none).
- [ ] **Step 3:** Build the app target (`xcodebuild … build` or full test). Lint. Generate.
- [ ] **Step 4: Hand files to the user.** No git.

---

## Task 14: `RowStore` groups

**Files:**
- Modify: `Sources/App/Rows/RowStore.swift`
- Test: `Tests/AppUnitTests/RowStoreGroupTests.swift` (new; do not explode `RowStoreTests`)

**Interfaces:**
- Consumes: `JobSnapshot.playlistGroupID`, `playlistIndex`; AppModel must pass group registry into the store (**`RowStore.setGroups([PersistedPlaylistGroup])`** or include titles on apply). Pick **`func applyGroups(_ groups: [PersistedPlaylistGroup])`** called from AppModel whenever registry or snapshot changes.
- Produces:

```swift
enum VisibleItem: Equatable, Identifiable {
    case header(PlaylistGroup)
    case child(RowModel)

    var id: String {
        switch self {
        case let .header(group): "g-\(group.id)"
        case let .child(row): "j-\(row.id)"
        }
    }
}
```

Expand `PlaylistGroup` with aggregates from spec §7.1 (speed, eta, size, duration, addedAt min, finishedAt, mixed labels, attempt max). Keep existing count/rollup/collapse fields.

`visibleItems: [VisibleItem]` — table will use this in Task 15. Keep `visibleRows` as **child RowModels only** (filtered jobs, no headers) so existing tests/table still compile until Task 15.

Rules: children by `playlistIndex`; group block key for default addedAt desc = max child `addedAt`; header if any child passes chip+column filters; rollup from **all** group members; collapse hides children in `visibleItems` but header remains; 10% progress buckets.

- [ ] **Step 1: Failing tests** — two jobs same group, indices 2 and 1, addedAt later on index 2; ungrouped job newer than both → order: ungrouped, header, child 1, child 2 (newest-first: ungrouped first if its addedAt is max). Chip `.done` with one completed child: header + that child; rollup totalCount still 2. Progress 0.14 then 0.16: same bucket, `groups` Equatable unchanged if you expose last rollup; 0.24 crosses 0.2→0.2 vs 0.1 — contribution 0.1 vs 0.2. Collapse: `setCollapsed(id:true)` → `visibleItems` is header only.
- [ ] **Step 2: Implement.** Extract `recomputeGroups` / `passesChip` reuse. Last-bucket dictionary `[UUID: Int]` (tenths). `swiftlint` body length — split file `RowStore+Groups.swift` if needed (**allowed**).
- [ ] **Step 3: Tests pass.** Lint. Generate if split.
- [ ] **Step 4: Hand files to the user.** No git.

---

## Task 15: Table header, spine, group actions

**Files:**
- Create: `Sources/App/Table/PlaylistGroupHeader.swift`
- Modify: `Sources/App/Table/DownloadsTable.swift`
- Modify: `Sources/App/Table/DownloadRow.swift`
- Modify: `Sources/App/Table/ColumnsMenu.swift` (empty check → `visibleItems`)
- Modify: `Sources/App/AppModelRowActions.swift`
- Modify: `Sources/App/AppModelDialogs.swift` (cancel all)
- Modify: `Sources/App/Home/HomeView.swift` (`onAction` + group callbacks)
- Test: `Tests/AppUnitTests/RowStoreGroupTests.swift` (actions are AppModel — `Tests/AppUnitTests/AppModelPlaylistGroupActionTests.swift`)

**Interfaces:**
- Consumes: `visibleItems`, spec §6.2 cancel-all copy, `suppressionKey: "playlist-cancel-all"`.
- Produces: header UI (caret, title, `N items · M done`, mini bar, Pause all / Retry failed / Cancel all). Child indent + spine (design-system §4.2.4). Pause all → `pause` each running child; Retry failed → `retry` each `.failed`; Cancel all → `confirm` then `cancel` each cancellable child.

Copy:

```swift
ConfirmationRequest(
    title: "Cancel this playlist?",
    message: "Videos still waiting or downloading will stop. Files already saved stay.",
    confirmTitle: "Cancel All",
    cancelTitle: "Keep",
    isDestructive: true,
    suppressionKey: "playlist-cancel-all"
)
```

Disable Pause all when no running child; Retry failed when no `.failed`; Cancel all when none cancellable. Caret toggles `RowStore` collapse and AppModel registry `isCollapsed` + `savePlaylistGroups`. Last `remove` of a member drops registry row (AppModel).

- [ ] **Step 1:** Switch `ForEach(store.visibleItems)`. Header spans full width (`PlaylistGroupHeader`). DownloadRow: if `playlistGroupID != nil`, extra leading padding + spine lines (color `theme.palette.stroke`).
- [ ] **Step 2: AppModel tests** — FakeEngine `cancelledIDs` after cancel all confirm (FakeConfirmer if tests already have one; else `AppModel.confirm` with suppression already true). Pause all records pause on running ids — **FakeEngine must record `pause` calls** (add `pausedIDs` if missing).
- [ ] **Step 3: Tests pass.** Full `AppUnitTests`. Lint.
- [ ] **Step 4: Hand files to the user.** No git.

---

## Task 16: Mockup + spec close verify

**Files:**
- Modify: `apps/media-grabber/docs/mockups/screens.html` §5.1 and §5.2
- Verify (no rewrite unless drift): parent playlist paragraphs, `apps/media-grabber/docs/design-system.md` §4.3, `apps/media-grabber/ticket-backlog.md` Phase 8
- Modify: `docs/superpowers/specs/2026-09-08-media-grabber-phase-8.md` status if needed (plan path already set)

**Do:**

- Drop `(depiction is refined when this screen's phase is detailed)`.
- **5.1:** paste + five-slot runway (`Link · Type · Format · Language · Save to`, skinned), table under, picker overlay. Runway primary is **Grab**, not Add 12. Status `✓ "Focus — deep work" · 24 items`. Footer `12 of 24 selected · 2 already in queue · ≈ 1:12:45` (or similar). Banner + one **Already saved** unchecked row. Hero/kicker: this screen has existing rows — **no first-run hero** (match 1.2: paste + runway + table).
- **5.2:** group header + spine + group actions; a single row above or below by recency; columns match Home (Title, Status, Progress, …) not a fake Format column.
- Health chips: `bot-check shield · on` as Phase 7.

- [ ] **Step 1: Edit HTML/CSS** as needed (warned row class, banner in `.modal`).
- [ ] **Step 2: Open the file in a browser (or Playwright) and check 5.1 / 5.2.**
- [ ] **Step 3: Full suite** `MediaGrabber-Workspace` test + lint.
- [ ] **Step 4: Hand files to the user.** No git.

---

## Spec coverage (self-review)

| Spec | Task |
|---|---|
| §2 Classify | 1, 12 |
| §3 Dump | 2, 4 |
| §4 Picker UI | 11, 13 |
| §5 Add M / join / force | 9, 11, 12 |
| §6 Token bucket | 0, 3, 4 |
| §6 Probe cancel | 4, 10, 15 |
| §7 Table / chips / aggregates | 14, 15 |
| §8 Persistence | 5, 7, 12 |
| §9 AppModel | 12 |
| §10 Copy | 12, 15 |
| §11 Tests / smoke | each task + 16 |
| §12 Docs | 16 |
| §13 Out of scope | no tasks |

No `--playlist-items`. No `DownloadRequest.playlist`. Non-YouTube never `--flat-playlist`.
