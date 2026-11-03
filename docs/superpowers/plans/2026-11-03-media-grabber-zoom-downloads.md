# Zoom Recording Downloads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paste a Zoom recording or Zoom Clips link into MediaGrabber and download it, asking for the recording's passcode when it has one.

**Architecture:** yt-dlp ships `zoom` and `zoom:clips` extractors, but the stock `zoom` extractor cannot get past Zoom's current passcode page. A small yt-dlp plugin bundled in GrabberKit overrides `zoom`: it completes the passcode step, raises one distinct plain-language error per failure, and enforces its own minimum gap between requests to Zoom. The app loads the plugin on every probe and download. A passcode is held in engine memory, keyed by URL, passed to yt-dlp as `--video-password`, and discarded as soon as its job ends; nothing is written to disk. One prompt sheet collects it, reached from a failed probe in the Add flow and from a failed row's "Enter passcode" action.

**Tech Stack:** Swift, SwiftUI, XCTest, yt-dlp, a Python yt-dlp plugin with `unittest` tests.

**Spec:** none. The design is the Architecture paragraph above plus the Decisions section below.

## Global Constraints

- Build, test and lint only through make: `make test ONLY=GrabberKitTests/<Suite>` or `ONLY=AppUnitTests/<Suite>`, then `make lint`. Never raw `xcodebuild`. At most one MediaGrabber.app may exist on the machine.
- No git commands anywhere. Create new files in place; never delete, move or overwrite a file that is not named in this plan.
- Comments are single-line only (`//`), lines at most 120 columns. No phase, ticket or spec-section references in source or UI copy.
- User-facing copy must be true for the real cause, plain language (no commands, no tool names, no flags), and state the action when one exists.
- Existing tests that pin exhaustive `ErrorClass` / `RowAction` / `MetadataError` lists must be updated in the task that adds the case.
- The passcode must never appear in a log line, a job log, a diagnostic bundle, or `queue.json` / `history.json`.
- No task leaves a placeholder or no-op branch for a later task to fill in.
- Zoom must never block us. No two requests to Zoom are ever made within 3 seconds of each other; the plugin enforces a 5 second gap itself, across processes. Every manual check against Zoom (captures, real-link runs) is paced the same way, runs with `--retries 0 --extractor-retries 0`, is logged with timestamps, and never tries to provoke a lockout or captcha.
- Python in the plugin and its tests follows the same comment rule: single-line `#` comments, at most 120 columns.

## Decisions

- **Session-only passcode, discarded when the job ends.** The engine keeps `[url: passcode]` in memory and drops the entry the moment the job reaches a final state (completed, failed or cancelled) or is removed. Internal automatic retries keep it, because the job has not ended. Restarting a finished job, or relaunching with a protected download still queued, asks for the passcode again through the row's "Enter passcode" action. Nothing is stored on disk.
- **Per-URL key.** The exact request URL string. No change to `DownloadRequest` or `PersistedJob`.
- **Passcode on argv.** yt-dlp only accepts `--video-password`. Passed as the single token `--video-password=<value>` so a passcode starting with `-` is not parsed as a flag. Visible to `ps` while the process runs; every logged argv masks it. This matches how proxy credentials are already passed.
- **Visible passcode field.** Recording passcodes are shared in invite emails and are mistyped more often than they are guarded, so the field is a plain text field.
- **One sheet, two entry points.** A failed probe opens it automatically; a failed row opens it from the row action. Both end in the same `submitPasscode`.
- **Classification reads `ERROR:` lines only.** Info lines go to stdout (download) or are suppressed (probe), and warnings are off, so stderr is the error line. The plugin owns the wording of every Zoom failure, so each signature is a string the plugin's tests pin, and the fixtures are real transcripts of the plugin run.
- **Plugin, not a yt-dlp upgrade.** Zoom's current flow (CSRF token, `need-password` share info, component page, `validate-context`, `validate-meeting-passwd`) is not handled by the installed yt-dlp. The plugin overrides `ZoomIE` for share links only and hands every other URL, and the play-page and format parts, to the stock code, so a fixed upstream extractor later can replace it by deleting one directory.
- **Bundled in GrabberKit, loaded from the bundle.** No copy to Application Support. `makeContext` appends the bundled plugin directory to `pluginDirs` for every context; the override applies only to Zoom share URLs.
- **Pacing lives in the plugin, shared across processes.** A probe and a download are separate yt-dlp processes, and several jobs can run at once, so a per-process delay is not enough. Before every extractor request the plugin takes an exclusive lock on one state file in the temp directory, sleeps until 5 seconds after the last recorded Zoom request, records the new time, and releases. Both `zoom` and `zoom:clips` go through it.
- **Failure wording reuses existing classes.** The plugin's sentences are chosen so the existing signatures classify them: dead link contains "no longer available" (`.unavailable`), sign-in-only contains "Private video" (`.private`, which already offers cookies), captcha or lockout contains "confirm you're not a bot" (`.botCheck`), and the two passcode classes are new. A Zoom format change surfaces as an unclassified error whose sentence tells the user the app needs an update.
- **One passcode attempt per user submission.** The plugin makes exactly one `validate-meeting-passwd` request per run and never retries a rejection; a lockout from repeated guesses is the one failure we cannot undo.

## Review Focus

- A passcode that starts with `-` (for example `-abc`) reaches yt-dlp as a value, not a flag. Pinned in Task 2.
- A wrong passcode reopens the prompt saying it didn't work, and a second wrong attempt does the same, with no stuck "probing" state. Pinned in Task 3.
- Neither the logged argv nor the job log contains the passcode, including when it contains spaces. Pinned in Task 2.
- An empty or whitespace-only passcode cannot be submitted; a pasted passcode with a trailing newline is trimmed. Pinned in Task 3.
- An expired or deleted Zoom recording does not show "That passcode didn't work", even when a passcode was sent. Pinned in Task 1 with the transcript from Task 0.
- After a job fails for any reason, restarting it does not reuse the old passcode. Pinned in Task 2.
- Two Zoom requests are never closer than 3 seconds, even across two processes started back to back. Pinned in Task 0.
- A wrong passcode is never retried automatically: `.passcodeRejected` is not auto-retryable (Task 1) and the plugin sends one attempt per run (Task 0).
- Every non-Zoom URL behaves exactly as before with the plugin directory loaded. Pinned in Task 0 (delegation test, `ExtractorContextTests`).
- A wrong passcode sent to the plugin results in exactly one `validate-meeting-passwd` request. Pinned in Task 0.

---

### Task 0: Zoom plugin, bundling and transcripts

The plugin makes yt-dlp's `zoom` extractor work with Zoom's current passcode flow. The flow below was verified live: a protected recording downloaded completely (684,347,272 bytes, 9741.56 s, clean decode).

**The verified flow** (every request is paced; `base` is the link's scheme and host):

1. GET the share link; the page's `window.__data__` holds `meetingId`.
2. GET `base/nws/recording/1.0/play/share-info/<meetingId>?originDomain=<host>&accessLevel=meeting` with `X-Requested-With: XMLHttpRequest`. A protected recording answers `componentName: need-password` and a bare-path `redirectUrl` plus separate query fields.
3. GET the component page: `redirectUrl` joined to `base`, with the share-info string fields and `originRequestUrl=<share link>` as the query. Its `window.__data__` has `meeting_id`, `fileId`, `action`, `useWhichPasswd`, `sharelevel`, `needRecaptcha`.
4. POST `base/csrf_js?t_x_zm_rid=1` with header `FETCH-CSRF-TOKEN: 1`; the body is `ZOOM-CSRFTOKEN:<token>`.
5. POST `base/nws/recording/1.0/validate-context` (form: `meetingId`, `fileId`, `useWhichPasswd`, `sharelevel`, `iet`) with headers `zoom-csrftoken`, `X-Requested-With`, `Referer`.
6. POST `base/nws/recording/1.0/validate-meeting-passwd` (form: `id` = `meeting_id`, `passwd`, `action`, `recaptcha` empty), same headers. `status: true` means accepted.
7. GET share-info again; the new `redirectUrl` is the play path. Hand that URL to the stock `ZoomIE`, which fetches the play page and `play/info` and returns the signed `ssrweb.zoom.us` mp4.

**Files:**

- Create: `Resources/YtDlpPlugins/zoomfix/yt_dlp_plugins/extractor/zoom_share_passcode.py`
- Create: `Tests/PluginTests/test_zoom_share_passcode.py`, `Tests/PluginTests/requirements.txt` (pins the `yt-dlp` version the tests run against)
- Create: `Tests/GrabberKitTests/Fixtures/zoom-stderr-passcode-rejected.txt`, `zoom-stderr-unavailable.txt`
- Modify: `Makefile` (a `plugin-test` target that runs the plugin tests with the repo's `.venv` Python after installing `requirements.txt`; `test` runs it first), `Project.swift` (GrabberKit gets `resources: ["Resources/YtDlpPlugins/**"]`), `Sources/GrabberKit/Download/DownloadEngine+Preview.swift` (`makeContext`)
- Test: `Tests/GrabberKitTests/ExtractorContextTests.swift`

- [ ] **Step 1: Write the plugin**

Start from the verified code below. Then add the two pieces it lacks: pacing (all requests, both extractors) and the failure sentences in the table that follows.

```python
from yt_dlp.extractor.zoom import ZoomIE as BaseZoomIE
from yt_dlp.networking import Request
from yt_dlp.utils import ExtractorError, js_to_json, update_url_query, urlencode_postdata, urljoin


def _first_object_after(html, marker):
    start = html.find(marker)
    start = html.find("{", start) if start >= 0 else -1
    if start < 0:
        return None
    depth, in_string, escaped, quote = 0, False, False, ""
    for index in range(start, len(html)):
        char = html[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                in_string = False
        elif char in "\"'":
            in_string, quote = True, char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return html[start : index + 1]
    return None


# Stock yt-dlp's zoom extractor can't pass Zoom's current passcode page, so share links are handled here.
class ZoomIE(BaseZoomIE):
    def _component_data(self, webpage, video_id):
        text = _first_object_after(webpage, "window.__data__")
        if not text:
            raise ExtractorError("Unable to extract passcode page data")
        return self._parse_json(text, video_id, transform_source=js_to_json)

    def _csrf_token(self, base_url, video_id):
        body = self._download_webpage(
            Request(f"{base_url}csrf_js?t_x_zm_rid=1", data=b"", headers={"FETCH-CSRF-TOKEN": "1"}),
            video_id,
            note="Downloading CSRF token",
        )
        return self._search_regex(r"ZOOM-CSRFTOKEN:([\w-]+)", body, "CSRF token")

    def _share_info(self, base_url, meeting_id, video_id, note):
        domain = base_url.split("//", 1)[1].strip("/")
        return self._download_json(
            f"{base_url}nws/recording/1.0/play/share-info/{meeting_id}"
            f"?originDomain={domain}&accessLevel=meeting",
            video_id,
            note=note,
            headers={"X-Requested-With": "XMLHttpRequest"},
        )["result"]

    def _redirect_url(self, base_url, result, origin_url=None):
        redirect = urljoin(base_url, result["redirectUrl"])
        if "?" in redirect:
            return redirect
        query = {
            key: value
            for key, value in result.items()
            if isinstance(value, str) and key != "redirectUrl"
        }
        if origin_url:
            query["originRequestUrl"] = origin_url
        return update_url_query(redirect, query)

    def _unlock_with_passcode(self, base_url, share_url, result, video_id):
        passcode = self.get_param("videopassword")
        if not passcode:
            raise ExtractorError(
                "This video is protected by a passcode, use the --video-password option",
                expected=True,
            )
        component_url = self._redirect_url(base_url, result, origin_url=share_url)
        component = self._download_webpage(
            component_url,
            video_id,
            note="Downloading passcode page",
            headers={"Referer": share_url},
        )
        data = self._component_data(component, video_id)
        headers = {
            "zoom-csrftoken": self._csrf_token(base_url, video_id),
            "X-Requested-With": "XMLHttpRequest",
            "Referer": component_url,
        }
        self._download_json(
            f"{base_url}nws/recording/1.0/validate-context",
            video_id,
            note="Validating context",
            data=urlencode_postdata(
                {
                    "meetingId": data["meeting_id"],
                    "fileId": data["fileId"],
                    "useWhichPasswd": data["useWhichPasswd"],
                    "sharelevel": data["sharelevel"],
                    "iet": "",
                }
            ),
            headers=headers,
        )
        validation = self._download_json(
            f"{base_url}nws/recording/1.0/validate-meeting-passwd",
            video_id,
            note="Validating passcode",
            data=urlencode_postdata(
                {
                    "id": data["meeting_id"],
                    "passwd": passcode,
                    "action": data["action"],
                    "recaptcha": "",
                }
            ),
            headers=headers,
        )
        if not validation.get("status"):
            raise ExtractorError(validation.get("errorMessage") or "Wrong passcode", expected=True)
        return data["meeting_id"]

    def _real_extract(self, url):
        base_url, url_type, video_id = self._match_valid_url(url).group("base_url", "type", "id")
        if url_type != "share":
            return super()._real_extract(url)

        webpage = self._download_webpage(url, video_id, note="Downloading share webpage")
        meeting_id = self._get_page_data(webpage, video_id)["meetingId"]
        result = self._share_info(base_url, meeting_id, video_id, "Downloading share info JSON")
        if result.get("componentName") == "need-password":
            meeting_id = self._unlock_with_passcode(base_url, url, result, video_id)
            result = self._share_info(base_url, meeting_id, video_id, "Downloading share info JSON")

        info = super()._real_extract(self._redirect_url(base_url, result))
        info["id"] = video_id
        return info
```

Changes to that code:

- **Pacing.** A module-level `_pace(now=time.time, sleep=time.sleep, path=<temp dir>/mediagrabber-zoom-pacing, gap=5.0)` opens the state file, takes `fcntl.flock(LOCK_EX)`, reads the last timestamp (unreadable or empty counts as 0), sleeps `min(gap, last + gap - now())` when positive (the `min` stops a clock that jumped backwards from stalling a run), writes the current time and closes. A mixin overrides `_request_webpage(self, *args, **kwargs)` to call `_pace()` then `super()`. `ZoomIE` and a `ZoomClipsIE` subclass of the stock clips extractor both use the mixin, so every extractor request is paced whether or not the caller passed `--sleep-requests`.
- **Rejected passcode.** A `status` that is not true raises `ExtractorError('Zoom rejected the passcode', expected=True)`; Zoom's own `errorMessage` is ignored for classification. The response's key names (never values) go to `write_debug` so the next capture shows its shape.
- **Captcha before submit.** `data.get('needRecaptcha')` true raises before any passcode is sent: "Zoom is asking to confirm you're not a bot. Open the link in your browser once, then try again."
- **Dead link.** The sentence and its detection are decided from the Step 4 capture: a share page that is Zoom's own error page raises "This Zoom recording is no longer available."; a page that is not recognisably an error page and has no recording data raises "Zoom changed how its recordings work, so this link can't be read. MediaGrabber needs an update." Never the same sentence for both.
- **Sign-in or registration only.** A share-info `componentName` that asks for sign-in or registration raises "Private video: this Zoom recording is only available to signed-in viewers." Names are taken from a real capture when available; until then an unrecognised `componentName` other than `need-password` raises the "Zoom changed" sentence above.
- **No media URL.** `play/info` without `viewMp4Url` raises "The host of this Zoom recording hasn't allowed downloads." (raised by overriding the stock extractor's failing step, not by catching a broad exception).

- [ ] **Step 2: Write the plugin tests** (`unittest`, no network; Zoom responses are stubbed by replacing `_download_webpage` / `_download_json`, structure-only JSON and HTML stored beside the test)
  - Pacing: with a fake clock and fake sleep, two `_pace()` calls with no time between them sleep 5 s; a call 6 s after the last does not sleep; a state file holding a time far in the future sleeps at most 5 s; two sequential calls using the real file path in a temp dir never record times closer than 5 s.
  - Passcode missing: raises with `protected by a passcode`.
  - Passcode rejected: `validate-meeting-passwd` returns `{"status": false}` → raises `Zoom rejected the passcode`, and the stub shows exactly one `validate-meeting-passwd` call.
  - Captcha: `needRecaptcha` true → raises the not-a-bot sentence and the stub shows no `validate-meeting-passwd` call.
  - Happy path: the stub sequence in the verified flow ends with the stock extractor invoked on the play URL, and `info['id']` equals the share id.
  - Delegation: a non-share Zoom URL goes straight to `super()._real_extract` with no share-info request.
  - A passcode starting with `-` or containing a space reaches `validate-meeting-passwd` unchanged.

- [ ] **Step 3: Bundle and load the plugin**
  - `Project.swift`: the GrabberKit target gains the `resources` line above.
  - `makeContext`: append the bundled plugin directory (`Bundle(for: DownloadEngine.self).resourceURL` + `YtDlpPlugins`) to the shield's `dirs`.
  - `ExtractorContextTests`: a context built by `makeContext` for a non-YouTube URL includes a directory containing `zoomfix/yt_dlp_plugins/extractor/zoom_share_passcode.py`, with no shield running.
  - Run: `make plugin-test`, then `make test ONLY=GrabberKitTests/ExtractorContextTests`. Expected: PASS.

- [ ] **Step 4: Capture real transcripts, paced** (at most 7 requests per run, 5 s apart, 30 s between runs, `--retries 0 --extractor-retries 0`, timestamped log with the passcode masked)
  - One run against the user's protected link with a deliberately wrong passcode, `-J --no-warnings --no-playlist --no-update`. Save stderr verbatim to `zoom-stderr-passcode-rejected.txt` with the recording token removed. Expected: an `ERROR:` line containing `Zoom rejected the passcode`. Also keep the debug line with the response's key names for the next step. This is the only wrong passcode sent to that recording; do not repeat it.
  - One run against a made-up share id on the same host. Save stderr to `zoom-stderr-unavailable.txt`, and record the share page's title and visible error text (structure only) so the dead-link detection in Step 1 can be written from evidence. Expected: an `ERROR:` line that contains `no longer available` and not `passcode`.
  - If the first transcript has no `Zoom rejected the passcode`, or the second has no recognisable error page, stop and bring the transcripts to the user: Step 1's wording must not be guessed.
  - With the evidence in hand, add the dead-link detection to the plugin and its test to `test_zoom_share_passcode.py`, using the recorded page structure as the stub, then re-run the second capture once to confirm the transcript now carries `no longer available`.

### Task 1: Classification and probe copy

**Files:**

- Modify: `Sources/GrabberKit/Download/ErrorClass.swift`, `ErrorClass+Presentation.swift`, `ErrorSignatures.swift`, `FailurePresentation.swift`, `MetadataProbe.swift` (`MetadataError`, `classify`), `DownloadEngine+Helpers.swift` (`errorClass(for:)`)
- Modify: `Sources/App/AppModelDialogs.swift` (`probeErrorMessage`)
- Test: `Tests/GrabberKitTests/ErrorSignaturesTests.swift`, `FailurePresentationTests.swift`, `ErrorClassKeyTests.swift`, `MetadataProbeTests.swift`

**Interfaces:**

- Produces:
  - `ErrorClass.passcodeRequired`, `ErrorClass.passcodeRejected` (keys `"passcode_required"`, `"passcode_rejected"`)
  - `MetadataError.passcodeRequired`, `MetadataError.passcodeRejected`
  - Sentences: required → "This recording needs a passcode."; rejected → "That passcode didn't work."
  - Neither class is auto-retryable and neither offers `.retry`; the action that fixes them is added in Task 3.

- [ ] **Step 1: Write the failing tests**
  - `ErrorSignaturesTests.test_passcodeRequired`: `classify("ERROR: [zoom] abc: This video is protected by a passcode, use the --video-password option")` is `.passcodeRequired`.
  - `test_passcodeRejected`: the first Task 0 fixture's `ERROR:` line (loaded with the fixture loader the probe tests use) is `.passcodeRejected`.
  - `test_unavailableRecording_isUnavailableNotPasscode`: the second fixture's `ERROR:` line is `.unavailable` and neither passcode class.
  - `test_zoomPrivateAndBotSentences`: the plugin's sign-in-only sentence is `.private` and its not-a-bot sentence is `.botCheck`.
  - `test_passcodeWordOutsideAnErrorLine_isIgnored`: `classify("[zoom] abc: Validating passcode")` is `nil`.
  - `FailurePresentationTests`: both classes added to `cases`; `isAutoRetryable` false; `offeredActions` does not contain `.retry`.
  - `ErrorClassKeyTests`: the two keys.
  - `MetadataProbeTests`: required line as stderr → `.failure(.passcodeRequired)`; first fixture → `.failure(.passcodeRejected)`; second fixture → neither.

- [ ] **Step 2: Run to verify failure**

Run: `make test ONLY=GrabberKitTests/ErrorSignaturesTests` Expected: compile FAIL.

- [ ] **Step 3: Implement**
  - `ErrorSignatures.firstMatch`: before the table, check the passcode classes against `ERROR:` content only — text counts only when it contains `error:`. `.passcodeRequired` matches `protected by a passcode`; `.passcodeRejected` matches `zoom rejected the passcode` (the plugin's pinned wording) and is checked after `.passcodeRequired`.
  - `MetadataProbe.classify`: after the cookie-read check, map those matches to the new `MetadataError` cases.
  - `errorClass(for:)`: 1:1 mapping.
  - `FailurePresentation`: both sentences in `fixedSentences`; both keys in `noRetryKeys`.
  - `probeErrorMessage`: required → "This recording needs a passcode."; rejected → "That passcode didn't work."
  - Fix every exhaustive `switch` over `ErrorClass` / `MetadataError` the compiler flags.

- [ ] **Step 4: Run to verify pass**

Run: `make test ONLY=GrabberKitTests/ErrorSignaturesTests`, `.../FailurePresentationTests`, `.../ErrorClassKeyTests`, `.../MetadataProbeTests`, `.../YouTubeErrorClassificationTests` Expected: PASS. Then `make lint`, expected clean.

### Task 2: Passcode plumbing and engine behaviour

**Files:**

- Modify: `Sources/GrabberKit/Download/ExtractorContext.swift`, `YtDlpArguments.swift` (`extractorFlags`, `redacted`), `DownloadEngine.swift` (storage), `DownloadEngine+Preview.swift` (`makeContext`), `DownloadEngine+Retry.swift`, `DownloadEngine+Mutations.swift` (completion, `remove`), `DownloadEngineProtocol.swift` (protocol)
- Modify: `Tests/AppUnitTests/Support/AppFakes.swift` (the engine fake gains the two new methods)
- Test: `Tests/GrabberKitTests/YtDlpArgumentsPasscodeTests.swift`, `Tests/GrabberKitTests/EnginePasscodeTests.swift`

**Interfaces:**

- Consumes: `ErrorClass.passcodeRequired/Rejected` from Task 1.
- Produces:
  - `ExtractorContext.videoPassword: String?` (defaulted to `nil` so existing memberwise calls compile)
  - `YtDlpArguments.extractorFlags(context:redact:)` with `redact: Bool = false`; `redacted(...)` passes `redact: true`
  - `DownloadEngineProtocol.setPasscode(_ passcode: String, for url: String) async`
  - `DownloadEngineProtocol.retryWithPasscode(_ id: UUID, passcode: String) async` — no-op unless the job is `.failed(.passcodeRequired)` or `.failed(.passcodeRejected)`; otherwise stores the passcode for the job's URL and restarts it from scratch (attempt 0, part files deleted, re-enqueued at the tail), as `retryWithCookies` does minus `forceCookies`. Factor the shared reset into one private helper used by `retry`, `retryWithCookies` and `retryWithPasscode`.
  - `makeContext` fills `videoPassword` from the engine's in-memory map. A private `dropPasscode(for job:)` removes that URL's entry and is called wherever a job reaches a final state (completed, failed, cancelled) and in `remove(_:)`. Automatic re-queues (rate limit, network, incomplete) are not final and keep the entry.

- [ ] **Step 1: Write the failing tests**

`YtDlpArgumentsPasscodeTests`:

```swift
func test_videoPasswordEmittedAsSingleToken() {
    let ctx = ExtractorContext(pluginDirs: [], potBaseURL: nil, playerClient: nil, cookieArgument: nil, videoPassword: "-abc d")
    let argv = YtDlpArguments.build(for: request(), context: ctx, concurrentFragments: 4)
    XCTAssertTrue(argv.contains("--video-password=-abc d"))
    XCTAssertFalse(argv.contains("--video-password"))
}
func test_redactedMasksVideoPassword() { /* redacted(...) contains "--video-password=<redacted>" and no "-abc d" anywhere */ }
func test_noPasswordEmitsNoFlag() { /* default context: no element has prefix "--video-password" */ }
```

`EnginePasscodeTests` (same fixture style as `EngineRetryWithCookiesTests`):

- `test_probeUsesPasscode`: `setPasscode("p", for: url)` then `engine.preview(url)` passes a context whose `videoPassword == "p"` (asserted through the fake probe's recorded context).
- `test_downloadArgvCarriesPasscode`: the spawned yt-dlp argv contains `--video-password=p`.
- `test_processLaunchedLogNeverContainsPasscode`: passcode `"hunter two"`; the log events and the job log file contain no `hunter`.
- `test_failedPasscodeJob_retryWithPasscodeRequeues`: script a run that prints the required line and exits 1; after `retryWithPasscode(id, passcode: "p")` the job is queued or running again with `attempt == 0` and the next spawn carries `--video-password=p`.
- `test_retryWithPasscode_onNonPasscodeFailureIsNoOp` (geo-blocked job: state unchanged) and on a completed job.
- `test_completedFailedCancelledAndRemovedJobsDropPasscode`: after each outcome, a later `preview(url)` context has `videoPassword == nil`.
- `test_restartAfterFailureDoesNotReusePasscode`: a job with a passcode fails with a network error after exhausting retries; `retry(id)` spawns an argv with no `--video-password` element.
- `test_automaticRetryKeepsPasscode`: a job re-queued by a rate-limit deferral still spawns its next attempt with `--video-password=p`.

- [ ] **Step 2: Run to verify failure**

Run: `make test ONLY=GrabberKitTests/YtDlpArgumentsPasscodeTests` Expected: compile FAIL (`videoPassword` not defined).

- [ ] **Step 3: Implement** as in Interfaces. `extractorFlags` appends `["--video-password=\(value)"]` (or `<redacted>` when `redact`) when `videoPassword` is non-empty.

- [ ] **Step 4: Run to verify pass**

Run: `make test ONLY=GrabberKitTests/YtDlpArgumentsPasscodeTests`, `.../EnginePasscodeTests`, `.../YtDlpArgumentsContextTests`, `.../ExtractorContextTests`, `.../EngineRetryWithCookiesTests`, `.../EngineRetryTests` Expected: PASS (the shared reset helper must not change existing retry behaviour). Then `make lint`, expected clean.

### Task 3: Row action, prompt, Add-flow wiring and site name

**Files:**

- Create: `Sources/App/Passcode/PasscodePrompt.swift`, `Sources/App/Passcode/PasscodeSheet.swift`
- Modify: `Sources/GrabberKit/Download/JobSnapshot.swift` (`RowAction`), `Sources/GrabberKit/Download/FailurePresentation.swift`
- Modify: `Sources/App/Theme/Icon.swift`, `Sources/App/Table/DownloadsGridTokens.swift`, `Sources/App/Table/BatchEligibility.swift` (compiler-driven exhaustiveness)
- Modify: `Sources/App/AppModel.swift` (state), `Sources/App/AppModelPlaylist.swift` (`showProbeFailure`), `Sources/App/AppModelQueueFlow.swift` (`resolvePasted`, `clearResolved`), `Sources/App/AppModelRowActions.swift` (`.enterPasscode` case), `Sources/App/Home/HomeView.swift` (button under the probe error), `Sources/App/MainWindow.swift` (sheet, beside the shield sheet at line 60), `Sources/App/SiteNames.swift`
- Test: `Tests/AppUnitTests/PasscodePromptTests.swift`, `Tests/AppUnitTests/SiteDisplayNameTests.swift`, `Tests/GrabberKitTests/FailurePresentationTests.swift`, `AvailableActionsTests.swift`

**Interfaces:**

- Consumes: `DownloadEngineProtocol.setPasscode` / `retryWithPasscode` (Task 2); the Task 1 error cases.
- Produces:
  - `RowAction.enterPasscode` (added to `displayOrder` after `.retryWithCookies`; label "Enter passcode", icon `lock.fill`); `FailurePresentation` offers exactly `[.enterPasscode]` for both passcode classes; excluded from batch actions like `.retryWithCookies`.
  - `struct PasscodePrompt: Equatable { enum Target: Equatable { case link(String), job(UUID) }; let target: Target; let url: String; let wasRejected: Bool }`
  - `AppModel.passcodeNeeded: PasscodePrompt?` and `AppModel.isPasscodeSheetShown: Bool`
  - `AppModel.submitPasscode(_ raw: String) async` — trims whitespace/newlines; empty after trimming does nothing and keeps the sheet open; `.link(url)` → `engine.setPasscode` then `resolvePasted(url)`; `.job(id)` → `engine.retryWithPasscode`; closes the sheet and clears `passcodeNeeded` on success.
  - `AppModel.cancelPasscodePrompt()` — closes the sheet; keeps `passcodeNeeded` so the Home "Enter passcode" button can reopen it for a link target.
  - `SiteNames` entries `"zoom": "Zoom"`, `"zoom:clips": "Zoom"`.

Sheet copy (plain text field, visible): title "Enter passcode"; body "This recording is protected. Enter the passcode its owner gave you."; when `wasRejected`, body "That passcode didn't work. Check it and try again."; buttons "Continue" (default, disabled while the trimmed field is empty) and "Cancel".

- [ ] **Step 1: Write the failing tests**
  - `FailurePresentationTests`: `offeredActions == [.enterPasscode]` for `.passcodeRequired` and `.passcodeRejected`.
  - `PasscodePromptTests` (same fake-engine setup as `AppModelShieldPromptTests`):
    - `test_probePasscodeRequired_opensSheetAndSetsMessage`: fake engine preview returns `.failure(.passcodeRequired)`; after `resolvePasted`, `isPasscodeSheetShown`, `passcodeNeeded == PasscodePrompt(target: .link(url), url: url, wasRejected: false)` and `probeError == "This recording needs a passcode."`.
    - `test_probePasscodeRejected_setsWasRejected`.
    - `test_submitPasscode_link_savesThenReprobes`: engine fake records `setPasscode("secret", for: url)` and a second `preview(url)`; sheet closed.
    - `test_submitPasscode_wrongAgain_reopensSheetRejected`: second preview returns `.passcodeRejected`; sheet shown again with `wasRejected == true`; `isProbing == false`.
    - `test_submitPasscode_trimsAndIgnoresEmpty`: `"  p\n"` saves `"p"`; `"   "` calls nothing and leaves the sheet open.
    - `test_enterPasscodeRowAction_opensSheetForJob`, `test_submitPasscode_job_callsRetryWithPasscode`.
    - `test_cancel_keepsNeededForLink`.
  - `SiteDisplayNameTests`: `SiteNames.display("zoom") == "Zoom"` and `"zoom:clips"`.

- [ ] **Step 2: Run to verify failure**

Run: `make test ONLY=AppUnitTests/PasscodePromptTests` Expected: compile FAIL.

- [ ] **Step 3: Implement**
  - `RowAction.enterPasscode`, its presentation entry and every exhaustive switch the compiler flags; the `.enterPasscode` branch of `handleRowAction` looks up the row's URL, sets `passcodeNeeded` to `.job(id)` (`wasRejected` true when the row's failure class is `.passcodeRejected`) and shows the sheet.
  - `showProbeFailure`: for the two passcode errors also set `passcodeNeeded` (`.link(url)`) and `isPasscodeSheetShown = true`. `resolvePasted` and `clearResolved` reset `passcodeNeeded` and the sheet flag at their start.
  - `HomeView`: when `passcodeNeeded` has a `.link` target, show an "Enter passcode" button under the error text (same place as `ShieldPromptButton`) that sets `isPasscodeSheetShown = true`.
  - `MainWindow`: `.sheet(isPresented: $appModel.isPasscodeSheetShown)` presenting `PasscodeSheet`.

- [ ] **Step 4: Run to verify pass**

Run: `make test ONLY=AppUnitTests/PasscodePromptTests`, `.../SiteDisplayNameTests`, `.../BannerResolverTests`, `.../RowStatusTextTests`, then `make test ONLY=GrabberKitTests/FailurePresentationTests` and `.../AvailableActionsTests` Expected: PASS. Then `make lint`, expected clean.

### Task 4: Real-link verification

**Files:**

- Modify (only if Step 3 finds the problem): `Sources/GrabberKit/Download/YtDlpArguments.swift` (`videoSelector`), `Tests/GrabberKitTests/YtDlpArgumentsTests.swift`

This task uses the user's protected link. A public recording and a Clips link are not available yet; those checks are listed under "Untested against real Zoom" at the end and stay open until a link exists. All runs follow the pacing rule in Global Constraints.

- [ ] **Step 1: Full suite and lint**

Run: `make test` then `make lint`. Expected: all green.

- [ ] **Step 2: Run the app and paste each link** (`make run`)
  - Protected recording: the sheet opens; the right passcode downloads the full file (about 653 MB) and the result plays. Restarting the finished row asks for the passcode again. Do not enter a second wrong passcode against the user's recording; the reopen-after-wrong behaviour is covered by the Task 3 tests.
  - Protected recording queued, then quit and relaunch: the job fails with "This recording needs a passcode." and the row's "Enter passcode" action restarts it.
  - Made-up share link: the row shows the dead-link sentence, not a passcode prompt.

- [ ] **Step 3: Check the format selector against Zoom**

If any Zoom download fails with the "quality you picked isn't available" sentence, run the probe JSON for that link and look at `formats[].height`. If heights are missing, change the last alternative of `videoSelector` from `b[height<=N]` to `b[height<=?N]` (unknown height passes the cap) and update the pinned strings in `YtDlpArgumentsTests`. If heights are present, change nothing.

- [ ] **Step 4: Add signatures for the failure messages seen in Step 2**

For each expired or restricted recording that surfaced raw tool text, add a `(errorClass, substrings)` entry with a test built from its transcript and a true, plain sentence in `FailurePresentation`, per the copy constraint above.

- [ ] **Step 5: Final**

Run: `make test` then `make lint`. Expected: green.

## Untested against real Zoom

Revisit each when a link is available; any Zoom traffic stays at 5 s spacing, never two requests within 3 s.

- Zoom Clips link (`zoom:clips`): no passcode flow is expected; the download itself is unverified.
- Public share with no passcode: the plugin hands it to the stock extractor; unverified.
- Wrong-passcode response body: only the rejection is known, not Zoom's message text, lockout or captcha shape.
- Dead or deleted share link: Zoom's page carries no `window.__data__`, and the plugin currently reports it as a generic extraction failure.
- Sign-in-only or registration-only shares.
- Downloads disabled by the host (no media URL in `play/info`).
