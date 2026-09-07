# MediaGrabber Phase 7 — YouTube Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make paste and Grab share one YouTube identity (bot-check shield + `player_client`), restrict the runway to this probe's formats and languages, and emit the YouTube failure / chrome cases.

**Architecture:** The engine owns `PotProviderProcess` and builds an `ExtractorContext` at spawn. `engine.preview` replaces AppModel's second `MetadataProbe`. Probe JSON fills `MediaMetadata` format/language fields; the runway seeds from those plus Preferences. `potProviderDown` is banner + chip only — not a queue halt.

**Tech Stack:** Swift 6, Tuist, XCTest. Targets: `GrabberKit`, `MediaGrabber`, `TestSupport`, `GrabberKitTests`, `AppUnitTests`.

**Spec:** `docs/superpowers/specs/2026-09-07-media-grabber-phase-7.md` — read it alongside this plan. Every task's "why" is there; this plan is the "how".

## Global Constraints

- **No git.** This plan contains no `git` commands. Each task ends by running lint + tests and handing the changed files to the user. Do not create branches, do not commit, do not stage.
- **No phase / ticket / epic numbers anywhere in source or UI copy.** Not in comments, not in log strings, not in SwiftUI `Text`. The spec and this plan are the only places "Phase 7" appears.
- **Comments: single-line only, only the *why*, only when names don't carry it.** No `///`. No stacked `//` blocks. Default to zero comments. `// MARK:` is fine.
- **UI copy:** "bot-check shield", "couldn't verify you". Never "POT", "yt-dlp", or `player_client` in a user-visible string.
- **Swift 6 concurrency:** `NSLock` banned in async. `LockedBox` is TestSupport-only. Actors reentrant across `await`. `XCTestCase` is not `Sendable`.
- **`@Observable` classes using `URL` / `Foundation` types need `import Foundation`.**
- **Lint after every task:** `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict` from `apps/media-grabber/`. Recurring traps: `function_body_length` 50, `type_body_length` 250, `cyclomatic_complexity` 10, `opening_brace` vs swiftformat — extract helpers, do not inline multi-line `if`.
- **Build after adding/removing files:** `mise exec -- tuist generate --no-open` from `apps/media-grabber/`.
- **Test command:** from `apps/media-grabber/`: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`. Single suite: `-only-testing:GrabberKitTests/<SuiteName>` or `-only-testing:AppUnitTests/<SuiteName>`. Do NOT use `tuist test` while developing.
- **Engine tests are not `@MainActor`.** Read state via `await engine.currentSnapshot()` or `EventCollector`.
- **Test names carry no phase number.**
- **The real test harness:**
  - `EventCollector(engine.events)` — positional.
  - `FakeMetadataProbe.success(title:)` — after Task 5 this still compiles (new `MediaMetadata` init params are defaulted).
  - `EngineFixture.engine(runner:probe:…)` — Task 2's `potProvider` default means this call site does not change until a test needs a fake shield.
  - `runner.script` / `runner.scripts([...], forPathEndingIn:)` — path-keyed.
  - Prefer `engine.currentSnapshot()` over the collector when racing.
- **Do not use `XCTAssertTrue(await …)`** — bind to a `let`, then assert.
- All source paths below are relative to `apps/media-grabber/` unless they start with `docs/`.
- **`ErrorClass.botCheck` / `.sabrGated` / `.formatsMissing` / `.potProviderDown` already exist.** This phase fills signatures, presentation, auto-retry, and emit — do not redeclare the enum cases.
- **`JobSnapshot.playerClientUsed` and `ChipInteraction.refresh` already exist.** Populate / split; do not add a second field or a second enum case.
- **`EngineFixture.engine(...)`** lives in `Tests/GrabberKitTests/DownloadEngineTestHelpers.swift`. Task 11 adds `potProvider:` (default `nil` → deps default `MissingPotProvider`). Until then, existing call sites stay as-is.

## Lint traps (apply the fix pre-emptively)

- `swiftlint cyclomatic_complexity` (limit 10) — a `switch` mixing `case let` with comma-grouped patterns trips it. Fix: split into per-arm helper funcs.
- `swiftlint function_body_length` (limit 50) — fix: hoist sub-expression builds into helpers.
- `swiftformat` collapses a `switch` arm returning a value into an implicit-return ternary, then `swiftlint void_function_in_ternary` rejects it. Fix: give that arm its own `guard`-based helper.
- `swiftlint large_tuple` (limit 2) — a test helper returning a 3+ tuple fails. Fix: a private `struct`.
- `swiftlint type_body_length` (limit 250, strict) — adding ~3 tests to a large XCTestCase trips it. Fix: split into a sibling `<Name>MoreTests.swift`.
- `swiftformat` reformats `for … where <pred> {` onto its own `{` line → `swiftlint opening_brace` rejects. Use `table.first { entry in … }?.field`. Same for a multi-line `if cond, let x`.
- `swiftformat` and `swiftlint` disagree on the `{` placement for a wrapped multi-line `if` condition. Fix: extract the condition into a named predicate function; do not inline a multi-line `||` / `,` condition.

## File Structure

**New — `GrabberKit/PotProvider/`:**

| File | Responsibility |
|---|---|
| `ShieldStatus.swift` | `enum ShieldStatus` (`running(port:)` / `down` / `missing`). |
| `PotProviding.swift` | `protocol PotProviding` + `MissingPotProvider`. |
| `PotPluginInstaller.swift` | Resolve plugin dir + server launch (`ProcessLaunch?`). Filesystem injected. |
| `PotProviderProcess.swift` | Live supervisor: bind 127.0.0.1, ping `/ping`, restart, stop. |

**New — `GrabberKit/Download/`:**

| File | Responsibility |
|---|---|
| `ExtractorContext.swift` | Shared argv context. |
| `PlayerClientRotation.swift` | Config constant + `client(forAttempt:)`. |
| `AudioLanguage.swift` | `AudioLanguage`, `AudioLanguagePolicy`, `LastAudioLanguage`. |
| `FormatCatalog.swift` | `FormatAvailability`, `AudioTrack`, `VideoQualityOptions`, `AudioLanguageSeed`. |

**New — `GrabberKit/Network/`:**

| File | Responsibility |
|---|---|
| `VPNDetecting.swift` | `protocol VPNDetecting` + `InterfaceVPNDetector` + `FakeVPNDetector` (TestSupport). |

**Modified — `GrabberKit`:**

| File | Change |
|---|---|
| `Model/EngineTuning.swift` | Two defaulted fields + `resolved()` env keys. |
| `Download/DownloadEngineProtocol.swift` | `potProvider` on deps (default `MissingPotProvider`); protocol gains `preview` / `ensureShield` / `restartShield`; `.live` constructs `PotProviderProcess`. |
| `Download/YtDlpArguments.swift` | `context: ExtractorContext = .none`; language spliced into `-f`. |
| `Download/DownloadRequest.swift` | `audioLanguage`; Codable default `.unspecified`. |
| `Download/MetadataProbe.swift` | `MediaMetadata` new `let`s; decode formats; `probe(_:context:)`; `MetadataError.hostBlocked`; bot-check via `ErrorSignatures`. |
| `Download/ErrorSignatures.swift` | YouTube groups **after** `ageRestricted`. |
| `Download/FailurePresentation.swift` | Four sentences; `noRetryKeys` / `cookieRetryKeys` deltas. |
| `Download/ErrorClass+Presentation.swift` | `isAutoRetryable` gains `botCheck`, `formatsMissing`. |
| `Download/DownloadEngine+Helpers.swift` | `errorClass(for:)` `.hostBlocked` → `.rateLimited()`. |
| `Download/DownloadEngine+Mutations.swift` | `classifyExit` kind-aware `formatsMissing`; spawn sets `playerClientUsed`. |
| `Download/DownloadEngine.swift` | `preview`, `ensureShield`, `restartShield`; `shutdown` stops shield; `launchProbe` / `downloadArguments` take context. |
| `Download/DownloadEngine+State.swift` | `buildSnapshot` passes `shieldStatus`. |
| `Download/QueueEvent.swift` | `QueueSnapshot.shieldStatus` defaulted on init. |
| `Download/JobLog.swift` | `player_client:` header line. |
| `Logging/LogEvent.swift` | Four shield cases; exhaustive `key` / `category` / `fields`. |
| `Model/Preferences.swift` | Policy + last language keys. |

**Modified — App:**

| File | Change |
|---|---|
| `MediaGrabberApp.swift` | Stop constructing `MetadataProbe`. |
| `AppModel.swift` | Drop `probe:`; `resolvePasted` → `engine.preview`; `ensureShield` on appear / onboarding; `grab` writes `lastAudioLanguage`. |
| `AppModelDialogs.swift` | `.hostBlocked` + VPN `.botCheck` copy. |
| `Chrome/AppModel+Banner.swift` | Union `shieldStatus != .running`. |
| `Chrome/BannerResolver.swift` | `.potProviderDown`. |
| `Chrome/HealthController.swift` | Prepend shield chip. |
| `Chrome/HealthStrip.swift` | `.refresh` is a `↻` button; `onRefresh`. |
| `MainWindow.swift` | Pass `onRefresh`. |
| `Home/RunwayView.swift` | Language slot. |
| `Home/HomeView.swift` | Re-seed quality + language on preview; `RunwayOverrides.audioLanguage`. |
| `Home/RunwaySeed.swift` | Unchanged for type/folder; quality/language seed is Home-side from catalog helpers. |
| `Rows/RequestBuilder.swift` | `audioLanguage`. |
| `Rows/RowStatusText.swift` | VPN variant for `botCheck`. |
| `Preferences/Panes/DownloadsPane.swift` | Audio language row. |

**Modified tests:** both `FakeEngine`s; `FakeMetadataProbe.probe` signature if protocol grows `context:`; `AppModelTestHelpers` drops `probe:`; `FailurePresentationTests`; `YtDlpArgumentsTests`; `MetadataProbeTests`; `HealthControllerTests`; `BannerResolverTests`; `PreferencesTests`; `RunwaySeedTests`; `JobLogTests`; `DownloadRequestTests`; `EngineFixture` unchanged until a test injects `potProvider:`.

**Docs (Task 17):** verify parent + design-system + backlog; fill `docs/mockups/screens.html`.

---

## Task 0: `EngineTuning` shield timeouts

**Files:**
- Modify: `Sources/GrabberKit/Model/EngineTuning.swift`
- Test: `Tests/GrabberKitTests/EngineTuningTests.swift` (extend; split sibling if `type_body_length`)

**Interfaces:**
- Consumes: existing `EngineTuning.init` (later fields already defaulted).
- Produces: `potHealthTimeoutSeconds: Int` (default 2), `potRestartBackoffSeconds: Int` (default 2); `resolved()` reads `MG_POT_HEALTH_TIMEOUT`, `MG_POT_RESTART_BACKOFF`.

- [x] **Step 1: Write the failing test**

```swift
func testPotTuningDefaults() {
    XCTAssertEqual(EngineTuning.default.potHealthTimeoutSeconds, 2)
    XCTAssertEqual(EngineTuning.default.potRestartBackoffSeconds, 2)
}

func testPotTuningReadsEnv() {
    let tun = EngineTuning.resolved(environment: [
        "MG_POT_HEALTH_TIMEOUT": "5",
        "MG_POT_RESTART_BACKOFF": "7"
    ])
    XCTAssertEqual(tun.potHealthTimeoutSeconds, 5)
    XCTAssertEqual(tun.potRestartBackoffSeconds, 7)
}
```

- [x] **Step 2: Run to see fail** — `xcodebuild … -only-testing:GrabberKitTests/EngineTuningTests`
- [x] **Step 3: Add the two stored properties as defaulted `init` params (end of the existing defaulted list) so `EngineTuning(ytDlp:backoffLadder:backoffCap:)` in `BackoffTests` still compiles. Set them on `.default`. Parse in `resolved()` via the existing `intValue` helper (or extend `RateLimitTuningValues` — prefer a tiny extra `intValue` at the `return EngineTuning(` site so you do not widen `RateLimitTuningValues` cyclomatic).
- [x] **Step 4: Tests pass.** Lint.
- [x] **Step 5: Hand files to the user.** No git.

---

## Task 1: `ShieldStatus`, `PlayerClientRotation`, `ExtractorContext`

**Files:**
- Create: `Sources/GrabberKit/Download/ShieldStatus.swift` (or `PotProvider/ShieldStatus.swift` — pick **`PotProvider/ShieldStatus.swift`**)
- Create: `Sources/GrabberKit/Download/PlayerClientRotation.swift`
- Create: `Sources/GrabberKit/Download/ExtractorContext.swift`
- Test: `Tests/GrabberKitTests/PlayerClientRotationTests.swift` (new)
- Test: `Tests/GrabberKitTests/ExtractorContextTests.swift` (new — Equatable / `.none`)

**Interfaces:**
- Produces:

```swift
public enum ShieldStatus: Sendable, Equatable {
    case running(port: Int)
    case down
    case missing
}

public enum PlayerClientRotation {
    public static let `default` = ["tv", "ios", "tv_embedded", "mweb", "web_safari"]
    public static func client(forAttempt attempt: Int) -> String
}

public struct ExtractorContext: Sendable, Equatable {
    public var pluginDirs: [URL]
    public var potBaseURL: URL?
    public var playerClient: String?
    public var cookieArgument: String?
    public static let none: ExtractorContext
}
```

`client(forAttempt:)`: `list[min(max(attempt, 0), list.count - 1)]`.

- [ ] **Step 1: Failing tests**

```swift
func testAttemptZeroIsTv() {
    XCTAssertEqual(PlayerClientRotation.client(forAttempt: 0), "tv")
}
func testAttemptFourIsWebSafari() {
    XCTAssertEqual(PlayerClientRotation.client(forAttempt: 4), "web_safari")
}
func testAttemptPastEndSticks() {
    XCTAssertEqual(PlayerClientRotation.client(forAttempt: 99), "web_safari")
}
func testSkipsWebAndAndroid() {
    XCTAssertFalse(PlayerClientRotation.default.contains("web"))
    XCTAssertFalse(PlayerClientRotation.default.contains("android"))
}
func testNoneHasNilFlags() {
    XCTAssertEqual(ExtractorContext.none.pluginDirs, [])
    XCTAssertNil(ExtractorContext.none.potBaseURL)
    XCTAssertNil(ExtractorContext.none.playerClient)
    XCTAssertNil(ExtractorContext.none.cookieArgument)
}
```

- [ ] **Step 2: Run — fail (types missing).**
- [ ] **Step 3: Implement the three files. `ExtractorContext.none` = empty dirs + nils. No comments.**
- [ ] **Step 4: Pass + lint.** `tuist generate --no-open` after adding files.
- [ ] **Step 5: Hand files to the user.**

---

## Task 2: `PotProviding` + `MissingPotProvider` + `EngineDependencies.potProvider`

**Files:**
- Create: `Sources/GrabberKit/PotProvider/PotProviding.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` (`EngineDependencies`)
- Test: `Tests/GrabberKitTests/MissingPotProviderTests.swift` (new)

**Interfaces:**
- Consumes: `ShieldStatus` (Task 1).
- Produces:

```swift
public protocol PotProviding: Sendable {
    var status: ShieldStatus { get async }
    func ensure() async
    func restart() async
    func stop() async
    var baseURL: URL? { get async }
    var pluginDirs: [URL] { get async }
}

public struct MissingPotProvider: PotProviding {
    public init()
    // status = .missing; ensure/restart/stop no-op; baseURL nil; pluginDirs []
}
```

`EngineDependencies` gains `public var potProvider: any PotProviding`.
`init` gains `potProvider: any PotProviding = MissingPotProvider()`.
`.live` still does **not** construct a real process this task — keep the default stub so Task 10 can swap `.live` to `PotProviderProcess` in one place. (If you construct live now, unit tests that accidentally call `.live` would bind a port. Do not.)

- [ ] **Step 1: Failing test** — `await MissingPotProvider().status == .missing`.
- [ ] **Step 2: Run — fail.**
- [ ] **Step 3: Add protocol + stub + deps property with default. Existing `EngineDependencies(` in `EngineFixture` / engine tests compile unchanged.**
- [ ] **Step 4: `GrabberKitTests` that construct `EngineDependencies` still pass. Lint.**
- [ ] **Step 5: Hand files to the user.**

---

## Task 3: `YtDlpArguments` extractor context (not language yet)

**Files:**
- Modify: `Sources/GrabberKit/Download/YtDlpArguments.swift`
- Modify: `Tests/GrabberKitTests/YtDlpArgumentsTests.swift`

**Interfaces:**
- Consumes: `ExtractorContext` (Task 1).
- Produces: `build(…, context: ExtractorContext = .none, concurrentFragments:)` and matching `redacted`. Put `context` **before** `concurrentFragments` with a default so existing `concurrentFragments:` labeled calls still compile.

Extract a package-internal helper used by both `build`/`redacted` **and** Task 5's probe argv so they cannot drift:

```swift
static func extractorFlags(context: ExtractorContext) -> [String] {
    var flags: [String] = []
    if !context.pluginDirs.isEmpty {
        flags += ["--plugin-dirs", context.pluginDirs.map(\.path).joined(separator: ":")]
    }
    if let pot = context.potBaseURL {
        flags += ["--extractor-args", "youtubepot-bgutilhttp:base_url=\(pot.absoluteString)"]
    }
    if let client = context.playerClient {
        flags += ["--extractor-args", "youtube:player_client=\(client)"]
    }
    return flags
}
```

Two `--extractor-args` flags, never a merged string. Insert `extractorFlags` **after** cookie flags, **before** the URL (same region as cookies). `cookieArgument` on `build` stays the existing param; `context.cookieArgument` is unused here — the engine already passes cookies via `cookieArgument:`. Do not emit cookies twice.

YouTube-only is **the caller's job** (engine omits `playerClient` / `potBaseURL` for non-YouTube). This task still emits whatever is in the context.

Redaction: cookies masked; `base_url` and `player_client` verbatim. `redacted` must take `context:` too. Add `test_redactedEqualsBuild` with a non-`.none` context.

- [ ] **Step 1: Failing tests**

```swift
func testContextEmitsPluginDirsPotAndClient() {
    let ctx = ExtractorContext(
        pluginDirs: [URL(fileURLWithPath: "/tmp/plug")],
        potBaseURL: URL(string: "http://127.0.0.1:4416")!,
        playerClient: "tv",
        cookieArgument: nil
    )
    let argv = YtDlpArguments.build(
        for: request(kind: .video(maxHeight: 1080)),
        context: ctx,
        concurrentFragments: 4
    )
    XCTAssertTrue(argv.contains("--plugin-dirs"))
    XCTAssertTrue(argv.contains("/tmp/plug"))
    XCTAssertTrue(argv.contains("youtubepot-bgutilhttp:base_url=http://127.0.0.1:4416"))
    XCTAssertTrue(argv.contains("youtube:player_client=tv"))
}

func testNoneContextDoesNotEmitExtractorArgs() {
    let argv = YtDlpArguments.build(
        for: request(kind: .video(maxHeight: 1080)),
        concurrentFragments: 4
    )
    XCTAssertFalse(argv.contains("--plugin-dirs"))
    XCTAssertFalse(argv.contains(where: { $0.contains("player_client") }))
}

func testRedactedKeepsPotAndClient() {
    let ctx = ExtractorContext(
        pluginDirs: [],
        potBaseURL: URL(string: "http://127.0.0.1:4416")!,
        playerClient: "ios",
        cookieArgument: "safari"
    )
    let red = YtDlpArguments.redacted(
        for: request(kind: .video(maxHeight: 720)),
        context: ctx,
        cookieArgument: "safari",
        concurrentFragments: 4
    )
    XCTAssertTrue(red.contains("<redacted>"))
    XCTAssertTrue(red.contains("youtube:player_client=ios"))
    XCTAssertTrue(red.contains("youtubepot-bgutilhttp:base_url=http://127.0.0.1:4416"))
}
```

Reuse the existing `request(kind:)` helper in `YtDlpArgumentsTests`.

- [ ] **Step 2: Run — fail.**
- [ ] **Step 3: Implement. Keep `test_video1080_mp4` exact-array assertion passing (context `.none` adds nothing).**
- [ ] **Step 4: Pass + lint.**
- [ ] **Step 5: Hand files to the user.**

---

## Task 4: `AudioLanguage` on `DownloadRequest` + format selector

**Files:**
- Create: `Sources/GrabberKit/Download/AudioLanguage.swift`
- Modify: `Sources/GrabberKit/Download/DownloadRequest.swift`
- Modify: `Sources/GrabberKit/Download/YtDlpArguments.swift` (`formatSelector`)
- Modify: `Tests/GrabberKitTests/DownloadRequestTests.swift`
- Modify: `Tests/GrabberKitTests/YtDlpArgumentsTests.swift`

**Interfaces:**
- Produces:

```swift
public enum AudioLanguage: Sendable, Equatable, Codable {
    case unspecified
    case original
    case code(String)
}

public enum AudioLanguagePolicy: String, Codable, Sendable, CaseIterable {
    case youtubeDefault
    case original
}

public enum LastAudioLanguage: Codable, Sendable, Equatable {
    case original
    case code(String)
}
```

`DownloadRequest` gains `public var audioLanguage: AudioLanguage = .unspecified` on the memberwise init **and** `init(from:)` via `decodeIfPresent` defaulting to `.unspecified`. Existing `DownloadRequest(` call sites keep compiling.

Format selector (video), `ba` tokens only:

- `.unspecified` — today's string unchanged.
- `.code("ja")` — `bv*[height<=H][ext=mp4]+ba[language=ja][ext=m4a]/bv*[height<=H]+ba[language=ja]/bv*[height<=H][ext=mp4]+ba[ext=m4a]/bv*[height<=H]+ba/b[height<=H]`
- `.original` — same shape with `ba[format_note*=original]` instead of `ba[language=ja]`, then unfiltered `ba` fallbacks. Selector cannot express `original_language`; that is probe-only.

Audio-only: prepend `-f` `ba[language=ja]/ba` (or original filter) before `-x --audio-format`.

- [ ] **Step 1: Failing tests** — decode JSON without `audioLanguage` → `.unspecified`; video `.code("ja")` argv contains `ba[language=ja]`; unspecified still matches today's `-f` string exactly; original contains `format_note*=original`.
- [ ] **Step 2: Run — fail.**
- [ ] **Step 3: Implement. Watch `function_body_length` — hoist format-string building into a private helper `baSelector(language:height:)`.**
- [ ] **Step 4: Pass + lint.**
- [ ] **Step 5: Hand files to the user.**

---

## Task 5: `MediaMetadata` catalog + probe decode + probe argv context

**Files:**
- Create: `Sources/GrabberKit/Download/FormatCatalog.swift` (`FormatAvailability`, `AudioTrack`; seed helpers can wait for Task 14)
- Modify: `Sources/GrabberKit/Download/MetadataProbe.swift` (`MediaMetadata`, `MetadataProbing`, decode, argv)
- Modify: `Tests/TestSupport/FakeMetadataProbe.swift` (and App's duplicate `FakeMetadataProbe` in `AppFakes.swift` if it still has its own `probe`)
- Modify: `Tests/GrabberKitTests/MetadataProbeTests.swift`
- Create fixtures under `Tests/GrabberKitTests/Fixtures/`:
  - `ytdlp-J-youtube-formats.json`
  - `ytdlp-J-audio-only.json`
  - `ytdlp-J-no-languages.json`
  - `ytdlp-J-no-formats.json`

**Interfaces:**
- Consumes: `ExtractorContext` (Task 1).
- Produces:

```swift
public enum FormatAvailability: Sendable, Equatable { case unknown, listed }

public struct AudioTrack: Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let languageCode: String?
    public let label: String
    public let isOriginal: Bool
    public let isDefault: Bool
}

// id formula:
//   synthetic Default: "default"
//   else: "\(languageCode ?? "und")|\(isOriginal ? "orig" : "dub")"
```

`MediaMetadata` stays all `let`. Append to the existing init **after `extractor`**:

```swift
formatAvailability: FormatAvailability = .unknown,
videoHeights: [Int] = [],
audioTracks: [AudioTrack] = []
```

Protocol:

```swift
func probe(_ url: String, context: ExtractorContext) async -> Result<MediaMetadata, MetadataError>
```

Extension default:

```swift
extension MetadataProbing {
    public func probe(_ url: String) async -> Result<MediaMetadata, MetadataError> {
        await probe(url, context: .none)
    }
}
```

`FakeMetadataProbe.probe(_:context:)` ignores context (same as today). Existing `probe.result(...)` tests keep working.

Decode (hoist into `FormatCatalog.parse` to keep `MetadataProbe` under 50 lines per function). Return a named struct — `swiftlint large_tuple` is 2:

```swift
struct ParsedFormats {
    var availability: FormatAvailability
    var videoHeights: [Int]
    var audioTracks: [AudioTrack]
}

static func parse(formats: [[String: Any]]?, originalLanguage: String?) -> ParsedFormats {
    guard let formats else {
        return ParsedFormats(availability: .unknown, videoHeights: [], audioTracks: [])
    }
    let heights = Set(formats.compactMap(videoHeight)).sorted(by: >)
    var tracksByID: [String: AudioTrack] = [:]
    var order: [String] = []
    for row in formats {
        guard let track = audioTrack(from: row, originalLanguage: originalLanguage) else { continue }
        if tracksByID[track.id] == nil {
            order.append(track.id)
        }
        tracksByID[track.id] = track
    }
    var tracks = order.compactMap { tracksByID[$0] }
    if tracks.isEmpty || tracks.allSatisfy({ $0.languageCode == nil && !$0.isOriginal }) {
        tracks = [AudioTrack(
            id: "default", languageCode: nil, label: "Default",
            isOriginal: false, isDefault: true
        )]
    } else {
        tracks = electDefault(tracks)
    }
    return ParsedFormats(availability: .listed, videoHeights: heights, audioTracks: tracks)
}
```

- Video height: `height` is a number, `vcodec` present and ≠ `"none"`.
- Audio row: `acodec` present and ≠ `"none"`.
- `isOriginal`: `format_note` contains `"original"` (case-insensitive) OR `language == originalLanguage`.
- `isDefault`: highest `language_preference` among audio rows; ties → first listed. Then copy that flag onto the matching `AudioTrack`.
- `label`: `audio_track.display_name` if present, else a readable `format_note` (not a technical tag like `Default, high`), else the language code, else `"Default"`. Append `" (original)"` when `isOriginal` and the label does not already contain `"original"`.

Missing / unparseable `formats` key → `.unknown`, empty heights/tracks (not the synthetic Default — runway Task 14 treats unknown as Default).

Probe argv: `["-J", "--no-warnings", "--no-playlist", "--no-update"] + YtDlpArguments.extractorFlags(context: context) + [url]`.

`MetadataError` gains `.hostBlocked` this task (engine wires it in Task 11). Add the case now so the enum is complete; probe `classify` never returns it. `AppModelDialogs.probeErrorMessage` will not compile until Task 7 adds the arm — **add a temporary `.hostBlocked` arm in `probeErrorMessage` this task** with the cooling-down sentence so the app target still builds (Task 7 rewrites `.botCheck` only).

- [ ] **Step 1: Fixtures + failing decode tests** via `MetadataProbe.decodeForTest`. YouTube fixture: 1080 + 720 video, original `ja` + dubbed `en`, `isDefault` on the YouTube default. Audio-only: `.listed`, `videoHeights` empty. No languages: synthetic Default. No formats key: `.unknown`.
- [ ] **Step 2: Failing argv test** — `probe` with a context containing `playerClient: "tv"` records a launch whose arguments contain `youtube:player_client=tv`.
- [ ] **Step 3: Implement decode + protocol + fake updates.** `tuist generate` after new files.
- [ ] **Step 4: Full `MetadataProbeTests` + `FakeMetadataProbe.success` still compiles in engine tests. Lint.**
- [ ] **Step 5: Hand files to the user.**

---

## Task 6: YouTube `ErrorClass` emit + presentation + `hostBlocked` mapping

**Files:**
- Modify: `Sources/GrabberKit/Download/ErrorSignatures.swift`
- Modify: `Sources/GrabberKit/Download/MetadataProbe.swift` (delete `botCheckSignatures`; bridge `firstMatch`)
- Modify: `Sources/GrabberKit/Download/FailurePresentation.swift`
- Modify: `Sources/GrabberKit/Download/ErrorClass+Presentation.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine+Helpers.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine+Mutations.swift` (`classifyExit` kind-aware extra)
- Modify: `Tests/GrabberKitTests/ErrorSignaturesTests.swift`
- Modify: `Tests/GrabberKitTests/FailurePresentationTests.swift`
- Modify: `Tests/GrabberKitTests/MetadataProbeTests.swift` (`test_botCheck_mapsToBotCheck` still passes via the table)
- Create: `Tests/GrabberKitTests/Fixtures/ytdlp-stderr-sabr.txt`, `ytdlp-stderr-formats-missing.txt`

**Ordering (required):** append YouTube groups **after** `.ageRestricted` so `"Sign in to confirm your age"` still matches age, not bot-check. Do **not** add the bare substring `"Sign in to confirm"` from the probe list — that would steal age-restricted. Use `"Sign in to confirm you're not a bot"` plus the other probe strings (`"confirm you're not a bot"`, `"page needs to be reloaded"`, `"unable to extract uploader id"`, `"HTTP Error 403"`, `"This content isn't available, try again later"`).

`ErrorClass` cases **already exist** — do not add them. This task fills `ErrorSignatures.table`, `FailurePresentation`, `isAutoRetryable`, `errorClass(for:)`, and `classifyExit`.

Then:

```swift
(.sabrGated, ["only images are available", "sabr"]),
(.formatsMissing, ["requested format is not available"]),
(.botCheck, [ /* strings above */ ]),
```

`sabrGated` before `formatsMissing` before `botCheck` so "only images" wins over a generic miss.

**Probe bridge:** in `classify`, after URL/unsupported/unavailable, `if let matched = ErrorSignatures.firstMatch(in: stderr), case .botCheck = matched { return .botCheck }`. Do **not** widen `sharedUnavailableSignatures` (it already filters `.unavailable/.private/.geoBlocked`).

**Presentation:**

| key | `fixedSentences` | `noRetryKeys` | `cookieRetryKeys` |
|---|---|---|---|
| `bot_check` | Couldn't verify you. Try again, or add browser cookies in Preferences. | no | add |
| `sabr_gated` | YouTube isn't offering a downloadable video for this link. | add | no |
| `formats_missing` | The quality you picked isn't available for this video. | no | add |
| `pot_provider_down` | Bot-check protection is offline. | no | no |

`isAutoRetryable`: add `.botCheck`, `.formatsMissing`. Leave `.sabrGated` / `.potProviderDown` on `default: false`.

`errorClass(for:)`: `.hostBlocked` → `.rateLimited()`.

`classifyExit`: if `lastError == nil` or last is generic, and job `kind` is `.video`, and stderr/lastError path saw `"audio only"` as the no-video reason, return `.formatsMissing`. Keep this in a helper to stay under complexity 10. If `lastError` is already `.sabrGated`, do not override.

- [ ] **Step 1: Failing tests** — `classify("ERROR: Sign in to confirm you're not a bot") == .botCheck`; age line still `.ageRestricted`; sabr fixture → `.sabrGated`; requested-format line → `.formatsMissing`; presentation sentences/actions; `isAutoRetryable`; `errorClass(for: .hostBlocked) == .rateLimited()`.
- [ ] **Step 2: Run — fail.**
- [ ] **Step 3: Implement. `FailurePresentationTests.cases` array adds the four YouTube cases plus keep `unknown`.**
- [ ] **Step 4: Pass + lint.**
- [ ] **Step 5: Hand files to the user.**

---

## Task 7: VPN detector + bot-check copy variant

**Files:**
- Create: `Sources/GrabberKit/Network/VPNDetecting.swift`
- Create: `Tests/TestSupport/FakeVPNDetector.swift`
- Modify: `Sources/App/Rows/RowStatusText.swift`
- Modify: `Sources/App/AppModelDialogs.swift`
- Test: `Tests/GrabberKitTests/VPNDetectingTests.swift` (new — fake detector only, no `getifaddrs` in CI)
- Test: `Tests/AppUnitTests/RowStatusTextTests.swift` (extend if it exists; otherwise put copy tests in `AppModelDialogsTests` / a new `BotCheckCopyTests.swift`)

**Interfaces:**

```swift
public protocol VPNDetecting: Sendable {
    var isVPNActive: Bool { get }
}

public struct FakeVPNDetector: VPNDetecting {
    public var isVPNActive: Bool
    public init(isVPNActive: Bool = false)
}

public struct InterfaceVPNDetector: VPNDetecting {
    public init()
    public var isVPNActive: Bool { /* getifaddrs; prefixes utun, ipsec, ppp, wg */ }
}
```

`FakeVPNDetector` lives in TestSupport (or GrabberKit if that is simpler — prefer TestSupport so production does not ship a mutable stub). `InterfaceVPNDetector` is the live type.

Display-only. `FailurePresentation.for(.botCheck)` stays the no-VPN sentence.

```swift
enum BotCheckCopy {
    static func sentence(vpnActive: Bool) -> String {
        vpnActive
            ? "Couldn't verify you. Turn off your VPN, or add browser cookies in Preferences."
            : "Couldn't verify you. Try again, or add browser cookies in Preferences."
    }
}
```

`RowStatusText` for `.failed(.botCheck)`: `BotCheckCopy.sentence(vpnActive:)`. Add `vpnActive: Bool = false` so existing call sites compile.

`AppModelDialogs.probeErrorMessage`: exhaustive switch — add `.hostBlocked` → `"This site is cooling down. Try again in a moment."`; `.botCheck` → `BotCheckCopy.sentence(vpnActive: vpnActive)` with a new `vpnActive: Bool = false` param (or have `resolvePasted` bypass the dialog helper and set `probeError` from `BotCheckCopy` directly). **Drop** the current brew-upgrade line.

`AppModel` stores `let vpnDetector: any VPNDetecting` with default `InterfaceVPNDetector()` on the live init only. Tests pass `FakeVPNDetector()`. Adding the param with a default keeps `AppModelTestHelpers` compiling until they opt in.

- [ ] **Step 1: Failing tests** for `BotCheckCopy` and `probeErrorMessage(.hostBlocked)`.
- [ ] **Step 2: Run — fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Pass + lint.**
- [ ] **Step 5: Hand files to the user.**

---

## Task 8: `QueueSnapshot.shieldStatus` + `LogEvent` + `JobLog` header

**Files:**
- Modify: `Sources/GrabberKit/Download/QueueEvent.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine+State.swift` (`buildSnapshot` — pass `.missing` until Task 11 reads the provider)
- Modify: `Sources/GrabberKit/Logging/LogEvent.swift`
- Modify: `Sources/GrabberKit/Logging/JobLog.swift`
- Modify: `Tests/GrabberKitTests/JobLogTests.swift`
- Modify: `Tests/GrabberKitTests/LogEventTests.swift` (or create `LogEventShieldTests.swift` if body-length)

**Interfaces:**
- `QueueSnapshot.init(..., isOnline: Bool, shieldStatus: ShieldStatus = .missing)`
- `buildSnapshot()` currently omit → uses default; Task 11 will pass live status.
- `LogEvent`: `.shieldStarted(port: Int)`, `.shieldExited(code: Int32)`, `.shieldRestarted(reason: String)`, `.shieldMissing`
  - `key`: `shield.started` / `shield.exited` / `shield.restarted` / `shield.missing`
  - `category`: all four `.deps`
  - `fields`: port / code / reason as strings
- `JobLog.writeHeader` adds `player_client: \(value ?? "-")`. Pass `playerClient: String? = nil` into `JobLog.init` (default nil so existing tests compile); download spawn in Task 11 passes `job.playerClientUsed`.

- [ ] **Step 1: Failing tests** — `QueueSnapshot(…)` without shieldStatus still compiles (this is the default); log event keys; job log header contains `player_client: -` by default and `tv` when set.
- [ ] **Step 2: Run — fail on missing cases / header.**
- [ ] **Step 3: Implement exhaustive switches. `LogEvent.jobID` already has `default: nil` — no change required there.**
- [ ] **Step 4: Existing `QueueSnapshot(` fixtures compile. Lint.**
- [ ] **Step 5: Hand files to the user.**

---

## Task 9: Protocol `preview` / `ensureShield` / `restartShield` + fakes

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngineProtocol.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (stubs that compile: `preview` → `.failure(.network)` until Task 11; `ensureShield`/`restartShield` no-op until Task 11)
- Modify: `Tests/AppUnitTests/Support/AppFakes.swift`
- Modify: `Tests/GrabberKitTests/QuitCoordinatorTests.swift` (private `FakeEngine`)

**Interfaces:**

```swift
func preview(_ url: String) async -> Result<MediaMetadata, MetadataError>
func ensureShield() async
func restartShield() async
```

`AppFakes.FakeEngine`:
- State: `previewResult: Result<MediaMetadata, MetadataError> = .failure(.malformedOutput)`, `previewed: [String] = []`, `ensureCount`, `restartCount`
- `func stubPreview(_ result: Result<MediaMetadata, MetadataError>)`
- `preview` appends URL, returns stub
- `ensureShield` / `restartShield` increment counters, no-op

QuitCoordinator fake: `preview` → `.failure(.network)`; ensure/restart no-ops (quit tests never call them).

- [ ] **Step 1: Add protocol methods. Build — fakes fail to compile. That is the "failing test".**
- [ ] **Step 2: Fill both fakes + engine stubs.**
- [ ] **Step 3: `AppUnitTests` + `QuitCoordinatorTests` pass. Lint.**
- [ ] **Step 4: Hand files to the user.**

---

## Task 10: `PotPluginInstaller` + `PotProviderProcess`

**Files:**
- Create: `Sources/GrabberKit/PotProvider/PotPluginInstaller.swift`
- Create: `Sources/GrabberKit/PotProvider/PotProviderProcess.swift`
- Create: `Tests/GrabberKitTests/PotPluginInstallerTests.swift`
- Create: `Tests/GrabberKitTests/PotProviderProcessTests.swift`
- Create: `Tests/TestSupport/FakePotProvider.swift` (scriptable `PotProviding` for engine tests)
- Modify: `DownloadEngineProtocol.swift` `.live` — still **do not** start a real server in unit tests; `.live` may construct `PotProviderProcess` but `ensure()` is lazy (Task 11 calls it). Construction must not bind a port.

**Interfaces:**

Installer (filesystem + PATH injected):

```swift
public struct PotPluginInstaller: Sendable {
    public func pluginDirs() -> [URL]
    public func resolveServerLaunch(port: Int, host: String = "127.0.0.1") -> ProcessLaunch?
}
```

Resolver order (injected `home`, `searchPaths`, `isExecutable`, `fileExists` — never the real home in tests):

1. `bgutil-ytdlp-pot-provider` on `searchPaths` (same list as `EnvironmentProbe.defaultSearchPaths`: `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `~/.local/bin`, then `PATH`). Launch: that URL + `["--host", "127.0.0.1", "--port", "\(port)"]`.
2. Else `node` on the same `searchPaths` plus the first existing `server/build/main.js` among:
   - `{home}/Library/Application Support/MediaGrabber/bgutil-server/server/build/main.js`
   - `{home}/.local/share/pipx/venvs/bgutil-ytdlp-pot-provider/lib/` then any `python*/site-packages/**/server/build/main.js` (walk one level of `python*` dirs; do not recurse the whole venv)
   - `{home}/.local/pipx/venvs/bgutil-ytdlp-pot-provider/lib/` same glob (older pipx)
3. Else `nil` → `.missing`.

Plugin dest (always this one dir when a source exists): `{home}/Library/Application Support/MediaGrabber/yt-dlp-plugins/`. Source: the Python package's `yt_dlp_plugins` folder beside `main.js`, or a zip already at `{home}/Library/Application Support/MediaGrabber/bgutil-plugin.zip`. Copy via an injected `PluginStore` (FileManaging has no `copyItem` — do **not** widen that protocol; add:

```swift
public protocol PluginStoring: Sendable {
    func fileExists(atPath: String) -> Bool
    func copyItem(at: URL, to: URL) throws
    func createDirectory(at: URL) throws
}
```

Live impl wraps `FileManager.default`. Tests use a fake map.

`.live` constructs `PotProviderProcess` with the real installer + `URLSessionShieldPinger` + the shared `runner`. Construction must **not** call `ensure()` (no bind until Task 11 / app launch).

Process:

```swift
public actor PotProviderProcess: PotProviding {
    public init(installer: PotPluginInstaller, runner: ProcessRunning, pinger: any ShieldPinging, tuning: EngineTuning, log: LogWriter?)
}
```

```swift
public protocol ShieldPinging: Sendable {
    func ping(_ url: URL, timeout: TimeInterval) async -> Bool
}
```

Live pinger: `URLSession` GET, 2xx = true. Tests: `FakePinger`.

`ensure`: if already `.running` and ping succeeds, return. Else resolve launch for preferred port **4416** if free, else next free loopback port (inject `PortBinding` or try 4416…4426 in tests via a fake that reports 4416 taken). Start child with `--host 127.0.0.1 --port N`. Ping `http://127.0.0.1:N/ping` with `tuning.potHealthTimeoutSeconds`. Success → `.running(port: N)` + log `shieldStarted`. Fail → `.down` or `.missing` if launch was nil (`shieldMissing`). Crash: `shieldExited`, backoff `potRestartBackoffSeconds` (cap 30), `ensure` again.

`restart`: `stop` then `ensure` immediately (log `shieldRestarted(reason: "user")`). Crash path uses reason `"crash"`.

`stop`: SIGTERM then SIGKILL after 2 s — use `Task.cancel` on the runner execution if `ProcessRunning` already cancels the child (it does for downloads). Mirror that.

**No real bind, no real HTTP, no pipx in tests.** Fake installer returns a canned `ProcessLaunch`; fake pinger returns true/false.

- [ ] **Step 1: Failing tests** — installer nil → missing; fake ping true after ensure → `.running(port: 4416)`; ping false → `.down`; restart increments runner launches.
- [ ] **Step 2: Run — fail.**
- [ ] **Step 3: Implement. `function_body_length` — split ensure into helpers.**
- [ ] **Step 4: Pass + lint. `tuist generate`.**
- [ ] **Step 5: Hand files to the user.**

---

## Task 11: Engine `preview`, spawn context, shield intents, `playerClientUsed`

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift`
- Modify: `Sources/GrabberKit/Download/DownloadEngine+State.swift`
- Modify: `Sources/GrabberKit/Logging/JobLog.swift` call site in `launchDownload`
- Modify: `Tests/GrabberKitTests/DownloadEngineTestHelpers.swift` — add `potProvider:` default nil (deps default still Missing)
- Test: `Tests/GrabberKitTests/EnginePreviewTests.swift` (new)
- Test: `Tests/GrabberKitTests/EngineShieldTests.swift` (new)
- Test: `Tests/GrabberKitTests/EngineRetryClientTests.swift` (new)

**Behavior:**

Write `makeContext` without nested `await` in a ternary. `ShieldStatus.running` is associated — compare with `if case .running = status`.

```swift
private func makeContext(url: String, attempt: Int, forceCookies: Bool) async -> ExtractorContext {
    let status = await dependencies.potProvider.status
    let dirs = await dependencies.potProvider.pluginDirs
    let base = await dependencies.potProvider.baseURL
    let isYouTube = RateHost(urlString: url).canonical == "youtube"
    let shieldUp: Bool
    if case .running = status {
        shieldUp = true
    } else {
        shieldUp = false
    }
    let home = dependencies.cookieResolverHome
        ?? FileManager.default.homeDirectoryForCurrentUser
    let cookie = CookieResolver(fileManager: dependencies.fileManager, home: home)
        .resolve(source: preferences.cookiesFromBrowser, jobOverride: forceCookies)
        .argument
    return ExtractorContext(
        pluginDirs: dirs,
        potBaseURL: (isYouTube && shieldUp) ? base : nil,
        playerClient: isYouTube ? PlayerClientRotation.client(forAttempt: attempt) : nil,
        cookieArgument: cookie
    )
}
```

`preview(_ url:)`:
1. Refresh `self.shieldStatus = await dependencies.potProvider.status`.
2. If `queueHalt == .networkDown` → `.failure(.network)`.
3. If `rateLimiter.blocked(host: RateHost(urlString: url), now: dependencies.clock.now)` → `.failure(.hostBlocked)`. (Do **not** use `blockedProbeHostIDs` — that is a `Set<UUID>` of jobs, not hosts.)
4. `let context = await makeContext(url: url, attempt: 0, forceCookies: false)`.
5. `return await dependencies.probe.probe(url, context: context)`.
6. No job, no `probeInFlight`.

`downloadArguments`: pass `context` from `makeContext(url: job.request.url, attempt: job.attempt, forceCookies: job.forceCookies)`. Set `job.playerClientUsed = context.playerClient` in `launchDownload` **before** building argv. Pass `playerClient:` into `JobLog`.

`YtDlpArguments.build` already has `cookieArgument:` — keep passing the resolved cookie there; `context.cookieArgument` is documentary. Do not emit cookies twice.

`launchProbe`: `probe.probe(url, context: await makeContext(url: url, attempt: 0, forceCookies: job.forceCookies))`.

`ensureShield()`: `await potProvider.ensure()`; `shieldStatus = await potProvider.status`; `emitSnapshot()`; no `evaluateSchedule()`.
`restartShield()`: same with `restart()`.
`shutdown()`: existing cancels, then `await potProvider.stop()`; `shieldStatus = await potProvider.status`.

`buildSnapshot()` stays sync: pass `self.shieldStatus`. Do **not** make it async.

`EngineFixture.engine` gains `potProvider: (any PotProviding)? = nil` and passes `potProvider: potProvider ?? MissingPotProvider()` into `EngineDependencies`.

- [ ] **Step 1: Failing tests**
  - preview while `queueHalt = .networkDown` (set via existing halt test helpers / fake monitor) → `.network`
  - YouTube URL while host in cooldown → `.hostBlocked` (use existing cooldown strike path, then preview)
  - success: argv of the **probe** launch contains `player_client=tv` for a youtube URL and does **not** for archive.org
  - no job appears in snapshot after preview
  - FakePotProvider running → snapshot.shieldStatus running after `ensureShield`
  - `MissingPotProvider` → not a halt (`queueHalt == nil`)
  - botCheck auto-retry: script 1 bot-check stderr, script 2 success; `maxAutoRetries: 2`; second launch argv contains `player_client=ios`
  - sabrGated stderr → failed sabr, **one** yt-dlp launch (no auto-retry)

- [ ] **Step 2: Run — fail.**
- [ ] **Step 3: Implement `makeContext` as the single builder.**
- [ ] **Step 4: Pass named suites + lint.**
- [ ] **Step 5: Hand files to the user.**

---

## Task 12: AppModel drops `probe`; paste uses `engine.preview`

**Files:**
- Modify: `Sources/App/AppModel.swift`
- Modify: `Sources/App/MediaGrabberApp.swift`
- Modify: `Tests/AppUnitTests/Support/AppModelTestHelpers.swift`
- Modify: `Tests/AppUnitTests/AppModelTests.swift` (`test_resolvePasted_*` stub `FakeEngine.preview`)

**Behavior:**

Drop `private let probe: MetadataProbing` and the `probe:` init parameter. `init` becomes:

```swift
init(
    engine: DownloadEngineProtocol,
    installer: OnboardingInstaller,
    prefs: Preferences,
    ...
    vpnDetector: any VPNDetecting = InterfaceVPNDetector()
)
```

`resolvePasted`:

```swift
let result = await engine.preview(trimmed)
...
case let .failure(error):
    probeError = error == .botCheck
        ? BotCheckCopy.sentence(vpnActive: vpnDetector.isVPNActive)
        : AppModelDialogs.probeErrorMessage(for: error)
```

`onboardingFinished`:

```swift
await engine.revalidate()
await engine.ensureShield()
await refreshOnboardingState()
```

A `.failed` pipx step still reaches Home (non-blocking). `ensureShield` on a missing installer is a no-op that stays `.missing` — calling it here matches spec §4.1.

Launch: wherever `needsOnboarding` is set false and Home appears, `await engine.ensureShield()`. Hook `AppModel.performLaunchSetup` / the existing `onAppear` on `MainWindow` / `MediaGrabberApp` — pick **one** seam (the existing launch probe of env is `refreshOnboardingState`; add `ensureShield` after it when `!needsOnboarding`).

`func restartShield() async { await engine.restartShield() }` — Task 15/16 call this.

`MediaGrabberApp`: delete `MetadataProbe(ytDlpURL:)` and the `probe:` argument. `EngineDependencies.live` remains the single owner of `MetadataProbe`.

Helpers: drop `probe:`. `test_resolvePasted_success` does `engine.stubPreview(.success(meta))`. Add `test_onboardingFinished_callsEnsureShield` asserting `engine.ensureCount == 1`.

- [ ] **Step 1: Rewrite AppModelTests to stub `FakeEngine.preview` first (they fail until AppModel drops `probe`).**
- [ ] **Step 2: Implement AppModel + app entry.**
- [ ] **Step 3: `AppUnitTests` pass. Lint.**
- [ ] **Step 4: Hand files to the user.**

---

## Task 13: Preferences audio language + Downloads pane

**Files:**
- Modify: `Sources/GrabberKit/Model/Preferences.swift`
- Modify: `Sources/App/Preferences/Panes/DownloadsPane.swift`
- Modify: `Tests/GrabberKitTests/PreferencesTests.swift`

**Interfaces:**
- `defaultAudioLanguagePolicy` key `mg.defaultAudioLanguagePolicy`, default `.youtubeDefault`
- `lastAudioLanguage: LastAudioLanguage?` key `mg.lastAudioLanguage`
- `ownedKeys` + `resetToDefaults` include both
- Downloads pane: `PrefRow` **Audio language**, helper `"Used when this video has that kind of track."`, `SkinnedSegment([AudioLanguagePolicy.youtubeDefault, .original])` labels `"YouTube default"` / `"Original"`, inserted **after Video quality, before Audio format**

- [ ] **Step 1: Failing PreferencesTests** — default policy, round-trip, reset clears last.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Pass + lint.**
- [ ] **Step 4: Hand files to the user.**

---

## Task 14: Runway Language slot + quality/language seed

**Files:**
- Modify: `Sources/GrabberKit/Download/FormatCatalog.swift` (add `VideoQualityOptions` + `AudioLanguageSeed`)
- Modify: `Sources/App/Rows/RequestBuilder.swift` (`RunwayOverrides.audioLanguage`)
- Modify: `Sources/App/Home/RunwayView.swift`
- Modify: `Sources/App/Home/HomeView.swift`
- Modify: `Sources/App/AppModel.swift` `grab` writes `lastAudioLanguage`
- Test: `Tests/GrabberKitTests/VideoQualityOptionsTests.swift` (new)
- Test: `Tests/GrabberKitTests/AudioLanguageSeedTests.swift` (new)
- Modify: `Tests/AppUnitTests/RunwaySeedTests.swift` (type/folder unchanged)
- Modify: `Tests/AppUnitTests/RequestBuilderTests.swift` if present, else add assertions in a small App test

**Seed rules (copy from spec §7.2 / §7.3):**

`VideoQualityOptions.offered`:
- `.unknown` → `[2160, 1440, 1080, 720, 480, Int.max]`
- `.listed` with max height H → ladder rungs `<= H` plus `Int.max`
- `.listed` empty heights → `[Int.max]`

`VideoQualityOptions.seed(last:defaultHeight:offered:)`: last if in offered, else default if in offered, else max numeric, else `Int.max`.

`AudioLanguageSeed.pick`: last original if present; last code if present (prefer non-original if last was a dub); else policy original if present; else `isDefault` track; else synthetic Default.

`RunwayOverrides` gains `audioLanguage: AudioLanguage? = nil`. `RequestBuilder.build` writes `audioLanguage: overrides.audioLanguage ?? .unspecified` onto `DownloadRequest`.

Home: `@State private var selectedTrackID: String = "default"`. On successful resolve, re-seed **only** `videoHeight` and `selectedTrackID` from catalog. Type + folder stay. Language picker rows = `resolved.audioTracks` (if empty, one Default). `RunwayView` slot order: Link, Type, Format, Language, Save to.

```swift
static func audioLanguage(from track: AudioTrack) -> AudioLanguage {
    if track.languageCode == nil { return .unspecified }
    if track.isOriginal { return .original }
    return .code(track.languageCode!)
}
```

`AppModel.grab`: after building the request, write last language:

```swift
switch request.audioLanguage {
case .original: prefs.lastAudioLanguage = .original
case let .code(code): prefs.lastAudioLanguage = .code(code)
case .unspecified: break
}
```

Reuse `RunwayView.qualityLadder` labels for offered rungs — filter the existing ladder by `offered` ids; keep "Best available" / `Int.max`. Offered rungs drive the Format picker when `mediaType == .video`.

- [ ] **Step 1: Failing catalog tests** (pure GrabberKit) — unknown → full ladder; listed 1080 → `[1080, 720, 480, Int.max]`; empty heights → `[Int.max]`; seed prefers last, then default, then max numeric; language seed order as spec §7.3.
- [ ] **Step 2: Implement catalog.**
- [ ] **Step 3: Wire runway + RequestBuilder + grab last-write. Lint + AppUnitTests.**
- [ ] **Step 4: Hand files to the user.**

---

## Task 15: Shield chip + live `↻`

**Files:**
- Modify: `Sources/App/Chrome/HealthController.swift`
- Modify: `Sources/App/Chrome/HealthStrip.swift`
- Modify: `Sources/App/MainWindow.swift`
- Modify: `Sources/App/AppModel.swift` (`restartShield` forward)
- Modify: `Tests/AppUnitTests/HealthControllerTests.swift`

**Behavior:**

```swift
private func shieldChip(_ status: ShieldStatus) -> HealthChip {
    switch status {
    case .running:
        HealthChip(id: "shield", label: "shield", dot: .ok, interaction: .none)
    case .down, .missing:
        HealthChip(id: "shield", label: "shield · offline", dot: .attention, interaction: .refresh)
    }
}

func update(snapshot: QueueSnapshot, now _: Date) {
    var next: [HealthChip] = [shieldChip(snapshot.shieldStatus), onlineChip(snapshot.isOnline)]
    ...
}
```

Existing tests: `chips[0]` was online — **update** them. After this task, `chips[0]` is the shield (default snapshot `.missing` → attention + refresh) and online is `chips[1]`. Helper `snapshot(online:summary:shield:)` default `.missing`. Cooldown tests that used `chips[1]` become `chips[2]`.
- `HealthStrip`: split `case .none, .refresh`. `.refresh` is a `Button` showing `chipBody` + trailing `Text("↻")`. `onRefresh: ((HealthChip) -> Void)? = nil`.
- `MainWindow`: `HealthStrip(chips:onRefresh:)` → if `chip.id == "shield"` `{ Task { await appModel.restartShield() } }`
- `AppModel.restartShield()` → `await engine.restartShield()` then the next snapshot updates the controller (consumer already calls `healthController.update`).

No toast.

- [ ] **Step 1: Failing HealthControllerTests** — missing → first chip offline + refresh; running → first chip ok + none; online still present.
- [ ] **Step 2: Implement controller + strip + MainWindow.**
- [ ] **Step 3: Pass + lint.**
- [ ] **Step 4: Hand files to the user.**

---

## Task 16: `potProviderDown` banner

**Files:**
- Modify: `Sources/App/Chrome/BannerResolver.swift`
- Modify: `Sources/App/Chrome/AppModel+Banner.swift`
- Modify: `Tests/AppUnitTests/BannerResolverTests.swift`

**Behavior:**
- `BannerReason.potProviderDown`
- `bannerPriority` append last
- `bannerCopy`: text `"Bot-check protection is offline — some downloads may fail or be low-res."`, button `"Restart"`, action = the `onRetry` closure **or** a new `onRestart` parameter. Do **not** reuse circuit "Retry now" copy. Add `onRestart: (@Sendable () async -> Void)? = nil` to `bannerCopy` / pass `onRetry` only for circuit and `onRestart` for pot. Simplest: the existing `onRetry` closure is **provided by AppModel per reason** — change `recomputeBanner` to pass `{ await self?.restartShield() }` when the resolved reason is pot, and `{ await self?.resetAllCircuits() }` when circuit.

```swift
bannerContent = bannerCopy(...) { [weak self] in
    switch reason {
    case .circuitOpen: await self?.resetAllCircuits()
    case .potProviderDown: await self?.restartShield()
    default: break
    }
}
```

- `activeBannerReasons(halt:shieldStatus:)`: start from halt set, if `shieldStatus != .running` insert `.potProviderDown`.
- `recomputeBanner` passes `snapshot.shieldStatus`.

- [ ] **Step 1: Failing BannerResolverTests** — pot last in priority; copy + Restart button; circuit still beats pot when both active.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Pass + lint.**
- [ ] **Step 4: Hand files to the user.**

---

## Task 17: Mockup, verify docs, full suite

**Files:**
- Modify: `docs/mockups/screens.html` (under `apps/media-grabber/docs/mockups/screens.html`)
- Verify (no rewrite unless drift): `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md`, `apps/media-grabber/docs/design-system.md`, `apps/media-grabber/ticket-backlog.md`, spec header still "design complete" until ship

**Mockup:** Home runway five slots including Language; Downloads pane Audio language row; health strip `shield · offline` with `↻`; banner sentence + Restart.

**Do not** copy Phase 7 into `specs/archived/` until the phase ships. Do not duplicate the Phase 6 dual-tree clutter.

- [ ] **Step 1: Update `screens.html`.**
- [ ] **Step 2: Read design-system §4.2.2 / §4.6 and parent §5.3 / §12.1 Phase 7 — if they already match the spec, leave them. Fix only drift.**
- [ ] **Step 3: Lint + full `MediaGrabber-Workspace` test suite. Fix failures.**
- [ ] **Step 4: `make` from `apps/media-grabber/` — BUILD SUCCEEDED. Manual smoke is the spec §11.1 list (user).**
- [ ] **Step 5: Hand files to the user.** No git.

---

## Self-review (plan vs spec)

| Spec | Task |
|---|---|
| EngineTuning pot keys | 0 |
| PlayerClientRotation, ExtractorContext, ShieldStatus | 1 |
| PotProviding default stub, EngineDependencies | 2 |
| YtDlpArguments context flags + redaction | 3 |
| AudioLanguage + DownloadRequest + `-f` splice | 4 |
| MediaMetadata lets + decode + probe context argv | 5 |
| ErrorSignatures bridge, presentation, isAutoRetryable, hostBlocked map | 6 |
| VPN + copy + hostBlocked dialog | 7 |
| QueueSnapshot default, LogEvent, JobLog | 8 |
| Protocol + both FakeEngines | 9 |
| Installer + process (no real bind) | 10 |
| preview, spawn client, ensure/restart/shutdown, playerClientUsed | 11 |
| AppModel / MediaGrabberApp | 12 |
| Preferences + Downloads pane | 13 |
| Runway five slots + seed | 14 |
| Shield chip + ↻ | 15 |
| Banner potProviderDown | 16 |
| screens.html + verify docs + full suite | 17 |
| `potProviderDown` not a halt | 11 (EngineShieldTests) |
| Playlist inherit / chip toast / brew node | out of scope (spec deferred) |

**Spec imprecision fixed in Task 11:** preview host-block uses `rateLimiter.blocked(host:now:)`, not `blockedProbeHostIDs` (`Set<UUID>` of jobs).
