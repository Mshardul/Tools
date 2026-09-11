# MediaGrabber Phase 9 — Add flows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clipboard, drag, Services, and `mediagrabber://open?url=` all land in the same Home field through one ingress controller (idle silent / busy confirm).

**Architecture:** `IncomingLinkController` (App) owns every external URL entry for the life of the app. `LinkExtractor` (GrabberKit) is a pure string→URL helper. AppModel exposes busy signals + apply-to-Home; the Home field text moves onto AppModel so ingress can set it. Share Extension is out of scope (sibling stub).

**Tech Stack:** Swift 6, Tuist, XCTest, AppKit Services / URL types. Targets: `GrabberKit`, `MediaGrabber`, `TestSupport`, `GrabberKitTests`, `AppUnitTests`.

**Spec:** `docs/superpowers/specs/archived/2026-09-10-media-grabber-phase-9.md` — read it alongside this plan. Every task's "why" is there; this plan is the "how".

## Global Constraints

- **No git.** This plan contains no `git` commands. Each task ends by running lint + tests and handing the changed files to the user. Do not create branches, do not commit, do not stage.
- **No phase / ticket / epic numbers anywhere in source or UI copy.** Not in comments, not in log strings, not in SwiftUI `Text`. The spec and this plan are the only places "Phase 9" appears.
- **Comments: single-line only, only the *why*, only when names don't carry it.** No `///`. No stacked `//` blocks. Default to zero comments. `// MARK:` is fine.
- **UI copy:** never "POT", "yt-dlp", or `player_client` in a user-visible string (existing onboarding exception unchanged). Dialog strings are verbatim from the spec.
- **Swift 6 concurrency:** `NSLock` banned in async. `LockedBox` is TestSupport-only. Actors reentrant across `await`. `XCTestCase` is not `Sendable`.
- **Lint after every task:** from `apps/media-grabber/`: `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict`.
- **Build after adding/removing files:** `mise exec -- tuist generate --no-open` from `apps/media-grabber/`.
- **Test command:** from `apps/media-grabber/`: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`. Single suite: `-only-testing:GrabberKitTests/<SuiteName>` or `-only-testing:AppUnitTests/<SuiteName>`. Do NOT use `tuist test` while developing. Workspace is gitignored — generate first if missing.
- **Do not use `XCTAssertTrue(await …)`** — bind to a `let`, then assert.
- **Test names carry no phase number.**
- All source paths below are relative to `apps/media-grabber/` unless they start with `docs/`.
- **Share Extension is out of scope.** Do not add an appex target.
- **No yt-dlp at extract/sniff time.** Probe remains the extractor truth.
- **Dialog copy is fixed by the spec** — do not invent softer wording.

## Lint traps (apply pre-emptively)

- `function_body_length` 50 / `cyclomatic_complexity` 10 — split extract / scheme parse / busy policy into helpers.
- `type_body_length` 250 — split test types rather than stuffing.
- `swiftformat` vs `opening_brace` on wrapped `if` — extract a named predicate.

## File Structure

**New — GrabberKit:**

| File | Responsibility |
|---|---|
| `Sources/GrabberKit/Link/LinkExtractor.swift` | Pure `LinkExtractor.extract(from: String) -> URL?` |

**New — App:**

| File | Responsibility |
|---|---|
| `Sources/App/Ingress/PasteboardReading.swift` | `PasteboardReading` + `PasteboardWriting` seams; live NSPasteboard adapters |
| `Sources/App/Ingress/IncomingLinkScheme.swift` | Parse `mediagrabber://open?url=` → `Result<URL, IncomingLinkSchemeError>` |
| `Sources/App/Ingress/IncomingLinkController.swift` | All ingress policy + clipboard observe |
| `Sources/App/Ingress/IncomingLinkHome.swift` | Protocol AppModel conforms to (busy + apply) |

**Modified:**

| File | Change |
|---|---|
| `Sources/App/AppModel.swift` | `homeFieldText`; `isHomeBusy`; `applyIncomingURL(_:)`; conform `IncomingLinkHome` |
| `Sources/App/AppModelDialogs.swift` | Busy offer + scheme-failure notice builders |
| `Sources/App/Home/HomeView.swift` | Bind field to `appModel.homeFieldText`; `onDrop` |
| `Sources/App/MediaGrabberApp.swift` | Construct controller; `onOpenURL`; activation hooks |
| `Sources/App/AppDelegate.swift` | Services provider + `open` URLs / Dock; wire controller |
| `Sources/App/MainWindow.swift` | Optional drop if not only on HomeView |
| `Project.swift` | `CFBundleURLTypes` + `NSServices` |
| Diagnostics / copy-report call sites | `markAppPasteboardWrite()` before writing clipboard |
| `docs/mockups/screens.html` | §4 dialogs (+ optional §1 drop caption) |

**Tests:**

| File | Responsibility |
|---|---|
| `Tests/GrabberKitTests/LinkExtractorTests.swift` | Extract cases |
| `Tests/AppUnitTests/IncomingLinkSchemeTests.swift` | Scheme parse |
| `Tests/AppUnitTests/IncomingLinkControllerTests.swift` | Idle/busy/clipboard/scheme policy with fakes |
| `Tests/TestSupport/FakePasteboard.swift` | Fake pasteboard for tests |

---

## Task 0: `LinkExtractor`

**Files:**
- Create: `Sources/GrabberKit/Link/LinkExtractor.swift`
- Test: `Tests/GrabberKitTests/LinkExtractorTests.swift`

**Interfaces:**
- Produces:

```swift
public enum LinkExtractor {
    public static func extract(from raw: String) -> URL?
}
```

Rules (spec §5): trim whitespace; strip one layer of wrapping `<>` if present; find the first `http://` or `https://` URL substring (stop at whitespace); return `nil` for bare `www.` / no scheme / empty. Multiple URLs → first only.

- [ ] **Step 1: Failing tests**

```swift
func testHTTPS() {
    XCTAssertEqual(
        LinkExtractor.extract(from: "  https://example.com/a  ")?.absoluteString,
        "https://example.com/a"
    )
}
func testAngleBrackets() {
    XCTAssertEqual(
        LinkExtractor.extract(from: "<https://youtu.be/x>")?.absoluteString,
        "https://youtu.be/x"
    )
}
func testFirstOfMany() {
    XCTAssertEqual(
        LinkExtractor.extract(from: "see https://a.example and https://b.example")?.absoluteString,
        "https://a.example"
    )
}
func testRejectsWWWWithoutScheme() {
    XCTAssertNil(LinkExtractor.extract(from: "www.youtube.com/watch?v=1"))
}
func testRejectsEmpty() {
    XCTAssertNil(LinkExtractor.extract(from: "   "))
}
```

- [ ] **Step 2: Run** — `xcodebuild … -only-testing:GrabberKitTests/LinkExtractorTests` → fail (type missing).
- [ ] **Step 3: Implement** with `Foundation`. Prefer `NSDataDetector` with `.link` **only if** it still rejects bare `www.` without scheme in your checks; otherwise a small scanner that requires `http://`/`https://` prefix. Do not call yt-dlp.
- [ ] **Step 4: Pass + lint.** `tuist generate --no-open` after adding files.
- [ ] **Step 5: Hand files to the user.**

---

## Task 1: Home field on `AppModel`

**Files:**
- Modify: `Sources/App/AppModel.swift`
- Modify: `Sources/App/Home/HomeView.swift`
- Modify: any AppUnitTests that construct Home-adjacent state if they assume local paste only
- Test: `Tests/AppUnitTests/AppModelHomeFieldTests.swift` (new, small)

**Why:** Ingress must set the Home field; `@State pastedURL` in `HomeView` cannot be the long-term owner.

**Interfaces:**
- Produces on `AppModel` (`@MainActor`):

```swift
var homeFieldText: String = ""
var isHomeBusy: Bool { /* non-empty homeFieldText || isProbing || isPlaylistPickerPresented */ }
func applyIncomingURL(_ url: URL) async
```

`applyIncomingURL` sets `homeFieldText = url.absoluteString` and `await resolvePasted(homeFieldText)`.

- [ ] **Step 1: Failing test** — `applyIncomingURL` sets text and triggers resolve path (use existing fake engine / helpers so probe is stubbed).
- [ ] **Step 2: Run → fail.**
- [ ] **Step 3:** Add `homeFieldText`. Replace HomeView `@State pastedURL` with `appModel.homeFieldText` (`@Bindable`). Update `onChange` / clear / grab paths that read/write the field. Keep debounce/probe behavior identical.
- [ ] **Step 4: `isHomeBusy`** as computed above (queue depth does **not** count).
- [ ] **Step 5: Pass focused AppUnitTests + lint.**
- [ ] **Step 6: Hand files to the user.**

---

## Task 2: Dialogs + `IncomingLinkHome` seam

**Files:**
- Create: `Sources/App/Ingress/IncomingLinkHome.swift`
- Modify: `Sources/App/AppModelDialogs.swift`
- Modify: `Sources/App/AppModel.swift` (conform)
- Test: extend `AppModelHomeFieldTests` or `IncomingLinkDialogsTests.swift`

**Interfaces:**
- Produces:

```swift
@MainActor
protocol IncomingLinkHome: AnyObject {
    var isHomeBusy: Bool { get }
    var detectClipboardLinks: Bool { get }
    func applyIncomingURL(_ url: URL) async
    func confirm(_ request: ConfirmationRequest) async -> Bool
}

enum AppModelDialogs {
    static func incomingLinkBusyConfirmation(url: URL) -> ConfirmationRequest
    static func incomingLinkSchemeFailureNotice() -> ConfirmationRequest
}
```

Busy confirm (spec §4): title `Grab this link?`, message `url.absoluteString`, confirm `Grab`, cancel `Not now`, `suppressionKey: nil`, `isDestructive: false`.

Scheme failure (spec §7): title `Couldn’t open that link`, message `The link was missing or not a web address.`, confirm `OK`, `cancelTitle: nil`.

`AppModel.detectClipboardLinks` reads `prefs.detectClipboardLinks`.

- [ ] **Step 1: Failing tests** asserting dialog field values exactly.
- [ ] **Step 2: Implement builders + protocol; AppModel conforms.**
- [ ] **Step 3: Pass + lint.**
- [ ] **Step 4: Hand files to the user.**

---

## Task 3: Scheme parser

**Files:**
- Create: `Sources/App/Ingress/IncomingLinkScheme.swift`
- Test: `Tests/AppUnitTests/IncomingLinkSchemeTests.swift`

**Interfaces:**
- Produces:

```swift
enum IncomingLinkSchemeError: Error, Equatable {
    case wrongScheme
    case missingURL
    case malformed
    case notWebURL
}

enum IncomingLinkScheme {
    static let scheme = "mediagrabber"
    static func openURL(from url: URL) -> Result<URL, IncomingLinkSchemeError>
}
```

Accept host/path form `mediagrabber://open?url=` (host `open` **or** path `/open` — pick one canonical and test it; recommend host empty + path `open` **or** host `open` with empty path — **lock in code to whatever `URL` produces for `mediagrabber://open?url=` on macOS and assert that round-trip in tests**). Percent-decode `url` query. Only `http`/`https`. Extra query keys ignored. Wrong scheme → `.wrongScheme`.

- [ ] **Step 1: Failing tests** for valid, missing, malformed percent-encoding, `ftp://`, wrong scheme.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Pass + lint.**
- [ ] **Step 4: Hand files to the user.**

---

## Task 4: `IncomingLinkController` core (idle / busy / scheme)

**Files:**
- Create: `Sources/App/Ingress/IncomingLinkController.swift`
- Test: `Tests/AppUnitTests/IncomingLinkControllerTests.swift`
- Test support: `Tests/TestSupport/FakePasteboard.swift` (minimal; clipboard wired Task 5)

**Interfaces:**
- Consumes: `IncomingLinkHome`, `LinkExtractor`, `IncomingLinkScheme`
- Produces:

```swift
@MainActor
final class IncomingLinkController {
    init(home: IncomingLinkHome, pasteboard: any PasteboardReading & PasteboardWriting = …)
    func handlePlainText(_ raw: String) async
    func handleOpenURL(_ url: URL) async
    func markAppPasteboardWrite()
    func setClipboardDetectionEnabled(_ enabled: Bool) async
    func applicationDidBecomeActive() async
}
```

`handlePlainText`: extract → nil return; else if `home.isHomeBusy` then confirm busy dialog → apply on true; else apply.  
`handleOpenURL`: parse scheme → failure notice on error; else same idle/busy as plain text with the web URL.  
Do not start clipboard observing in this task (Task 5).

- [ ] **Step 1: Failing tests** with a fake `IncomingLinkHome` recording apply/confirm calls:
  - idle → apply, no confirm
  - busy + Grab → confirm then apply
  - busy + Not now → confirm, no apply
  - scheme valid → apply
  - scheme bad → failure notice (`confirm` once, `cancelTitle == nil`), no apply
- [ ] **Step 2: Implement controller core.**
- [ ] **Step 3: Pass + lint.**
- [ ] **Step 4: Hand files to the user.**

---

## Task 5: Pasteboard seams + clipboard policy

**Files:**
- Create: `Sources/App/Ingress/PasteboardReading.swift` (protocols + `NSPasteboard` live types)
- Modify: `Sources/App/Ingress/IncomingLinkController.swift`
- Modify: `Tests/TestSupport/FakePasteboard.swift`
- Modify: `Tests/AppUnitTests/IncomingLinkControllerTests.swift`
- Modify: any Copy report / diagnostic clipboard write sites to call `markAppPasteboardWrite()` **immediately before** writing

**Interfaces:**
- Produces:

```swift
protocol PasteboardReading: Sendable {
    var changeCount: Int { get }
    func readString() -> String?
}
protocol PasteboardWriting: Sendable {
    func writeString(_ string: String)
}
```

Clipboard policy (spec §6):

- Observe only when `home.detectClipboardLinks` is true.
- On `applicationDidBecomeActive` and when changeCount advances while enabled, read string → `handlePlainText`.
- Dedupe: ignore if `changeCount` and extracted URL match the last handled pair.
- `markAppPasteboardWrite()` records current/next changeCount to ignore self-writes.
- `setClipboardDetectionEnabled(false)` stops observing and cancels in-flight busy offer if you track a Task — simplest correct approach: set a generation token so an in-flight confirm’s apply is skipped if disabled before apply (test this).

Polling vs `NSPasteboard` notifications: use a lightweight timer (e.g. 0.5–1.0 s) **while app is active and detection enabled**, comparing `changeCount` — simpler and testable with fakes. Document the interval as a named constant.

- [ ] **Step 1: Failing tests** — prefs off no handle; self-write ignored; duplicate changeCount ignored; disable mid-offer skips apply.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Wire `markAppPasteboardWrite` at existing clipboard write call sites (grep `NSPasteboard` / `stringForType` / `clearContents`).**
- [ ] **Step 4: Pass + lint.**
- [ ] **Step 5: Hand files to the user.**

---

## Task 6: Info.plist URL types + Services + AppDelegate

**Files:**
- Modify: `Project.swift` (`infoPlist`)
- Modify: `Sources/App/AppDelegate.swift`
- Modify: `Sources/App/MediaGrabberApp.swift`
- Test: keep unit coverage via controller; add a thin test that Services selector is exposed if you use `@objc` — optional. Manual smoke is user-owned.

**Plist (Tuist `infoPlist: .extendingDefault(with:)`):**

- `CFBundleURLTypes`: scheme `mediagrabber`, name `MediaGrabber`, role Editor.
- `NSServices`: one service — menu `Download with MediaGrabber`, send types public.utf8-plain-text + public.url (and legacy string if required), message selector matching AppDelegate method, `NSRequiredContext` empty / default.

**AppDelegate:**

- Hold `var incomingLinks: IncomingLinkController?`
- `applicationDidBecomeActive` → `Task { await incomingLinks?.applicationDidBecomeActive() }`
- `application(_:, open: [URL])` → for each URL, if scheme is `mediagrabber` then `handleOpenURL`; else if file URL with text, optional skip; for plain `http(s)` opened onto Dock, `handlePlainText(url.absoluteString)`
- `@objc` Services method reading pasteboard string/URL → `handlePlainText`
- Register `NSApp.servicesProvider` on launch

**MediaGrabberApp:**

- Construct `IncomingLinkController(home: appModel)` after model exists; assign to `appDelegate.incomingLinks`
- `.onOpenURL { url in Task { await controller.handleOpenURL(url) } }` on the root content

- [ ] **Step 1: Implement plist + delegate + app wiring.**
- [ ] **Step 2: `tuist generate`, build (`make` or xcodebuild build).**
- [ ] **Step 3: Lint.**
- [ ] **Step 4: Hand files to the user.**

---

## Task 7: Drag onto Home window

**Files:**
- Modify: `Sources/App/Home/HomeView.swift` (and/or `MainWindow.swift` if drops must cover the table chrome)

**Behavior:** `onDrop` of `UTType.url` and `UTType.plainText` → read providers → `handlePlainText` / URL absoluteString via controller (Environment or callback from MainWindow). Idle/busy handled inside controller.

- [ ] **Step 1: Implement drop.** Prefer attaching on the outermost Home/Main content so first-run and table layouts both accept drops.
- [ ] **Step 2: Build + lint.**
- [ ] **Step 3: Hand files to the user.** (Unit-test via controller already covers policy; drop is integration.)

---

## Task 8: Mockups + doc verify + full suite

**Files:**
- Modify: `docs/mockups/screens.html` (§4 busy offer + scheme failure notice; optional §1 drop caption)
- Verify: parent §12.1 Phase 9 stub still points here; design-system clipboard row; Share Extension stub untouched
- Do **not** archive until ship closeout after SDD final review

- [ ] **Step 1: Update mockups.**
- [ ] **Step 2: Lint + full `MediaGrabber-Workspace` test suite.** Fix Phase 9 failures. Pre-existing Phase 8 `MetadataProbePlaylistTests` cancel flakes: do not expand scope unless you touch that code; note in the report if still red.
- [ ] **Step 3: `make` from `apps/media-grabber/` — BUILD SUCCEEDED.
- [ ] **Step 4: Hand files to the user.**

---

## Self-review (plan vs spec)

| Spec | Task |
|---|---|
| Link extract §5 | 0 |
| Home apply / busy signals §3, §9 | 1–2 |
| Offer + scheme failure dialogs §4, §7 | 2 |
| Scheme parse §7 | 3 |
| Controller idle/busy §3, §9 | 4 |
| Clipboard §6 | 5 |
| Services + plist + openURL §7–8 | 6 |
| Drag §2 | 7 |
| Mockups / suite §11–13 | 8 |
| Share Extension out of scope | — (no task) |

**Spec imprecision fixed here:** `mediagrabber://open?url=` canonical `URL` shape is locked by round-trip tests in Task 3 (Foundation’s host vs path parsing).

**Long-term note:** Home field lift (Task 1) is required so ingress is not trapped in SwiftUI `@State` — matches end-state ownership, not a temporary workaround.
