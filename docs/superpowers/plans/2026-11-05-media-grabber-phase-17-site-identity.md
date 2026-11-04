# Phase 17 Site / Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** YouTube's player-client order can change without an app release, a bot-check burns that client for the rest of that job, failure copy names the real cause in plain words, and a chosen browser can be limited to named sites.

**Architecture:** A pure picker chooses the first unburned client from an ordered list. A small store caches a JSON document for 24 hours and falls back to the bundled list. `makeContext` asks that store only for YouTube. The burned set lives on the in-memory job. Sign-in scope is a separate preference from the site list, and `makeContext` omits the cookie argument when the scope says this host is out. Copy and the Home nudge are app-side and do not change the engine's shield state machine.

**Tech Stack:** Swift, SwiftUI, XCTest, URLSession, yt-dlp.

**Spec:** `apps/media-grabber/docs/superpowers/specs/2026-11-05-media-grabber-phase-17-site-identity-design.md`

## Global Constraints

- Build, test and lint only through make, from `apps/media-grabber`: `make test ONLY=GrabberKitTests/<Suite>` or `ONLY=AppUnitTests/<Suite>`, then `make lint`. Never raw `xcodebuild`. At most one MediaGrabber.app may exist on the machine. `make test` already runs `tuist generate`.
- No git commands. New Swift files under the existing `Sources/**` and `Tests/**` globs are picked up by generate. Do not edit `Project.swift` for those files.
- Comments are single-line `//` only, at most 120 columns. No `///`. No phase, ticket or spec-section references in source or UI copy.
- User-facing copy is true for the real cause, plain, and names one later-reachable action when a fix exists. No command, and no `yt-dlp`, `pipx`, `ffmpeg`, or `shield` in a sentence a person reads. The onboarding step that installs Homebrew may still say `Homebrew`, because that is the thing the button installs.
- No network in tests. The catalog fetcher is an injected closure.
- A missing or stopped YouTube check does not send the user back through onboarding and does not stop the queue. POT is attached only when the helper status is `.running` and the host is YouTube.
- Cookie values are still read only from the one browser the user chose. Nothing in this plan scans another browser.
- No task leaves a no-op branch for a later task. The suite named in the task is green at the end of the task.

## Decisions

- **Picker.** `PlayerClientRotation.client(order:burned:)` returns the first non-empty entry in `order` that is not in `burned`. If none remain, it returns the last non-empty entry. If `order` has no non-empty entry, it returns `tv`. Attempt index is not an input. A failure that is not a bot-check does not burn, so the next attempt of that job uses the same client.
- **Burn scope.** `DownloadJob.burnedPlayerClients` is in memory only. It is not on `PersistedJob`. A probe has no job, so a probe does not burn a client.
- **Catalog.** Remote URL is `https://raw.githubusercontent.com/Mshardul/Tools/main/apps/media-grabber/config/player-clients.json`. Max age is 86400 seconds. A fetch runs only when a YouTube context is built and the saved copy is older than that. Invalid JSON, an empty array, a blank string, or a thrown fetch keeps the saved copy, then the bundled list.
- **Sign-in mode.** `SignInScope.allSites` is the default and ignores the site list. `SignInScope.listedSites` sends the browser only when `sites` contains `RateHost.canonical`. An empty list sends it nowhere and does not change the mode.
- **Add-site confirm.** Offered only when the mode is `listedSites`, a browser is chosen, the failure's sign-in advice is `.checkBrowser`, and the host is not listed. Confirm appends the canonical host and restarts. Cancel does neither. `allSites` never switches to `listedSites` because of a failure. No browser chosen keeps today's Preferences handoff.
- **Which sentence names the site.** YouTube bot-check sentences already say YouTube. Age-restricted and private sentences stay as they are. The new confirmation is what names the site being added. Do not add a site argument to `SignInCopy`.
- **Audit table.** `docs/copy-audit.md` has one row per sentence Task 4 changes, plus one kept row for each existing `SignInCopy` sentence and each `probeErrorMessage` arm Task 4 does not rewrite.

## Review Focus

- A failed or invalid catalog fetch leaves the previous order in place, and the bundled order when nothing was saved. Pinned in Task 2.
- A bot-check burns the client on that job only; the next YouTube job starts at `tv`. A non-bot-check failure does not burn. Pinned in Task 3.
- Building a context for a non-YouTube URL does not call the catalog and sets no player client. Pinned in Task 3.
- `listedSites` with an empty list omits `--cookies-from-browser` on every host. `allSites` sends it even when the list is non-empty. Pinned in Task 6.
- Cancelling the add-site confirmation does not append the host and does not restart. Pinned in Task 7.

---

### Task 1: Player-client picker

**Files:**

- Modify: `apps/media-grabber/Sources/GrabberKit/Download/PlayerClientRotation.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/PlayerClientRotationTests.swift`

**Interfaces:**

- Consumes: nothing
- Produces: `PlayerClientRotation.bundled: [String]` equal to `["tv", "ios", "tv_embedded", "mweb", "web_safari"]`. `PlayerClientRotation.client(order: [String], burned: Set<String>) -> String`. Keep `client(forAttempt:)` compiling by implementing it as `client(order: bundled, burned: [])`, so existing callers stay on `tv` until Task 3 passes a real burned set. That is a behavior change from indexing by attempt; Task 3's engine test is what locks the new rule in the engine.

- [ ] **Step 1: Write the failing test**

```swift
func testFirstUnburnedClient() {
    XCTAssertEqual(PlayerClientRotation.client(order: ["tv", "ios"], burned: []), "tv")
    XCTAssertEqual(PlayerClientRotation.client(order: ["tv", "ios"], burned: ["tv"]), "ios")
}

func testExhaustedOrderUsesTheLastClient() {
    XCTAssertEqual(PlayerClientRotation.client(order: ["tv", "ios"], burned: ["tv", "ios"]), "ios")
}

func testEmptyOrderUsesTv() {
    XCTAssertEqual(PlayerClientRotation.client(order: ["", " "], burned: []), "tv")
}

func testBundledOrder() {
    XCTAssertEqual(
        PlayerClientRotation.bundled,
        ["tv", "ios", "tv_embedded", "mweb", "web_safari"]
    )
}
```

- [ ] **Step 2: Run** `make test ONLY=GrabberKitTests/PlayerClientRotationTests`. Expect a compile failure because `client(order:burned:)` does not exist.
- [ ] **Step 3: Implement** the two functions in `PlayerClientRotation.swift` with the decision above. Skip empty and whitespace-only entries.
- [ ] **Step 4: Run** the same suite, then `make lint`. Expect pass.

### Task 2: Catalog decode and 24-hour cache

**Files:**

- Create: `apps/media-grabber/Sources/GrabberKit/Download/PlayerClientCatalog.swift`
- Create: `apps/media-grabber/config/player-clients.json`
- Create: `apps/media-grabber/Tests/GrabberKitTests/PlayerClientCatalogTests.swift`

**Interfaces:**

- Consumes: `PlayerClientRotation.bundled`
- Produces: `PlayerClientCatalog.remoteURL: URL`. `PlayerClientCatalog.clients(from: Data) -> [String]?` returns nil unless the data is a JSON object with a non-empty `playerClients` array of non-empty strings. `PlayerClientCatalogStore.init(directory: URL, now: @escaping @Sendable () -> Date, maxAge: TimeInterval = 86_400)`. `func order(fetch: @Sendable () async throws -> Data) async -> [String]`.

- [ ] **Step 1: Write the failing tests** in `PlayerClientCatalogTests`. Use a temporary directory and a `now` closure the test moves forward.
  - `clients(from:)` of `{"playerClients":["ios","tv"]}` equals `["ios", "tv"]`.
  - `clients(from:)` returns nil for `{}`, `{"playerClients":[]}`, `{"playerClients":[""]}`, `{"playerClients":[1]}`, and `"nope"`.
  - `order` with no file and a fetch that throws equals `PlayerClientRotation.bundled`, and a later `order` within the hour does call fetch (nothing valid was saved).
  - A fetch of the ios/tv payload makes `order` return that list. A second `order` one hour later, whose fetch records a call, does not call fetch and still returns that list.
  - Moving `now` forward by 86401 seconds calls fetch. A thrown fetch then still returns the saved ios/tv list.
  - An invalid payload when a valid file exists leaves the saved list.
- [ ] **Step 2: Run** `make test ONLY=GrabberKitTests/PlayerClientCatalogTests`. Expect a compile failure.
- [ ] **Step 3: Implement** the type. Persist one JSON file in `directory` containing `playerClients` and an ISO-8601 `fetchedAt`. Write that file only after a payload `clients(from:)` accepts. `remoteURL` is the URL in Decisions. Write `config/player-clients.json` as `{"playerClients":["tv","ios","tv_embedded","mweb","web_safari"]}`.
- [ ] **Step 4: Run** the suite, then `make lint`. Expect pass.

### Task 3: Use the catalog on YouTube and burn a bot-check

**Files:**

- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngineProtocol.swift` (`EngineDependencies`)
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadJob.swift`
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine+Preview.swift` (`makeContext`)
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine+Launch.swift` (the download `makeContext` call)
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine+Mutations.swift` (`recordExit` / `routeFailure`)
- Create: `apps/media-grabber/Tests/GrabberKitTests/PlayerClientBurnTests.swift`
- Modify: `apps/media-grabber/Tests/GrabberKitTests/PersistenceTests.swift` only if a round-trip assertion is easier there; otherwise assert in the new suite that `PersistedJob` encoding of a job has no `burnedPlayerClients` key.

**Interfaces:**

- Consumes: `PlayerClientRotation.client(order:burned:)`, `PlayerClientCatalog`, `PlayerClientCatalogStore`
- Produces: `protocol PlayerClientOrdering: Sendable { func order() async -> [String] }`. `struct BundledPlayerClientOrder: PlayerClientOrdering` returns `PlayerClientRotation.bundled`. `EngineDependencies.playerClientOrder: any PlayerClientOrdering`, default `BundledPlayerClientOrder()`, so existing test inits keep compiling. `DownloadJob.burnedPlayerClients: Set<String>`, default empty, absent from `PersistedJob`. `makeContext(url:attempt:burnedClients:passcode:)` with `burnedClients` defaulting to `[]`.

- [ ] **Step 1: Write the failing tests** in `PlayerClientBurnTests`, using `EngineFixture` and `FakeProcessRunner` the way `EngineRateLimitTests` does.
  - A counting `PlayerClientOrdering` is not called for `https://vimeo.com/1`, and that context's `playerClient` is nil.
  - YouTube, order `["tv", "ios"]`, a bot-check script then a success script: the first yt-dlp argv contains `player_client=tv`, the second contains `player_client=ios`.
  - A second submitted YouTube job's first argv contains `player_client=tv`.
  - A non-bot-check failure (disk-full stderr, as in `testNonRateLimitFailureDoesNotTouchHostState`) followed by a retry still launches with `player_client=tv`.
  - Encoding the persisted form of a job whose in-memory `burnedPlayerClients` is `["tv"]` does not contain the key `burnedPlayerClients`.
  - YouTube with the helper `.running` still sets `potBaseURL`; YouTube with `.missing` does not. Use the existing pot-provider test double if one exists; otherwise a one-case fake in the test file.
- [ ] **Step 2: Run** `make test ONLY=GrabberKitTests/PlayerClientBurnTests`. Expect failure.
- [ ] **Step 3: Implement.** `EngineDependencies.live` builds a `PlayerClientCatalogStore` in Application Support under `MediaGrabber/player-clients`, and a `PlayerClientOrdering` whose `order()` calls `store.order` with `URLSession.shared.data(from: PlayerClientCatalog.remoteURL)`. The download launch passes `job.burnedPlayerClients`. When `routeFailure` classifies `.botCheck` and `job.playerClientUsed` is non-nil, insert it into `job.burnedPlayerClients` before the job is re-queued or marked failed. Do not add the set to `PersistedJob`.
- [ ] **Step 4: Run** `PlayerClientBurnTests`, `PlayerClientRotationTests`, and `ExtractorContextTests`, then `make lint`. Expect pass.

### Task 4: Plain copy

**Files:**

- Modify: `apps/media-grabber/Sources/App/Rows/BotCheckCopy.swift`
- Modify: `apps/media-grabber/Sources/App/AppModelDialogs.swift` (the `.ytDlpMissing, .launchFailed` sentence)
- Modify: `apps/media-grabber/Sources/App/AppModelDiagnostics.swift` (the update-failure toast)
- Modify: `apps/media-grabber/Sources/App/Chrome/HealthController.swift` (`shieldChip`)
- Modify: `apps/media-grabber/Sources/App/Table/GridAccessibility.swift`
- Modify: `apps/media-grabber/Sources/App/Onboarding/OnboardingView.swift` (the bot-check step title only)
- Modify: `apps/media-grabber/Sources/App/About/AboutView.swift` (the two tool row titles)
- Modify: `apps/media-grabber/Tests/AppUnitTests/BotCheckCopyTests.swift`
- Create: `apps/media-grabber/docs/copy-audit.md`
- Create: `apps/media-grabber/Tests/AppUnitTests/UserFacingJargonTests.swift`

**Interfaces:**

- Consumes: nothing from earlier tasks
- Produces: the sentences below. Later tasks display them and do not reword them.

- [ ] **Step 1: Write the failing assertions** in `BotCheckCopyTests` and `UserFacingJargonTests`.
  - Shield `.down`, YouTube: `YouTube didn't accept this request because the YouTube check stopped working.`
  - Shield `.missing`, YouTube: `YouTube didn't accept this request. The YouTube check isn't set up on this Mac.` The string does not contain `sign in`.
  - Non-YouTube, any shield status, advice `.none`: the existing sentence, and it does not contain `shield` or `YouTube check`.
  - `AppModelDialogs.probeErrorMessage(for: .ytDlpMissing)` equals `The downloader isn't installed. Open setup.`
  - `UserFacingJargonTests` asserts the chip labels `YouTube check · on`, `YouTube check · offline`, `YouTube check · not set up`, the accessibility label `Restart YouTube check`, the onboarding step title `YouTube check`, and the About titles `Downloader` and `Media tools`. It also asserts none of those strings, and none of the `BotCheckCopy` outputs above, contain `yt-dlp`, `pipx`, `ffmpeg`, or `shield`.
- [ ] **Step 2: Run** `make test ONLY=AppUnitTests/BotCheckCopyTests` and `ONLY=AppUnitTests/UserFacingJargonTests`. Expect failure.
- [ ] **Step 3: Implement** the replacements. The update-failure toast text is `Couldn't update the downloader.` with no interpolated reason. Leave `SignInCopy` as it is. Write `docs/copy-audit.md` with one row per sentence this task changes and one kept row for each `SignInCopy` sentence and each unchanged `probeErrorMessage` arm. Columns: surface, trigger, string, and the four verdicts (true, plain, says what is wrong, one later-reachable action or none).
- [ ] **Step 4: Run** both suites and any existing health-chip or About test that asserted the old labels, then `make lint`. Expect pass.

### Task 5: Dismissible YouTube-check line

**Files:**

- Create: `apps/media-grabber/Sources/App/Home/YouTubeCheckNudge.swift`
- Modify: `apps/media-grabber/Sources/App/Home/HomeView.swift`
- Modify: `apps/media-grabber/Sources/App/AppModelEmptyState.swift` (the defaults flag next to `hasCompletedOnboarding`)
- Create: `apps/media-grabber/Tests/AppUnitTests/YouTubeCheckNudgeTests.swift`

**Interfaces:**

- Consumes: the Task 4 name "YouTube check"
- Produces: `YouTubeCheckNudge.message == "YouTube downloads work better with the YouTube check set up."`, `YouTubeCheckNudge.button == "Set it up"`, `YouTubeCheckNudge.isVisible(onboardingComplete: Bool, shield: ShieldStatus, dismissed: Bool) -> Bool`. Defaults key `mg.youtubeCheckNudgeDismissed`.

- [ ] **Step 1: Write the failing test**

```swift
func testVisibleOnlyWhenSetupWasSkippedAndTheCheckIsMissing() {
    XCTAssertTrue(YouTubeCheckNudge.isVisible(onboardingComplete: true, shield: .missing, dismissed: false))
    XCTAssertFalse(YouTubeCheckNudge.isVisible(onboardingComplete: false, shield: .missing, dismissed: false))
    XCTAssertFalse(YouTubeCheckNudge.isVisible(onboardingComplete: true, shield: .down, dismissed: false))
    XCTAssertFalse(YouTubeCheckNudge.isVisible(onboardingComplete: true, shield: .running(port: 4416), dismissed: false))
    XCTAssertFalse(YouTubeCheckNudge.isVisible(onboardingComplete: true, shield: .missing, dismissed: true))
}
```

- [ ] **Step 2: Run** `make test ONLY=AppUnitTests/YouTubeCheckNudgeTests`. Expect a compile failure.
- [ ] **Step 3: Implement** the enum and the defaults flag. In both Home layouts, when `isVisible` is true, show `message` and a button titled `button` that calls `shieldSetup.present()`, plus a dismiss control that sets the flag. Dismissal survives a new `AppModel` using the same defaults. `.down` shows nothing here; the existing chip stays.
- [ ] **Step 4: Run** the suite, then `make lint`. Expect pass.

### Task 6: Sign-in scope

**Files:**

- Create: `apps/media-grabber/Sources/GrabberKit/Cookies/SignInScope.swift`
- Modify: `apps/media-grabber/Sources/GrabberKit/Model/Preferences.swift` (`ownedKeys` included)
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine+Preview.swift` (`makeContext` cookie argument)
- Modify: `apps/media-grabber/Sources/App/Preferences/Panes/SignInCookiesPane.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/SignInScopePolicyTests.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/SignInScopeEngineTests.swift`

**Interfaces:**

- Consumes: `RateHost.canonical`, `CookieResolver.resolve(source:)`
- Produces: `enum SignInScope: String, Codable, Sendable { case allSites, listedSites }`. `SignInScopePolicy.sendsCookies(scope: SignInScope, sites: [String], host: String) -> Bool`. `Preferences.signInScope` key `mg.signInScope`, default `.allSites`. `Preferences.signInSites` key `mg.signInSites`, a JSON string array, default `[]`.

- [ ] **Step 1: Write the failing tests**
  - Policy: `allSites` returns true for `youtube` and for `vimeo` whether `sites` is `[]` or `["youtube"]`. `listedSites` returns true only for a host in the list, and false for `youtube` when the list is empty.
  - A fresh `Preferences` reports `.allSites` and `signInSites == []`. Both keys are removed by `resetToDefaults()`.
  - Engine: browser set to Safari, `allSites`, a vimeo launch argv contains `--cookies-from-browser`. Same browser, `listedSites`, sites `["youtube"]`: a youtube argv contains it and a vimeo argv does not. Same browser, `listedSites`, sites `[]`: a youtube argv does not contain it. Browser `.none`: no argv contains it, for either scope.
- [ ] **Step 2: Run** `make test ONLY=GrabberKitTests/SignInScopePolicyTests` and `ONLY=GrabberKitTests/SignInScopeEngineTests`. Expect failure.
- [ ] **Step 3: Implement.** In `makeContext`, resolve cookies only when a browser is chosen and `sendsCookies` is true for `RateHost(urlString: url).canonical`. On the sign-in pane, under the browser row, add a control labeled `Use sign-in for` with the choices `All sites` and `Only these sites`. When the second is selected, list `signInSites` and let a row be removed. Do not add a free-text site adder; Task 7 adds sites from a failure.
- [ ] **Step 4: Run** both suites plus `CookieResolverResolveTests`, then `make lint`. Expect pass.

### Task 7: Confirm before adding a site

**Files:**

- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine+Helpers.swift` (`availableActions`)
- Modify: the snapshot call site that passes `signInAdvice` into `availableActions` (same helper file or `DownloadEngine+State.swift`)
- Modify: `apps/media-grabber/Sources/App/AppModelRowActions.swift`
- Modify: `apps/media-grabber/Sources/App/AppModelDialogs.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/SignInSiteOfferTests.swift`
- Create: `apps/media-grabber/Tests/AppUnitTests/SignInSiteConfirmTests.swift`

**Interfaces:**

- Consumes: `SignInScope`, `SignInScopePolicy.sendsCookies`, `RowAction.retryWithCookies`, `DownloadEngine.retryWithCookies(_:)`
- Produces: `availableActions(..., signInAdvice: SignInAdvice = .none, offerSiteSignIn: Bool = false)`. `offerSiteSignIn == true` adds `.retryWithCookies` the same way `.suggest` does. `AppModelDialogs.signInSiteConfirmation(siteName: String) -> ConfirmationRequest` with title `Use sign-in for this site?`, message `Use your signed-in browser for \(siteName)?`, confirm `Use sign-in`, cancel `Not now`. Site name is `YouTube` when the canonical host is `youtube`, otherwise the canonical host.

- [ ] **Step 1: Write the failing tests**
  - `availableActions` for a failed age-restricted job with advice `.checkBrowser` and `offerSiteSignIn: false` does not contain `.retryWithCookies`. With `offerSiteSignIn: true` it does. Advice `.suggest` still contains it when the flag is false.
  - The engine sets `offerSiteSignIn` only when scope is `listedSites`, a browser is chosen, advice is `.checkBrowser`, and the host is absent from `signInSites`.
  - `signInSiteConfirmation(siteName: "YouTube")` carries the four strings above.
  - App model: a held job, scope `listedSites`, browser chosen, host `vimeo` not listed. The confirm path appends `vimeo` and calls `retryWithCookies`. The cancel path leaves `signInSites` unchanged and does not call `retryWithCookies`. Scope `allSites` does not present this confirmation. No browser chosen still opens the cookies pane and does not append a site.
- [ ] **Step 2: Run** `make test ONLY=GrabberKitTests/SignInSiteOfferTests` and `ONLY=AppUnitTests/SignInSiteConfirmTests`. Expect failure.
- [ ] **Step 3: Implement.** `presentFixPrompt` for `.retryWithCookies`, when a browser is already chosen and the scope is `listedSites`, calls `confirm(signInSiteConfirmation)` instead of `setPendingCookieRetry`. Confirm appends `RateHost(urlString:).canonical` if missing, then `engine.retryWithCookies`. Cancel returns. Any other `.retryWithCookies` press keeps `setPendingCookieRetry` and opens the cookies page.
- [ ] **Step 4: Run** both suites plus `EngineRetryWithCookiesTests`, then `make lint`. Expect pass.
