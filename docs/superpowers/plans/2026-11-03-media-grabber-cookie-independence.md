# Cookie Independence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MediaGrabber never asks for a sign-in or browser cookies up front. Probes and downloads run cookie-less unless the user already chose a browser; a failure that a sign-in can fix says so in plain words; cookie values never reach a log.

**Architecture:** One pure policy in GrabberKit, `SignInPolicy`, decides from `(ErrorClass, host, cookiesConfigured)` whether a failure earns a sign-in suggestion, a "check your browser's sign-in" note, or nothing. Row actions, row sentences and probe messages all read that one policy. The per-job cookie override and the browser auto-detect are removed, so the cookie argument is a pure function of the Preferences browser choice. Log redaction gains a free-text pass for `Cookie` / `Set-Cookie` header values.

**Tech Stack:** Swift, SwiftUI, XCTest, yt-dlp.

**Spec:** `apps/media-grabber/docs/superpowers/specs/2026-11-03-cookie-independence.md`

## Global Constraints

- Build, test and lint only through make, from `apps/media-grabber`: `make test ONLY=GrabberKitTests/<Suite>` or `ONLY=AppUnitTests/<Suite>`, then `make lint`. Never raw `xcodebuild`. At most one MediaGrabber.app may exist on the machine. Run `mise exec -- tuist generate --no-open` after adding a file.
- No git commands anywhere. Create new files in place; never delete, move or overwrite a file that is not named in this plan.
- Comments are single-line only (`//`), lines at most 120 columns. No `///`. No phase, ticket or spec-section references in source or UI copy.
- User-facing copy is true for the real cause, plain language (no commands, no tool names, no "cookies" in row or dialog sentences), and states one action when a fix exists. Each cause-specific sentence has a test pinning cause to copy.
- Existing tests that pin exhaustive `ErrorClass` / `RowAction` / `MetadataError` lists are updated in the task that changes the case list.
- No task leaves a placeholder or no-op branch for a later task to fill in. The suite is green at the end of every task.
- Cookie values never appear in a log line, job log, diagnostic bundle, `queue.json` or `history.json`.

## Decisions

- **Configured browser is the standing consent.** With a browser chosen, every probe and download uses it. With none, both run cookie-less. There is no per-job override and no auto-detection of an installed browser.
- **Policy keyed on class and host.** Age-restricted and private failures earn a sign-in note on any host. A bot-check earns one only on YouTube. Every other class, including `formatsMissing`, `rateLimited`, `geoBlocked` and a bare 403 on another host, earns none.
- **Configured and still failing.** Cookies were already used, so no restart action is offered; the sentence tells the user to check that the chosen browser is signed in.
- **Unconfigured action.** The failed row offers "Restart with sign-in". It opens the Preferences browser picker and holds the job; choosing a browser restarts it; leaving the picker without a choice drops the hold. This is the existing pending-retry flow, now the only path to cookies for an unconfigured user.
- **Probe failures carry the note, not an action.** The Add flow shows the same suggestion sentence the row would.
- **`cookieReadFailed` is a configured-only failure.** It names the chosen browser, offers plain Restart, and never suggests a sign-in.
- **Row sentences stay free of the word "cookies".** Preferences keeps its own pane wording.

## Review Focus

- A fresh install with no browser chosen produces a probe and a download whose argv contains no `--cookies-from-browser`. Pinned in Task 1.
- No code path reads a browser the user did not choose. Pinned in Task 1 with a fake file manager that records reads.
- `formats_missing`, rate-limit, circuit-open and non-YouTube bot-check failures never mention signing in and never offer "Restart with sign-in". Pinned in Tasks 3 and 4.
- A configured user never sees "Restart with sign-in"; they see the check-your-browser sentence. Pinned in Task 4.
- Picking a browser after "Restart with sign-in" restarts the held job once; backing out restarts nothing. Pinned in Task 4.
- A private or age-restricted link pasted into Add shows a sign-in sentence, not "This video isn't available" or raw tool text. Pinned in Task 5.
- `Cookie:` and `Set-Cookie:` header values are redacted in job logs, the app log and the diagnostic bundle. Pinned in Task 7.

---

## Task 1: Cookie argument comes only from the chosen browser

**Files:**

- Modify: `Sources/GrabberKit/Cookies/CookieResolver.swift`, `Sources/GrabberKit/Download/DownloadEngine+Preview.swift`, `Sources/GrabberKit/Download/DownloadEngine+Launch.swift`, `Sources/App/Preferences/CookiePaneModel.swift`
- Modify tests: `Tests/GrabberKitTests/CookieResolverResolveTests.swift`, `CookieResolverBrowserMatrixTests.swift`, `CookieResolverSafariTests.swift`, `CookieResolverFirefoxTests.swift`, `EngineCookieTests.swift`, `YtDlpArgumentsContextTests.swift`, `Tests/AppUnitTests/CookiePaneModelTests.swift`

- [ ] **Step 1: Failing tests.** In `CookieResolverResolveTests` replace the four `jobOverride: true` tests with two: `.none` resolves to `argument == nil` and `.unconfigured` with a fake file manager that has Safari access, Chrome and Firefox directories present; and the same fake records zero reads of any browser path (`reads.isEmpty`). Add to `EngineCookieTests`: with `preferences.cookiesFromBrowser == .none`, the argv built for a submitted job and the argv of a probe contain no `--cookies-from-browser`.
- [ ] **Step 2: Run** `make test ONLY=GrabberKitTests/CookieResolverResolveTests`. Expect a compile failure (the new call shape) or failures on the substituted cases.
- [ ] **Step 3: Implement.** Change the signature to `resolve(source: CookieSource) -> CookieResolution`. Delete `noneResolution(jobOverride:)` and `substitutedResolution()`; `.none` returns `CookieResolution(argument: nil, verdict: .unconfigured)`. Update the two engine call sites (`makeContext`, `resolveCookieArgument`) and the two `CookiePaneModel` call sites. Update every test call site listed above to the new signature. Remove the `forceCookies` argument from `makeContext` callers only in Task 2; keep `makeContext(url:attempt:forceCookies:)` compiling by ignoring nothing: pass the flag through unchanged here.
- [ ] **Step 4: Run** the resolver suites, `EngineCookieTests`, `CookiePaneModelTests`, then `make lint`. All green.

## Task 2: Remove the per-job cookie override

**Files:**

- Modify: `Sources/GrabberKit/Download/DownloadJob.swift`, `Sources/GrabberKit/Model/PersistedJob.swift`, `DownloadEngine+State.swift`, `DownloadEngine+Launch.swift`, `DownloadEngine+Preview.swift`, `DownloadEngine+Retry.swift`
- Modify tests: `Tests/GrabberKitTests/PersistenceCookieTests.swift`, `EngineRetryWithCookiesTests.swift`, `QuitCoordinatorTests.swift`, `Tests/AppUnitTests/Support/AppFakes.swift`, `Tests/AppUnitTests/DownloadsTableTests.swift`, `BatchEligibilityTests.swift`

- [ ] **Step 1: Failing tests.** In `PersistenceCookieTests`: a `queue.json` written with an extra `"forceCookies": true` key decodes without error, and a re-encoded job contains no `forceCookies` key. In `EngineRetryWithCookiesTests`: restarting a failed age-restricted job via `retryWithCookies` re-queues it with `attempt == 0` and the job has no cookie-state property (the test reads the argv instead: it carries the chosen browser's argument when one is configured and none otherwise).
- [ ] **Step 2: Run** the two suites; expect failures.
- [ ] **Step 3: Implement.** Delete the `forceCookies` stored property and init argument from `DownloadJob`, the field, coding key and `decodeIfPresent` from `PersistedJob`, and the two copies in `DownloadEngine+State.swift`. `makeContext(url:attempt:)` and `launchProbe` drop the parameter. `retryWithCookies` stays as the engine's "restart after sign-in" verb: same body minus `job.forceCookies = true`. Update the listed tests and fakes.
- [ ] **Step 4: Run** `make test ONLY=GrabberKitTests/PersistenceCookieTests`, `.../EngineRetryWithCookiesTests`, `.../QuitCoordinatorTests`, `AppUnitTests/DownloadsTableTests`, `AppUnitTests/BatchEligibilityTests`, then `make lint`.

## Task 3: SignInPolicy

**Files:**

- Create: `Sources/GrabberKit/Cookies/SignInPolicy.swift`, `Tests/GrabberKitTests/SignInPolicyTests.swift`

- [ ] **Step 1: Failing test** `SignInPolicyTests`, a table over `(ErrorClass, canonicalHost, cookiesConfigured)`:
  - `.ageRestricted` and `.private` on `youtube` and on `vimeo`: `.suggest` when unconfigured, `.checkBrowser` when configured.
  - `.botCheck` on `youtube`: `.suggest` / `.checkBrowser`; on `vimeo`: `.none` both ways.
  - `.formatsMissing`, `.rateLimited()`, `.geoBlocked`, `.unavailable`, `.networkDown`, `.diskFull`, `.permissionDenied`, `.incomplete`, `.depMissing`, `.sabrGated`, `.potProviderDown`, `.cookieReadFailed`, `.unknown(raw: "x")`: `.none` on every host, both configured states.
  - A loop over every `ErrorClass` case fails the test if a new case is not listed, so a future case must be classified.
- [ ] **Step 2: Run** `make test ONLY=GrabberKitTests/SignInPolicyTests`; expect a compile failure.
- [ ] **Step 3: Implement.**

```swift
import Foundation

public enum SignInAdvice: Sendable, Equatable {
    case none
    case suggest
    case checkBrowser
}

public enum SignInPolicy {
    public static func fixableBySignIn(_ errorClass: ErrorClass, host: RateHost) -> Bool {
        switch errorClass {
        case .ageRestricted, .private: true
        case .botCheck: host.canonical == "youtube"
        default: false
        }
    }

    public static func advice(for errorClass: ErrorClass, host: RateHost, cookiesConfigured: Bool) -> SignInAdvice {
        guard fixableBySignIn(errorClass, host: host) else { return .none }
        return cookiesConfigured ? .checkBrowser : .suggest
    }
}
```

- [ ] **Step 4: Run** the suite, then `make lint`.

## Task 4: Row actions and sentences follow the policy

**Files:**

- Modify: `Sources/GrabberKit/Download/FailurePresentation.swift`, `DownloadEngine+Helpers.swift`, `DownloadEngine+State.swift`, `DownloadEngine+Retry.swift`, `Sources/App/Rows/RowStatusText.swift`, `Sources/App/Rows/BotCheckCopy.swift`, `Sources/App/Theme/Icon.swift`, `Sources/App/AppModelRowActions.swift`, `Sources/App/AppModel.swift`, `Sources/App/Chrome/BannerResolver.swift`
- Create: `Sources/GrabberKit/Cookies/SignInCopy.swift`
- Modify tests: `FailurePresentationTests`, `AvailableActionsTests`, `YouTubeErrorClassificationTests`, `EngineRetryWithCookiesTests`, `Tests/AppUnitTests/RowStatusTextTests.swift`, `BotCheckCopyTests.swift`, `AppModelCookieRetryTests.swift`

- [ ] **Step 1: Failing tests.**
  - `FailurePresentationTests`: no `ErrorClass` offers `.retryWithCookies` from class alone; `cookie_read_failed` offers `.retry`; `bot_check` keeps `.retry`; the `bot_check` sentence no longer contains "cookies".
  - `AvailableActionsTests` (new engine-level cases, built with a failed job on a given URL and a given `cookiesFromBrowser`): age-restricted unconfigured offers `.retryWithCookies`; age-restricted configured does not; YouTube bot-check unconfigured offers it; non-YouTube bot-check does not; `formatsMissing` and `rateLimited` never do.
  - `RowStatusTextTests`: pin the exact sentences below for each cause and configured state.
  - `AppModelCookieRetryTests`: with no browser chosen, the action sets the pending retry and opens the cookies pane; choosing a browser restarts the job once; leaving the pane without a choice clears the hold and restarts nothing.
- [ ] **Step 2: Run** these suites; expect failures.
- [ ] **Step 3: Implement.**
  - `FailurePresentation`: `cookieRetryKeys` and its `insert` are removed; `bot_check` sentence becomes `"Couldn't verify this request. Try again in a moment."`; `cookie_read_failed` stays `"Couldn't read your browser's sign-in."`.
  - `DownloadEngine.availableActions` gains `cookiesConfigured: Bool` and `host: RateHost` parameters; for `.failed(errorClass)` it unions `.retryWithCookies` when `advice == .suggest`. `buildSnapshot` passes `preferences.cookiesFromBrowser.isNone == false` and `RateHost(urlString: job.request.url)`.
  - `retryWithCookies` in `DownloadEngine+Retry.swift` guards on `SignInPolicy.fixableBySignIn(errorClass, host:)` instead of the presentation set, because the browser is configured by the time it runs.
  - `SignInCopy.sentence(for:advice:) -> String?` returns, for `.suggest`: age-restricted `"This video is age-restricted. Signing in with your browser may let you download it."`; private `"This video is private. If you have access, signing in with your browser may let you download it."`. For `.checkBrowser`: age-restricted `"This video is age-restricted. Make sure your browser is signed in to an account that can watch it."`; private `"This video is private. Make sure your browser is signed in to an account that has access."`. `.none` returns nil.
  - `RowStatusText.sentence` takes `cookiesConfigured`, asks `SignInPolicy.advice` with `snapshot.rateHost`, and returns `SignInCopy` when non-nil; the bot-check branch goes through `BotCheckCopy`.
  - `BotCheckCopy.sentence` takes `advice`. YouTube: shield `.down` / `.missing` sentences unchanged; otherwise `.suggest` is `"YouTube didn't accept this request. Try again, or sign in with your browser in Preferences."`, `.checkBrowser` is `"YouTube didn't accept this request. Try again, or check that your browser is signed in to YouTube."`, with the VPN variant `"... Try turning off your VPN, or ..."` kept. Non-YouTube (`.none`): `"This site didn't accept this request. Try again later, or turn off your VPN."` with no sign-in mention.
  - `Icon.swift`: the accessibility label and tooltip for `.retryWithCookies` read `"Restart with sign-in"`.
  - `BannerResolver` circuit-open text: `"\(subject) keep getting rate-limited. Wait a while, or turn off a VPN."`.
  - `AppModelRowActions.retryWithCookies`: unchanged shape (unconfigured sets the pending retry and opens the cookies pane); the configured branch is unreachable because the action is not offered, so it is deleted. `AppModel.resolveCookieRetry` is unchanged.
- [ ] **Step 4: Run** every suite named above, then `make lint`.

## Task 5: Probe failures name the real cause

**Files:**

- Modify: `Sources/GrabberKit/Download/MetadataProbe.swift`, `DownloadEngine+Helpers.swift`, `Sources/App/AppModelDialogs.swift`, `Sources/App/AppModelPlaylist.swift`, `Sources/App/AppModel.swift` (the single-link probe failure path)
- Modify tests: `MetadataProbeTests.swift`, `ErrorSignaturesTests.swift`, `Tests/AppUnitTests/BotCheckCopyTests.swift`, add cases to `Tests/AppUnitTests/AppModelDialogsTests.swift` (create if absent)

- [ ] **Step 1: Failing tests.** `MetadataProbeTests`: stderr containing `"Sign in to confirm your age"` classifies as `.ageRestricted`; stderr containing `"Private video"` classifies as `.private`; `"Video unavailable"` stays `.unavailable`; geo text stays `.unavailable`. `AppModelDialogsTests`: `probeErrorMessage(for: .ageRestricted, ...)` and `.private` return the `SignInCopy` sentence for the given advice and never contain raw tool text; a bot-check on a non-YouTube host contains no sign-in mention.
- [ ] **Step 2: Run** the suites; expect compile failures (new cases).
- [ ] **Step 3: Implement.** Add `MetadataError.ageRestricted` and `.private`. In `classify(stderr:exitCode:)`, match the age and private signatures from `ErrorSignatures` before the shared unavailable list; remove `.private` from `sharedUnavailableSignatures`. `errorClass(for:)` maps them to `.ageRestricted` / `.private`. `probeErrorMessage` takes `advice: SignInAdvice` and, for the two new cases, returns `SignInCopy.sentence(...)`; for `.botCheck` it forwards `advice` to `BotCheckCopy`. `showProbeFailure` computes the advice from `SignInPolicy.advice(for: AppModelDialogs.errorClass(...), host: RateHost(urlString: url), cookiesConfigured: !prefs.cookiesFromBrowser.isNone)` and passes it. The `cookieReadFailed` probe message becomes `"Couldn't read your browser's sign-in. Close the browser and try again."`.
- [ ] **Step 4: Run** the suites, then `make lint`.

## Task 6: Preferences wording is site-neutral

**Files:**

- Modify: `Sources/App/Preferences/PreferencesPane.swift`, `Sources/App/Preferences/Panes/SignInCookiesPane.swift`, `Sources/App/Preferences/CookiePaneModel.swift`
- Modify tests: `Tests/AppUnitTests/PreferencesPaneTests.swift`, `CookiePaneModelTests.swift`, `CookiePaneSignInTests.swift`

- [ ] **Step 1: Failing tests.** Pin the pane subtitle to `"Sign in to reach private or age-restricted videos on sites that need it."`, the browser row helper to `"Use your browser's sign-in for videos that need an account."`, the tip to `"For the most reliable results, use a browser profile that's signed in to the site and keep it closed while downloading."`, and the pass message to `"MediaGrabber can read your \(name) sign-in."` (unchanged). Pin that no pane string contains "YouTube".
- [ ] **Step 2: Run** the three suites; expect failures.
- [ ] **Step 3: Implement** the string changes in the three files.
- [ ] **Step 4: Run** the suites, then `make lint`.

## Task 7: Cookie header values are redacted in every log

**Files:**

- Modify: `Sources/GrabberKit/Logging/LogEvent.swift` (`LogRedaction`)
- Modify tests: `Tests/GrabberKitTests/LogRedactionTests.swift` (add to the existing suite for `LogRedaction`; create it if the suite lives under another name)

- [ ] **Step 1: Failing tests.** `LogRedaction.redact("Cookie: SID=abc; HSID=def")` returns `"Cookie: <redacted>"`; `"Set-Cookie: a=b; Path=/"` returns `"Set-Cookie: <redacted>"`; a line `"[debug] Cookie: x=y"` keeps its prefix; a case-insensitive `"cookie: x=y"` is redacted; `"Extracted 12 cookies from chrome"` is unchanged; a job-log line passing through `JobLog.append` containing a `Cookie:` header is written redacted (use a temp dir).
- [ ] **Step 2: Run** the suite; expect failures.
- [ ] **Step 3: Implement.** In `LogRedaction.redact(_ value:)` add a third stage that replaces everything after `Cookie:` or `Set-Cookie:` (case-insensitive, to end of line) with `<redacted>`, applied per line so multi-line input is handled.
- [ ] **Step 4: Run** the suite plus `GrabberKitTests/DiagnosticBundleTests`, then `make lint`.

## Task 8: Docs match the behaviour

**Files:**

- Modify: `docs/state-flow.md`, `docs/job-status-and-actions.md`, `docs/architecture.md`, `PRIVACY.md`, `CLAUDE.md`, `roadmap.md` (mark the cookie-independence phase shipped)

- [ ] **Step 1:** Update each doc's cookie text to the standing behaviour in the spec: no per-job override, no auto-detect, advice by class and host, "Restart with sign-in" only when unconfigured. `PRIVACY.md` states that cookies are read only from the browser the user chooses, are never stored or logged, and are sent only by the download tool to the site being downloaded from. In `CLAUDE.md` set the next phase to the site and identity phase.
- [ ] **Step 2:** Run `make test` (full suite, must be green) and `make lint`.

## Self-Review

- Spec §1–§2 (no up-front ask, two states): Tasks 1–2.
- Spec §3 (failure table): Task 3 table test.
- Spec §4.1–§4.3 (row, probe, shared copy): Tasks 4–5.
- Spec §4.4 (Preferences): Task 6.
- Spec §5 (privacy invariants): Tasks 1, 2, 7 and the PRIVACY.md text in Task 8.
