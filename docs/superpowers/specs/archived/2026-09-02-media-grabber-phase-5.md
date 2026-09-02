# Cookies (Phase 5)

**Status:** design complete. Plan: not yet written. Parent spec:
`docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1.
Phase 2 (shipped): `docs/superpowers/specs/queue-foundation.md`.
Phase 3 (shipped): `docs/superpowers/specs/archived/2026-08-31-media-grabber-phase-3.md`.
Phase 4 (shipped): `docs/superpowers/specs/archived/2026-09-01-media-grabber-phase-4.md`.
Phase 1 (shipped): `docs/superpowers/specs/archived/core-download-pipeline.md`.

Phases 1–4 built the download pipeline, the engine-owned queue and scheduler, the
Downloads table with its row-action bar, per-job raw logs, persistence, the
Preferences editor, and retry / error classification. Phase 5 lets the user hand
`yt-dlp` a browser's YouTube sign-in so age-restricted and private videos, and
videos behind a bot check, can be downloaded. It is **opt-in**: no cookies touch
a download unless the user picks a browser in Preferences or presses the `🔑`
Retry-with-cookies action on a failed row.

Everything here is built to its final-app form. `CookieSource`, `CookieResolver`,
and the filled Sign-in & cookies pane are the shapes the app keeps; a future
always-on-cookies decision reuses `CookieResolver` unchanged (parent §12 scoping
rule).

---

## 1. Scope

**In this phase:**

- **`CookieSource`** — a `GrabberKit` value type: `.none`, `.safari`, `.chrome`,
  `.brave`, `.edge`, `.firefox(profile: String?)`. `Codable` for `Preferences`.
  Carries a stable `browserKey` string (`"safari"`, `"firefox"`, …) for logs and
  the help-URL lookup, and a `ytDlpSpec` accessor (`"firefox:default-release"`,
  `nil` for `.none`).
- **`CookieResolver`** — `GrabberKit/Cookies/`. Owns `firefoxProfiles()`
  (parses Firefox's `profiles.ini`), `safariAccess()` (a Full-Disk-Access
  probe-read of the Safari cookie container), and
  `resolve(source:jobOverride:) -> CookieResolution` (`{ argument: String?,
  verdict: CookieVerdict }`). Filesystem is injected for tests.
- **`Preferences.cookiesFromBrowser: CookieSource`**, default `.none`. One
  composite field — the Firefox profile rides inside `.firefox(profile:)`,
  replacing the parent spec's separate `cookiesFromBrowser` + `firefoxProfile`.
- **The Sign-in & cookies pane, filled.** A browser `SkinnedPicker`
  (`None` + 5 browsers); a Firefox-profile `SkinnedPicker` shown only when
  `.firefox` and 2+ profiles exist; a Full Disk Access status row shown only
  when `.safari`; a "Learn more" link row; the recommended-setup tip.
- **`cookieReadFailed` wired live.** New `ErrorSignatures` entries for `yt-dlp`'s
  cookie-read failures, placed before `private` / `unavailable`. Plus a second
  signal: an `Extracted 0 cookies` line during a download whose spawn carried a
  cookie argument, followed by a non-zero exit → `.cookieReadFailed` (the
  Chrome app-bound-encryption case, which prints no error).
- **The `🔑` `retryWithCookies` row action, live.** Offered for
  `.failed(.cookieReadFailed)`, `.failed(.ageRestricted)`, `.failed(.private)`.
  `AppModel`: a browser is set → `engine.retryWithCookies(id)`; browser is
  `.none` → deep-link to `Page.preferences(.cookies)` with a pending-retry
  handoff.
- **`engine.retryWithCookies(_ id:) async`** — parallel to `retry(_:)`. Sets
  `job.forceCookies = true` (a new persisted `DownloadJob` field), does a
  from-scratch retry (deletes `.part`, resets `attempt`), logs `jobRetried`.
- **`YtDlpArguments.build`** gains `cookieArgument: String? = nil`; emits
  `--cookies-from-browser <spec>` before the URL; `redacted` masks the spec.
- **`CookieHelpURL`** — a config constant, per-`browserKey` → a `yt-dlp` FAQ
  wiki anchor, one place, swappable for an app-hosted page later.
- **`screens.html`** — the Sign-in & cookies pane fills (all row types, both the
  Firefox and Safari states); the Home-table `cookieReadFailed` row gets the
  real reason sentence and an enabled `🔑`.

**Deferred (hints land in the owning phase's stub):**

- **`cookieReadFailed` as a non-fatal fallback during a normal download** —
  parent §7.2's "always-on cookies, fall back to no cookies, classify
  `cookieReadFailed` only if the download then fails" belongs with an always-on
  cookies model, which this phase does not ship. Phase 5's `cookieReadFailed`
  fires only on a user-requested cookie read that failed. A future always-on
  phase owns the silent-fallback path.
- **A browser-tailored `cookieReadFailed` sentence** ("Chrome's newer versions
  block cookie access — try Safari or Firefox"). Phase 5 ships the one generic
  sentence; the pane's "Learn more" link covers the specifics. A later variant
  is a `RowModel`-side string swap keyed on `browserKey`, no `GrabberKit`
  change.
- **Per-attempt `player_client` + cookie interplay** — Phase 7. The cookie
  argument is independent of client rotation.
- **Instagram / Twitter / TikTok auto-cookie heuristics** — parent §13 "later",
  not a numbered phase.

**Not in scope:**

- A Full-Disk-Access onboarding step. Cookies are opt-in; most users never pick
  Safari. FDA is requested just-in-time from the Preferences pane. The
  `OnboardingStepID` enum and the 4-step onboarding flow are untouched.
- Keychain-prompt handling for Chrome / Brave / Edge — the first
  `--cookies-from-browser chrome` triggers a macOS Keychain dialog the user
  must approve; it cannot be suppressed or pre-authorised. The pane tip
  mentions it. No code.
- Any `WarningBanner` / `HealthStrip` content — Phase 6 / 7.
- Rate limiting, per-host state, circuit breaker — Phase 6.
- The POT provider / `player_client` rotation — Phase 7.
- Toasts or native notifications — Phase 11.

---

## 2. Architecture

`GrabberKit/Cookies/` is a new self-contained unit — no SwiftUI import. The
Preferences pane and the engine both consume it through plain function calls.

```
Sources/GrabberKit/Cookies/
  CookieSource.swift        — the enum + browserKey + ytDlpSpec; Codable
  FirefoxProfile.swift      — { name, path, isDefault }
  CookieResolver.swift      — firefoxProfiles(), safariAccess(), resolve(source:jobOverride:)
  CookieVerdict.swift       — .unconfigured / .ready(browserKey:) / .needsFullDiskAccess / .noProfiles
  CookieHelpURL.swift       — browserKey → URL, one config constant
  FileManaging.swift        — the 3-method filesystem protocol + FoundationFileManager
Sources/GrabberKit/Model/
  Preferences.swift         — + cookiesFromBrowser: CookieSource (default .none)
Sources/GrabberKit/Download/
  DownloadJob.swift             — + forceCookies: Bool (persisted)
  DownloadEngine+Retry.swift    — + retryWithCookies(_:) intent
  DownloadEngine.swift          — spawn path resolves the cookie argument
  DownloadEngine+Mutations.swift — recordExit gains cookiesRequested; the 0-cookies override
  DownloadEngineProtocol.swift  — + func retryWithCookies(_:) async; EngineDependencies.fileManager
  YtDlpArguments.swift          — build / redacted gain cookieArgument: String?
  ErrorSignatures.swift         — + cookieReadFailed substrings, ordered first
  FailurePresentation.swift     — .cookieReadFailed / .ageRestricted / .private gain .retryWithCookies
Sources/GrabberKit/Model/
  PersistedJob.swift        — + forceCookies round-trip
Sources/App/Preferences/Panes/
  SignInCookiesPane.swift   — the filled pane
Sources/App/Preferences/
  CookiePaneModel.swift     — @Observable, bridges CookieResolver ↔ the pane's rows
Sources/App/
  AppModel.swift            — pendingCookieRetryJobID, resolveCookieRetry()
  AppModelRowActions.swift  — the .retryWithCookies case
```

### The resolver at spawn time

`DownloadEngine.launchDownload` currently builds `GlobalDownloadOptions` from
`preferences` and hands it to `YtDlpArguments.build`. Phase 5 adds, in the same
synchronous setup block (no new async hop — `profiles.ini` and the FDA probe are
small local reads, no process spawn, no network):

```swift
let cookieArgument = CookieResolver(fileManager: dependencies.fileManager)
    .resolve(source: preferences.cookiesFromBrowser, jobOverride: job.forceCookies)
    .argument
```

`cookieArgument` (a `Sendable String?`) is captured into the launcher `Task`
alongside `tuning` / `ytDlpURL` and passed to
`YtDlpArguments.build(for:options:tuning:cookieArgument:)`. Whether a cookie
argument was in play is also passed to `recordExit` as `cookiesRequested: Bool`
(§4.1).

`resolve` decision table:

| `source` | `jobOverride` | `argument` | `verdict` |
|---|---|---|---|
| `.none` | `false` | `nil` | `.unconfigured` |
| `.none` | `true` | a substituted browser's spec, or `nil` | `.ready` / `.unconfigured` |
| `.safari` | either | `"safari"` if FDA readable, else `nil` | `.ready` / `.needsFullDiskAccess` |
| `.firefox(name)` | either | `"firefox:<name-or-default-or-nil>"` | `.ready` / `.noProfiles` |
| `.chrome` / `.brave` / `.edge` | either | `"<key>"` | `.ready` |

The `.none + jobOverride` substitution (the `🔑`-with-no-standing-default path):
try `.safari` when `safariAccess() != .denied`, else the first of
`.chrome` / `.brave` / `.edge` / `.firefox` whose browser-support directory
exists, else `argument: nil`.

The `verdict` is not read by the engine — it only wants `argument`. The
Preferences pane consumes the same call for its status rows.

### The 🔑 path

`engine.retryWithCookies(id)` (§6.4) mirrors `retry(id)`'s from-scratch branch and
additionally sets `job.forceCookies = true`. It is a no-op unless the job is
`.failed` with a class whose `presentation.offeredActions` contains
`.retryWithCookies`.

`AppModel.handleRowAction(id, .retryWithCookies)`:

```swift
if prefs.cookiesFromBrowser.isNone {
    pendingCookieRetryJobID = id
    page = .preferences(.cookies)
} else {
    await engine.retryWithCookies(id)
}
```

The pane's picker moving off `.none` while `pendingCookieRetryJobID` is set calls
`AppModel.resolveCookieRetry()`, which fires `engine.retryWithCookies(pendingID)`
and clears the id. A `page` change away from `.preferences(.cookies)` clears an
unconsumed pending id — no dangling retry. The engine stays ignorant of the UI
dance.

### How Phases 6 / 7 attach

- Phase 7's `player_client` argv token threads into
  `YtDlpArguments.build` as a second orthogonal parameter — no interaction with
  `cookieArgument`.
- Phase 6's rate limiting does not touch cookies.
- A future always-on-cookies decision reuses `CookieResolver` unchanged: it
  would default `cookiesFromBrowser` to `.safari` and add the silent-fallback
  classification on the engine side.

---

## 3. `CookieSource` and `CookieResolver`

### 3.1 `CookieSource`

```swift
public enum CookieSource: Sendable, Equatable, Codable {
    case none
    case safari
    case chrome
    case brave
    case edge
    case firefox(profile: String?)   // nil = the default profile

    public var browserKey: String {
        switch self {
        case .none: "none"
        case .safari: "safari"
        case .chrome: "chrome"
        case .brave: "brave"
        case .edge: "edge"
        case .firefox: "firefox"
        }
    }

    public var ytDlpSpec: String? {
        switch self {
        case .none: nil
        case .safari: "safari"
        case .chrome: "chrome"
        case .brave: "brave"
        case .edge: "edge"
        case let .firefox(profile):
            profile.map { "firefox:\($0)" } ?? "firefox"
        }
    }

    public var isNone: Bool { self == .none }
}
```

Synthesized `Codable` handles the associated value. `Preferences` stores it as
JSON under `mg.cookiesFromBrowser`; a decode failure → `.none`.

### 3.2 `FirefoxProfile`

```swift
public struct FirefoxProfile: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String      // profiles.ini [ProfileN] Name=
    public let path: String      // absolute
    public let isDefault: Bool
}
```

### 3.3 `CookieResolver`

```swift
public struct CookieResolver: Sendable {
    public init(
        fileManager: FileManaging = FoundationFileManager(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    )

    public func firefoxProfiles() -> [FirefoxProfile]
    public func safariAccess() -> SafariCookieAccess
    public func resolve(source: CookieSource, jobOverride: Bool) -> CookieResolution
}

public enum SafariCookieAccess: Sendable, Equatable {
    case granted        // the container file opened for reading
    case denied         // it exists but the read was refused — needs Full Disk Access
    case noContainer    // Safari never ran / no cookie file
}

public struct CookieResolution: Sendable, Equatable {
    public let argument: String?
    public let verdict: CookieVerdict
}

public enum CookieVerdict: Sendable, Equatable {
    case unconfigured
    case ready(browserKey: String)
    case needsFullDiskAccess
    case noProfiles
}
```

**`FileManaging`** — `fileExists(atPath:) -> Bool`,
`contentsOfDirectory(at:) -> [URL]` (throwing → returns `[]` on failure in the
protocol's default extension is NOT used; the resolver catches), and
`dataReadable(at:) -> Bool` (an `open(O_RDONLY)` + immediate close; `true` only
on a successful open). `FoundationFileManager` is the real implementation; tests
inject a fake with a scripted filesystem — the same shape as `EnvironmentProbe`'s
injected `isExecutable`.

**`firefoxProfiles()`** — reads
`<home>/Library/Application Support/Firefox/profiles.ini`. Parses the INI:
`[ProfileN]` sections give `Name`, `Path`, `IsRelative` (default 1 → path is
relative to the `Profiles/` dir, else absolute); the `Default=` at the top level
and the `[Install…]` sections' `Default=` mark the default profile. Absent file
→ `[]`. Unparseable sections are skipped, never thrown.

**`safariAccess()`** — targets
`<home>/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies`.
Not `fileExists` → `.noContainer`. `fileExists` and `dataReadable` → `.granted`.
`fileExists` and not `dataReadable` → `.denied`.

**`resolve(source:jobOverride:)`** — the §2 table. The `.none + jobOverride`
substitution order is Safari (when `safariAccess() != .denied`), then Chrome,
Brave, Edge, Firefox by first-existing support directory, then `nil`.

### 3.4 `CookieHelpURL`

```swift
public enum CookieHelpURL {
    public static func url(forBrowserKey key: String) -> URL {
        URL(string: base + anchor(forBrowserKey: key))!
    }

    private static let base = "https://github.com/yt-dlp/yt-dlp/wiki/FAQ"

    // All browsers point at the one cookies section for now; the per-key seam
    // lets a later version split them or swap to an app-hosted page.
    private static func anchor(forBrowserKey _: String) -> String {
        "#how-do-i-pass-cookies-to-yt-dlp"
    }
}
```

---

## 4. `cookieReadFailed`: classification and presentation

### 4.1 The two signals

**stderr signatures** — `ErrorSignatures.table` gains a `cookieReadFailed` entry
**first** in the table (so a cookie-read error on a private video classifies as
the cookie problem, not the video state):

| `ErrorClass` | stderr substrings (case-insensitive) |
|---|---|
| `cookieReadFailed` | `could not find` + `cookies database`; `Permission denied` + `Cookies`; `Failed to decrypt`; `unable to open database file` + `cookies`; `could not copy` + `cookie`; `You must provide at least one` + `cookies` |

Each row is an AND of the listed fragments on one stderr line.

**The 0-cookies signal** — the Chrome app-bound-encryption case prints no error:
`yt-dlp` emits `Extracted 0 cookies` and the download later fails downstream
(bot check, formats missing). `drainDownload` sets
`DownloadDrainOutcome.extractedZeroCookies = true` when any drained line contains
`Extracted 0 cookies`. `recordExit` (§6.3), when
`result.exitCode != 0 && cookiesRequested && outcome.extractedZeroCookies`,
overrides the classified class with `.cookieReadFailed`.

`classifyStderr` order is otherwise unchanged from Phase 4: network signatures
first, then the table (now `cookieReadFailed`-first), then the `ERROR:`
fallthrough, then nil.

### 4.2 `FailurePresentation`

`cookieReadFailed` already has an entry from Phase 4
(`"Couldn't read your browser's sign-in."`, `offeredActions: [.retry]`). Phase 5:

- `.cookieReadFailed` → `offeredActions` becomes `[.retry, .retryWithCookies]`.
- `.ageRestricted` → `offeredActions` gains `.retryWithCookies` (was `[]`).
  Sentence unchanged (`"This video is age-restricted and needs you to be signed
  in."`).
- `.private` → `offeredActions` gains `.retryWithCookies` (was `[]`). Sentence
  unchanged (`"This video is private."`).

The `noRetryKeys` set in `FailurePresentation` drops `private` and
`ageRestricted`; `geoBlocked`, `unavailable`, `depMissing` stay actionless.

`FailurePresentation` stays `{ sentence, offeredActions }` — no URL field. The
"Learn more" affordance lives only in the Preferences pane (§5), not on the
dense table row. A `cookieReadFailed` table row shows its sentence + the `🔑`
button; pressing `🔑` with no browser set opens the pane where "Learn more" is.

### 4.3 `availableActions` for `.failed`

`DownloadEngine.availableActions(for:)` `.failed` arm already reads
`errorClass.presentation.offeredActions.union([.remove, .openInBrowser,
.showLog])` (Phase 4). No change — the widened `offeredActions` sets flow through
automatically. `retryWithCookies` was in `RowAction` from Phase 2 (gated); Phase 5
is the first phase the engine puts it in a job's set.

---

## 5. The Sign-in & cookies pane

Replaces `PrefSteplessPane(.cookies, …)`. Four row types on the Phase 3 `PrefRow`
/ `SkinnedPicker` primitives. Backed by `CookiePaneModel` (`@Observable`, App
target).

### 5.1 `CookiePaneModel`

```swift
@MainActor
@Observable
final class CookiePaneModel {
    init(prefs: Preferences,
         resolver: CookieResolver = CookieResolver(),
         settingsLink: SettingsLinkOpening = WorkspaceSettingsLink(),
         openURL: OpenURLSink = WorkspaceOpenURLSink())

    var source: CookieSource { get set }   // get/set prefs.cookiesFromBrowser; set → refresh()
    private(set) var firefoxProfiles: [FirefoxProfile]
    private(set) var safariAccess: SafariCookieAccess

    var selectedFirefoxProfile: String?    // get/set the .firefox(profile:) associated value

    func onAppear()                        // refresh()
    func openFullDiskAccessSettings()
    func openHelp()                        // CookieHelpURL for source.browserKey
    private func refresh()
}
```

`refresh()`: `firefoxProfiles = resolver.firefoxProfiles()`;
`safariAccess = resolver.safariAccess()`; validates the stored Firefox profile —
if `source` is `.firefox(name)` and `name` is not in the live list, rewrite
`source` to `.firefox(profile: nil)`.

### 5.2 The rows

1. **Browser** — `SkinnedPicker<CookieSource>`, rows `None`, `Safari`, `Chrome`,
   `Brave`, `Microsoft Edge`, `Firefox`. Selecting Firefox yields
   `.firefox(profile: nil)`. Helper: *"Use your browser's YouTube sign-in for
   age-restricted or private videos."*

2. **Firefox profile** — shown only when `source` is `.firefox` **and**
   `firefoxProfiles.count >= 2`. `SkinnedPicker<String>` of profile names,
   preselecting the `isDefault` one. One profile → hidden (used implicitly).
   Zero → hidden; a `--dim` note *"No Firefox profiles found."*

3. **Full Disk Access** — shown only when `source == .safari`:
   - `.granted` → `.ok` dot + *"Full Disk Access granted."*, no button.
   - `.denied` → `--warn` dot + *"MediaGrabber needs Full Disk Access to read
     Safari's sign-in."* + an **"Open System Settings"** button.
   - `.noContainer` → hidden.

4. **Learn more** — shown when `source != .none`. A link row:
   *"Cookie access for \(browserName) — Learn more ↗"* → `openHelp()`.

5. **Tip** — shown when `source != .none`, a `--dim` block: *"For the most
   reliable results, use a browser profile that's signed in to YouTube and keep
   it closed while downloading."*

### 5.3 Deep links

- FDA: `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`,
  behind a `SettingsLinkOpening` protocol (mirrors `OpenURLSink`) so the pane
  test asserts the call without opening System Settings.
- Help: `CookieHelpURL.url(forBrowserKey:)` via the `OpenURLSink` added in
  Phase 4.

### 5.4 The 🔑-with-no-browser prompt

When `AppModel.pendingCookieRetryJobID` is set and the pane is shown, a banner
row at the top: *"Pick a browser to retry "\(jobTitle)" with your sign-in."* It
clears and triggers `AppModel.resolveCookieRetry()` the moment `source` moves off
`.none`. Navigating away without picking drops the pending id.

---

## 6. Engine, persistence, redaction

### 6.1 `YtDlpArguments`

```swift
public static func build(
    for request: DownloadRequest,
    options: GlobalDownloadOptions = .none,
    tuning: YtDlpTuning = .default,
    cookieArgument: String? = nil
) -> [String]
```

`baseArgv` gains, after the resilience flags and before the URL:
`if let cookieArgument { argv += ["--cookies-from-browser", cookieArgument] }`.
`redacted` takes the same parameter and substitutes
`["--cookies-from-browser", "<redacted>"]` when non-nil (a Firefox profile name
is user data). Both defaults keep every existing call site compiling.

### 6.2 `EngineDependencies`

Gains `fileManager: FileManaging` (default `FoundationFileManager()`).
`.live(...)` leaves the default. Every existing engine-test fixture keeps
compiling.

### 6.3 `DownloadDrainOutcome` + `recordExit`

`DownloadDrainOutcome` gains `var extractedZeroCookies = false`, set in
`drainDownload` when a drained line contains `Extracted 0 cookies`.

`recordExit` gains `cookiesRequested: Bool` (the launcher passes
`cookieArgument != nil`). Its classification step, for a non-zero exit:

```swift
let errorClass: ErrorClass =
    (cookiesRequested && outcome.extractedZeroCookies)
        ? .cookieReadFailed
        : classifyExit(result: result, lastError: lastError)
```

This runs before the `isAutoRetryable` check. `cookieReadFailed` is not
auto-retryable (Phase 4), so a job that lost its cookies goes straight to
`.failed(.cookieReadFailed)` — no backoff loop.

### 6.4 `retryWithCookies` intent

`DownloadEngine+Retry.swift`, parallel to `retry(_:)`:

```swift
public func retryWithCookies(_ id: UUID) async {
    guard let job = jobs.first(where: { $0.id == id }),
          case let .failed(errorClass) = job.state,
          errorClass.presentation.offeredActions.contains(.retryWithCookies)
    else { return }

    job.forceCookies = true
    job.attempt = 0
    job.state = .queued
    job.finishedAt = nil
    job.progress = nil
    job.sizeBytes = nil
    job.integrityVerdict = nil
    job.actualQuality = nil
    deletePartFiles(for: job)
    move(job, toTail: true)
    logEvent(.jobRetried(id: id))
    bump(); emitSnapshot(); evaluateSchedule()
}
```

Always from-scratch (never resume). `forceCookies` stays set for the life of the
job — a job that fails again and is retried keeps its cookies.

### 6.5 Persistence

`DownloadJob.forceCookies: Bool` (default `false`) →
`PersistedJob.forceCookies` round-trips like `attempt`. Schema version
unchanged: a new optional-with-default field is backward compatible — an old
`queue.json` without the key decodes to `false`.

### 6.6 Redaction

`YtDlpArguments.redacted` (§6.1) masks the cookie spec. The engine logs the
redacted argv through the existing `processLaunched` event, so a profile name
never reaches a log. No `LogRedaction` change.

### 6.7 Preferences reset

`mg.cookiesFromBrowser` joins `Preferences.ownedKeys`; `resetToDefaults` clears
it to `.none`.

---

## 7. App wiring, `screens.html`, parent-spec edits

### 7.1 `AppModel`

- `handleRowAction(id, .retryWithCookies)` — the §2 branch.
- `pendingCookieRetryJobID: UUID?` (`private(set)`); `resolveCookieRetry()` —
  `guard let id = pendingCookieRetryJobID; pendingCookieRetryJobID = nil; await
  engine.retryWithCookies(id)`.
- `page` `didSet` clears an unconsumed `pendingCookieRetryJobID` when moving away
  from `.preferences(.cookies)`.
- `DownloadEngineProtocol` gains `func retryWithCookies(_:) async`; the
  `FakeEngine` conformers (App `AppFakes.swift`, `QuitCoordinatorTests`) get a
  recorder / stub.

### 7.2 `screens.html`

- **Screen 3.4 (Sign-in & cookies)** — replace the stepless placeholder with the
  four row types: the browser `SkinnedPicker` (Firefox selected), the
  Firefox-profile picker (two profiles, `default-release` selected), the
  "Learn more ↗" link row, the tip block. Add a second inset showing the
  **Safari state**: browser = Safari, the Full Disk Access `--warn` row with
  "Open System Settings".
- **Screen 1.2 (Home table)** — the existing `cookieReadFailed`-style failed row
  (currently "couldn't verify you") gets the real sentence
  *"Couldn't read your browser's sign-in."* and a `🔑` rendered **enabled**.
- **Screen 2.1 (Onboarding)** — no change.

### 7.3 Parent-spec edits (same pass)

- **§5 Preferences model** — collapse `cookiesFromBrowser: BrowserChoice` +
  `firefoxProfile: String?` into one `cookiesFromBrowser: CookieSource`
  (default `.none`). State that cookies are opt-in.
- **§7.2 "Cookies from browser"** — reword: opt-in, default `.none`. The
  "always on, default `.safari`" and the silent-fallback-then-`cookieReadFailed`
  model become a note attached to a future always-on-cookies phase. Phase 5
  fires `cookieReadFailed` on a direct user-requested cookie read that failed.
- **§7.3 Cookie edge cases** — keep; add that Safari FDA detection is a
  probe-read (just-in-time, no onboarding step) and Chrome app-bound encryption
  is detected from `Extracted 0 cookies` plus a downstream failure.
- **§12.1 Phase 5 stub** — rewrite to the shipped surface: `CookieSource` +
  `CookieResolver` (`profiles.ini` parse, Safari FDA probe-read), opt-in default
  `.none`, the filled Sign-in & cookies pane, `cookieReadFailed` classifier +
  `retryWithCookies` on `cookieReadFailed` / `ageRestricted` / `private`,
  `engine.retryWithCookies` (`job.forceCookies` persisted), `CookieHelpURL`.
  Note: **no FDA onboarding step**.
- **§12.1 Onboarding step list row** — strike "Phase 5 — a Full-Disk-Access
  case"; onboarding stays 4 steps.
- **§12.2 rows** — `Downloads-table row-action bar`: `retryWithCookies` now lives
  (Phase 5), the engine adds it to the set for `cookieReadFailed` /
  `ageRestricted` / `private`. `ErrorClass emit paths`: Phase 5 wires
  `cookieReadFailed`. `PreferencesView panes`: Phase 5 fills the whole Sign-in &
  cookies pane (not just the Firefox picker).
- **§13 "later"** — no change.

---

## 8. Testing (TDD — test before implementation for every unit)

**`GrabberKitTests`:**

- **`CookieSource`** — `ytDlpSpec` per case; `.firefox` with and without a
  profile → `"firefox:name"` / `"firefox"`; `browserKey` per case; `Codable`
  round-trip through JSON including `.firefox("x")`; a malformed JSON blob
  decodes to `.none` (tested via `Preferences`).
- **`CookieResolver.firefoxProfiles`** — a fixture `profiles.ini` with 0 / 1 /
  2 profiles; `IsRelative=1` (path joined under `Profiles/`) vs `IsRelative=0`
  (absolute path used verbatim); the `Default=` marker on a top-level key and on
  an `[Install…]` section; a malformed section skipped; an absent file → `[]`.
- **`CookieResolver.safariAccess`** — fake FS: no container file → `.noContainer`;
  present + readable → `.granted`; present + not readable → `.denied`.
- **`CookieResolver.resolve`** — every `(source, jobOverride)` row of the §2
  table; `.none + override` substitution picks Safari when accessible, else the
  first existing browser dir, else `nil`; `.safari` denied → `argument: nil`,
  `verdict: .needsFullDiskAccess`; `.firefox("gone")` with that name absent →
  the default profile; `.firefox(nil)` with no profiles → `argument: nil`,
  `.noProfiles`.
- **`YtDlpArguments`** — `cookieArgument: "safari"` emits
  `["--cookies-from-browser", "safari"]` before the URL; `nil` omits both
  tokens; `redacted` emits `["--cookies-from-browser", "<redacted>"]`; the
  existing argv fixtures updated for the new (absent-by-default) tokens.
- **`ErrorSignatures` / `classifyStderr`** — each `cookieReadFailed` fragment
  pair classifies; a `cookieReadFailed` line on a `Private video` line
  classifies `cookieReadFailed` (ordered first); the Phase 4 signatures
  unaffected.
- **`FailurePresentation`** — `.cookieReadFailed` offers
  `{ .retry, .retryWithCookies }`; `.ageRestricted` and `.private` offer
  `{ .retryWithCookies }`; `geoBlocked` / `unavailable` / `depMissing` offer
  nothing; every case still has a non-empty sentence.
- **`availableActions`** — `.failed(.cookieReadFailed)` includes
  `retryWithCookies`, `retry`, `showLog`, `remove`, `openInBrowser`;
  `.failed(.private)` includes `retryWithCookies` but not `retry`;
  `.failed(.geoBlocked)` includes neither.
- **`DownloadEngine` — the 0-cookies override** (`FakeProcessRunner`): a spawn
  with a cookie argument, an `Extracted 0 cookies` line, then a non-zero exit →
  `.failed(.cookieReadFailed)`, not deferred, `attempt == 0`; the same run
  **without** a cookie argument → the normally-classified class; an
  `Extracted 0 cookies` line on an exit-0 run → `.completed` (the warning is
  benign).
- **`engine.retryWithCookies`** — a `.failed(.cookieReadFailed)` job →
  `forceCookies == true`, `.queued` at the tail, `attempt == 0`, `.part`
  deleted, `jobRetried` logged; a `.failed(.geoBlocked)` job → a no-op; a
  non-`.failed` job → a no-op; the next spawn's argv carries
  `--cookies-from-browser` even though `preferences.cookiesFromBrowser == .none`
  (resolver substitution, via a fake `FileManaging` that reports Safari
  readable).
- **`CookieResolver` in the spawn path** — an engine with
  `preferences.cookiesFromBrowser == .safari` and a fake FS reporting `.granted`
  → the launched argv carries `["--cookies-from-browser", "safari"]`; with the
  FS reporting `.denied` → no cookie tokens in the argv (the download proceeds
  cookieless).
- **Persistence** — a job with `forceCookies == true` round-trips; an old
  `queue.json` (no `forceCookies` key) restores `forceCookies == false`.

**`AppUnitTests`:**

- **`AppModel.handleRowAction(.retryWithCookies)`** — `cookiesFromBrowser ==
  .none` → `pendingCookieRetryJobID` set and `page == .preferences(.cookies)`,
  `engine.retryWithCookies` not called; a browser set → `engine.retryWithCookies`
  called, no page change.
- **`AppModel.resolveCookieRetry`** — with a pending id → `engine.retryWithCookies`
  called with it, the id cleared; with no pending id → a no-op.
- **`AppModel` page-change clears the pending id** — set the pending id, move
  `page` to `.home` → the id is nil, no retry fired.
- **`CookiePaneModel.refresh`** — a fake resolver reporting two profiles →
  `firefoxProfiles.count == 2`; `source == .firefox("stale")` with `"stale"`
  absent from the list → `source` rewritten to `.firefox(profile: nil)`;
  `safariAccess` reflects the fake.
- **`CookiePaneModel` sinks** — `openFullDiskAccessSettings()` calls the
  `SettingsLinkOpening` fake with the `x-apple.systempreferences:` URL;
  `openHelp()` calls the `OpenURLSink` fake with the `CookieHelpURL` for the
  current `browserKey`.
- **Pane row visibility** (pure — a small `cookiePaneRows(source:profiles:access:)`
  helper if the view logic is worth isolating, else assert on the model's
  `shouldShow…` computed flags): Firefox picker hidden at 0/1 profiles, shown at
  2+; FDA row shown only for `.safari` and only when `access != .noContainer`;
  "Learn more" + tip shown for any non-`.none` source.

**Not tested:** real `profiles.ini` on the test machine, real browser cookie
databases, a real System Settings open, real `NSWorkspace`, SwiftUI rendering.

**Manual smoke** (leaf checklist, added by the plan):

- With `cookiesFromBrowser == .none`, grab an age-restricted video → it fails
  `This video is age-restricted…`, the `🔑` button is enabled. Press `🔑` →
  Preferences opens on Sign-in & cookies with the "Pick a browser…" prompt.
  Pick Safari.
- Safari selected, no Full Disk Access → the pane shows the `--warn` FDA row;
  "Open System Settings" opens the Full Disk Access pane. Grant it, return →
  the row flips to `.ok`.
- With Safari + FDA, retry the age-restricted video (`🔑` or Retry) → it
  downloads.
- Select Firefox with 2+ profiles → the profile picker appears, the default
  profile preselected. Pick a signed-in profile, retry a private video you have
  access to → it downloads.
- Select Chrome (v127+) → grab a bot-checked video → it fails
  `Couldn't read your browser's sign-in.`; the pane's "Learn more" opens the
  yt-dlp FAQ.
- Quit mid-retry with `forceCookies` set → relaunch → the job is queued and
  still retries with cookies.

---

## 9. Definition of done

- Everything in §1 "in this phase" built to final-app form.
- `xcodebuild … test` green; `swiftformat --lint` + `swiftlint --strict` clean.
- The manual smoke checklist passes on a real machine.
- Parent spec §5, §7.2, §7.3, §12.1 (Phase 5 stub + onboarding step row), §12.2
  rows updated to reflect the shipped surface.
- `screens.html` screens 1.2 and 3.4 updated.

---

## 10. Parent-spec edits (same pass) — checklist

- §5 Preferences model — `cookiesFromBrowser: CookieSource` default `.none`,
  drop `firefoxProfile`, note opt-in.
- §7.2 — reword to opt-in; move always-on + silent-fallback to a future-phase
  note.
- §7.3 — FDA probe-read (JIT, no onboarding step); Chrome app-bound encryption
  via `Extracted 0 cookies` + downstream failure.
- §12.1 Phase 5 stub — shipped surface (see §7.3 of this spec).
- §12.1 Onboarding step list row — strike the Phase 5 FDA case; onboarding stays
  4 steps.
- §12.2 row-action bar row — `retryWithCookies` lives (Phase 5).
- §12.2 `ErrorClass` emit paths row — Phase 5 wires `cookieReadFailed`.
- §12.2 `PreferencesView` panes row — Phase 5 fills the whole Sign-in & cookies
  pane.
