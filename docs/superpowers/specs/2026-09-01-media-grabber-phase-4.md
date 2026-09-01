# Retry and error classification (Phase 4)

**Status:** design complete. Plan: not yet written. Parent spec:
`docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1.
Phase 2 (shipped): `docs/superpowers/specs/queue-foundation.md`.
Phase 3 (shipped): `docs/superpowers/specs/archived/2026-08-31-media-grabber-phase-3.md`.
Phase 1 (shipped): `docs/superpowers/specs/archived/core-download-pipeline.md`.

Phases 1–3 built the download pipeline, the engine-owned queue and multi-slot
scheduler, the Downloads table with its full row-action bar, per-job raw logs,
persistence across launches, and the Preferences editor. Phase 4 is the layer
that classifies a `yt-dlp` failure, explains it in plain language, and — where a
re-attempt could plausibly succeed — retries it automatically on a backoff
schedule. It also verifies every completed file against the probe's duration and
records the real resolution.

Everything here is built to its final-app form. The `ErrorClass` → presentation
model, the retry orchestration in the engine's terminal path, and the backoff
schedule are the shapes the app keeps; Phase 6 (per-host cooldown) and Phase 7
(YouTube `ErrorClass` cases, per-attempt `player_client`) extend them additively
with no relayout (parent §12 scoping rule).

---

## 1. Scope

**In this phase:**

- **Error classification.** `ProgressParser.classifyStderr` recognises the
  generic failure signatures and maps them to `ErrorClass`: `rateLimited`,
  `geoBlocked`, `private`, `unavailable`, `ageRestricted`, `networkDown`,
  `depMissing`, `unknown` (fallthrough).
- **`FailurePresentation`** — a `GrabberKit` value type keyed off `ErrorClass`,
  giving each case its one-sentence plain-English reason and the `RowAction` set
  its failed row offers. `ErrorClass` carries a stable `key` string (logs, the
  later diagnostics report) and a `presentation` accessor.
- **The Retry row action, live** in the Phase 2 action bar (`forceStart` is
  already live from Phase 2). The engine picks per failure: a usable `.part`
  plus a transient class **resumes** (keeps `.part` and `attempt`); otherwise it
  **retries** from scratch (deletes `.part`, resets `attempt`). The button reads
  "Retry" in the UI either way.
- **The per-job auto-retry budget.** After a classified auto-retryable failure,
  a job with `attempt < Preferences.maxAutoRetries` re-queues on the backoff
  schedule with `attempt` incremented; at the budget it goes terminal
  `.failed`. `maxAutoRetries` (1–5) and its "Automatic retries" Downloads-pane
  control ship from Phase 3; Phase 4 is the engine that honours it.
- **`Backoff`** — a pure type: exponential with full jitter
  (`random(0, base)`), a ladder (default 30 → 60 → 120 → 300 → 600 s, last entry
  held) with a cap, an integer-seconds `Retry-After` honoured when `yt-dlp`
  surfaces one. The first caller of the Phase 2 `deferStart(_:until:)` seam.
- **`EngineTuning`** — one env-overridable constant (`MG_*` keys, no UI) holding
  every retry / pacing number: the `Backoff` ladder and cap, and the §7.5
  `yt-dlp` flag values (`YtDlpTuning`).
- **`DeferReason.backoff(attempt:)`** — the first emittable case of the Phase 2
  enum, logged through the existing `jobDeferred` event. New `LogEvent` cases
  `jobRetried(id:)` (a from-scratch retry — the one the diagnostics report
  counts) and `showLogTargetMissing(jobID:)`.
- **`IntegrityCheck`** — an `ffprobe` call on every completed file: a duration
  materially short of the probe's `durationSeconds` fails the job `.incomplete`
  (consuming a retry attempt); the same call reads the real resolution into
  `JobSnapshot.actualQuality`, letting the Quality column show `1080p → 720p`.
  It degrades to `IntegrityVerdict.skipped` when `ffprobe` is absent or the
  expected duration is unknown.
- **The always-on download flags** (parent §7.5) in `YtDlpArguments`.
- **`EnvironmentProbe` reports `ffprobe`**, resolved from the `ffmpeg` location.
  The every-launch environment re-probe (`AppModel.refreshOnboardingState`,
  Phase 2) already routes a vanished `yt-dlp` / `ffmpeg` back to Onboarding.
- **The `showLog` row action, live** — opens the per-job `JobLog` file in the
  default text editor; a missing file shows a notice (the Phase 2
  `revealTargetMissing` pattern).
- **`screens.html`** — the §1 Home table gains a failed row and a retrying row,
  one completed row's Quality cell shows `1080p → 720p`, and the row-action bar
  is drawn with its full button set and the Phase 4 enable states (§11).

**Deferred (hints land in the owning phase's stub):**

- The live `m:ss` countdown in the Status cell during a backoff wait — Phase 6,
  which owns the cooldown chip, its popover, and the "clears in" machinery.
  Phase 4's Status cell shows `Retrying — attempt 3 of 5` with no ticking clock.
- Per-host `RateState`, cooldown, circuit breaker, adaptive concurrency,
  `NetworkMonitor` / `waitingForNetwork` — Phase 6. A `rateLimited` result here
  retries on the plain `Backoff` schedule with no per-host memory.
- `player_client` rotation and per-attempt client context threaded into
  `YtDlpArguments` — Phase 7.
- The YouTube-specific `ErrorClass` cases (`botCheck`, `sabrGated`,
  `formatsMissing`, `potProviderDown`) and their presentation entries — Phase 7,
  built with the §7.2 machinery that emits them.
- `retryWithCookies` (`🔑`) and the `cookieReadFailed` emit path — Phase 5.
  `cookieReadFailed` has a `FailurePresentation` entry this phase (its copy and
  `retry` action exist) but no classifier signature.

**Not in scope:**

- A dedicated `ffprobe` onboarding step. `ffprobe` ships inside the Homebrew
  `ffmpeg` formula; a present `ffmpeg` with a missing `ffprobe` is a corrupt
  install — rare, and it degrades to `IntegrityVerdict.skipped` rather than
  blocking downloads. The onboarding checklist and `OnboardingStepID` are
  untouched.
- Any `WarningBanner` or `HealthStrip` content — Phase 6 / 7.
- Toasts or native notifications for a failure — Phase 11.
- The Diagnostics page, the `yt-dlp` staleness banner, the updater — Phase 10.

---

## 2. Architecture

Retry orchestration lives in `DownloadEngine`'s terminal path — the synchronous
`recordExit` method — not in a separate controller. The engine owns
`job.attempt` (a `DownloadJob` field, persisted). The backoff policy is a pure
function with no state of its own. Two deferral sources — Phase 4 backoff and
Phase 6 host cooldown — coexist through the seam, not a coordinator: each calls
`deferStart(_ id:, until:)` with its own `Date`, the seam re-sorts and re-arms,
and `DeferReason` is the log discriminator.

```
Sources/GrabberKit/Download/
  ErrorClass.swift            — key, presentation, isAutoRetryable, retryAfterSeconds
  FailurePresentation.swift   — the ErrorClass-keyed { sentence, offeredActions } value
  ErrorSignatures.swift       — the substring → ErrorClass table (data); shared by both classifiers
  IntegrityCheck.swift        — ffprobe(file, expectedDuration) → verdict + actualQuality
Sources/GrabberKit/RateLimiting/
  Backoff.swift               — pure: delay(attempt:retryAfter:tuning:jitter:)
Sources/GrabberKit/Model/
  EngineTuning.swift          — the env-overridable knob umbrella: ytDlp + backoff ladder / cap
Sources/GrabberKit/Download/
  DownloadEngine+Mutations.swift   — recordExit: the classify → retry-or-fail branch
  DownloadEngine.swift             — retry(_:) intent, ffprobeURL / tuning deps, the integrity call
  YtDlpArguments.swift             — the always-on flags from YtDlpTuning in baseArgv
Sources/GrabberKit/Onboarding/
  EnvironmentProbe.swift      — EnvironmentReport.ffprobe
Sources/App/
  AppModel.swift              — handleRowAction: .retry and .showLog
  Rows/RowModel.swift         — status text: presentation sentence + retry-state variants
```

### The terminal path

The launcher `Task` (outside actor isolation) runs the download to exit, then —
on `exitCode == 0` — resolves the output file and awaits
`IntegrityCheck.verify(...)` against it; only then does it re-enter the actor
through `recordExit`, which now carries the integrity result. `IntegrityCheck`
needs the *finalized* file, so it runs strictly after the process exits, never
alongside it.

`recordExit(_ id:, _ result:, integrity:, lastError:, launchFailed:)` runs
synchronously (the Phase 2 mutation invariant). Its decision order:

1. `launchFailed` → `haltForDepMissing` (Phase 2 behaviour).
2. `result.wasCancelled` → `.cancelled`.
3. `result.exitCode == 0`:
   - `integrity.verdict` is `.passed` / `.skipped(_)` → `.completed`; store
     `integrityVerdict` and `actualQuality`,
   - `.failed(reason:)` → a failure with `ErrorClass.incomplete`; store the
     verdict and fall to step 4.
4. a non-zero exit, or a failed integrity check: classify.
   - `errorClass = lastError ?? .unknown(raw: "yt-dlp exited \(exitCode)")`
     (integrity: `.incomplete`),
   - `errorClass.isAutoRetryable` **and** `job.attempt < maxAutoRetries` →
     `job.attempt += 1`, `job.state = .queued`,
     `deferStart(id, until: clock.now + Backoff.delay(attempt: job.attempt, retryAfter: errorClass.retryAfterSeconds, tuning: tuning))`,
     log `jobDeferred(id:, until:, reason: .backoff(attempt: job.attempt))`,
   - otherwise → `job.state = .failed(errorClass)`, `job.finishedAt = .now`.
5. `enforceTerminalCap` / `bump` / `emitSnapshot` / `evaluateSchedule` (Phase 2).

An auto-retry re-queue is one sync mutation: the job moves `.running` →
`.queued` with `attempt` bumped and a pending deferral, no transient `.failed`
snapshot. `nextDownloads` skips `deferredIDs` (Phase 2), so the scheduler
ignores the job until the backoff `Task` fires `evaluateSchedule()`.

`maxAutoRetries` is read from `preferences` at classification time — live, like
`cap` — so a mid-flight pref change applies to the next failure.

### `IntegrityCheck` and the process rule

`IntegrityCheck` shells `ffprobe` through a `ProcessRunning`. `ProcessRunner`
stays the only `Foundation.Process` touch and `DownloadEngine` stays the only
component that spawns a child — the `verify` call is made from the engine's
launcher `Task`, after the process exits and the output file resolves, before
`recordExit`. A nil or non-executable `ffprobeURL` yields
`IntegrityVerdict.skipped` with no spawn.

### How Phases 6 and 7 attach

- Phase 6's `SchedulerInput.hostStates` and its second `deferStart` caller do
  not touch Phase 4's `deferStart` use — the seam already handles multiple
  deferral sources by `Date` (Phase 2, tested).
- Phase 6's live Status-cell countdown reads `JobSnapshot.cooldownUntil`, which
  Phase 4 leaves nil; the countdown is an additive read of the same row state.
- Phase 7's per-attempt `player_client` threads into
  `YtDlpArguments.build(for:options:)` keyed on `job.attempt`, orthogonal to the
  retry orchestration.

---

## 3. Error classification and presentation

### 3.1 `ErrorClass`

`ErrorClass` is the full 16-case enum from Phase 1. In Phase 4 the `rateLimited`
case carries an optional `Retry-After`:

```swift
case rateLimited(retryAfterSeconds: Int? = nil)
```

Every other case keeps its shape. `ErrorClass` exposes:

```swift
public extension ErrorClass {
    // A stable token for logs and the later diagnostics report — not user-facing.
    var key: String {
        switch self {
        case .rateLimited: "rate_limited"
        case .botCheck: "bot_check"
        case .sabrGated: "sabr_gated"
        case .formatsMissing: "formats_missing"
        case .cookieReadFailed: "cookie_read_failed"
        case .geoBlocked: "geo_blocked"
        case .private: "private"
        case .unavailable: "unavailable"
        case .ageRestricted: "age_restricted"
        case .networkDown: "network_down"
        case .diskFull: "disk_full"
        case .permissionDenied: "permission_denied"
        case .incomplete: "incomplete"
        case .depMissing: "dep_missing"
        case .potProviderDown: "pot_provider_down"
        case .unknown: "unknown"
        }
    }

    var presentation: FailurePresentation { FailurePresentation.for(self) }

    var isAutoRetryable: Bool {
        switch self {
        case .rateLimited, .networkDown, .incomplete, .unknown: true
        default: false
        }
    }

    var retryAfterSeconds: Int? {
        if case let .rateLimited(seconds) = self { return seconds }
        return nil
    }
}
```

### 3.2 `FailurePresentation`

```swift
public struct FailurePresentation: Sendable, Equatable {
    // One plain-English sentence — no error code, no yt-dlp jargon.
    public let sentence: String
    // Row actions offered beyond the always-present remove / openInBrowser / showLog.
    public let offeredActions: Set<RowAction>

    public static func `for`(_ errorClass: ErrorClass) -> FailurePresentation { … }
}
```

One `switch` over `ErrorClass` in one file. The YouTube cases are four more arms
in Phase 7 — no other file changes.

| `ErrorClass` | Sentence | `offeredActions` (∪ remove / openInBrowser / showLog) |
|---|---|---|
| `rateLimited` | The site is limiting how fast we can download right now. | `retry` |
| `geoBlocked` | This video isn't available in your region. | — |
| `private` | This video is private. | — |
| `unavailable` | This video is no longer available. | — |
| `ageRestricted` | This video is age-restricted and needs you to be signed in. | — |
| `networkDown` | No internet connection. | `retry` |
| `cookieReadFailed` | Couldn't read your browser's sign-in. | `retry` |
| `diskFull` | The disk is full. | `retry` |
| `permissionDenied` | The download folder isn't writable. | `retry` |
| `incomplete` | The download kept ending early. | `retry` |
| `depMissing` | The downloader needs reinstalling. | — |
| `unknown(raw)` | *the trimmed raw `ERROR:` line* | `retry` |

The classes with no `retry` (`geoBlocked`, `private`, `unavailable`,
`ageRestricted`, `depMissing`) are the parent's "stop, show a remedy" set — a
re-attempt cannot succeed. Phase 5 adds `retryWithCookies` to `private` and
`ageRestricted`.

`FailurePresentation` owns only the per-class reason clause and the action set.
`RowModel` owns the `Failed — ` prefix and the retry-state Status variants (§4.4).

### 3.3 The stderr signature table

`ErrorSignatures` is the substring → `ErrorClass` data table.
`ProgressParser.classifyStderr` (the download-side entry point callers already
use) reads from it; `MetadataProbe`'s classifier reads the same table for the
strings it shares, so the two agree by construction rather than by two
hand-kept lists.

| `ErrorClass` | stderr substrings (case-insensitive) |
|---|---|
| `rateLimited` | `HTTP Error 429`, `Too Many Requests`, `Download speed ... below throttle limit`, `The download speed is below the minimum` |
| `geoBlocked` | `not available in your country`, `blocked it in your country`, `geo restrict` |
| `private` | `Private video`, `Sign in if you've been granted access to this video` |
| `unavailable` | `Video unavailable`, `This video is unavailable`, `This video is not available`, `has been removed`, `no longer available` |
| `ageRestricted` | `Sign in to confirm your age`, `age-restricted`, `confirm your age` |
| `networkDown` | `ProgressParser.networkSignatures` (Phase 1) |

`classifyStderr` order: the network signatures, then the table above top to
bottom, then an `ERROR:`-prefixed line → `.unknown(raw: line)`, then nil. A
`Retry-After: <int>` on a `rateLimited` match parses into
`.rateLimited(retryAfterSeconds:)`; an HTTP-date `Retry-After` is ignored and
the jitter schedule applies.

`cookieReadFailed`, `botCheck`, `sabrGated`, `formatsMissing`, `potProviderDown`
have no Phase 4 signature — their emit paths belong to Phase 5 / 7.

### 3.4 `availableActions` for `.failed`

`DownloadEngine.availableActions(for:)` keeps its `JobState` parameter (the
`ErrorClass` rides inside `.failed`). The `.failed` arm:

```swift
case let .failed(errorClass):
    errorClass.presentation.offeredActions
        .union([.remove, .openInBrowser, .showLog])
```

`showLog` belongs to every state whose job has run: `.running`, `.paused`,
`.completed`, `.cancelled`, `.failed`. `.queued` and `.probing` do not offer it
(no log file yet).

---

## 4. Retry and backoff

### 4.1 The auto-retryable set

Auto-retried on the backoff schedule: `rateLimited`, `networkDown`,
`incomplete`, `unknown` (`ErrorClass.isAutoRetryable`).

Offered as a manual `retry` but never auto-retried: `diskFull`,
`permissionDenied`, `cookieReadFailed` — an immediate re-attempt fails the same
way; the user frees space, fixes the folder, or (Phase 5) supplies cookies, then
retries.

No `retry` at all: `geoBlocked`, `private`, `unavailable`, `ageRestricted`,
`depMissing`.

`isAutoRetryable` is a strict subset of the classes whose
`presentation.offeredActions` contains `retry`.

### 4.2 `Backoff`

```swift
public enum Backoff {
    // attempt is 1-based — the first retry is attempt 1.
    public static func delay(
        attempt: Int,
        retryAfter: Int? = nil,
        tuning: EngineTuning = .default,
        jitter: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) -> TimeInterval {
        if let retryAfter, retryAfter > 0 {
            return TimeInterval(min(retryAfter, tuning.backoffCap))
        }
        let ladder = tuning.backoffLadder
        let base = min(ladder[min(attempt, ladder.count) - 1], tuning.backoffCap)
        return jitter(0 ... Double(base))     // full jitter
    }
}
```

- The ladder defaults to `30, 60, 120, 300, 600`; `attempt` past its length
  reuses the last entry. `backoffCap` (default 600) ceilings every value,
  including a `retryAfter`.
- Full jitter — the wait is `random(0, base)`, spreading a fleet of retrying
  jobs (parent §7.4).
- An integer-seconds `retryAfter` wins over the ladder, capped, used with no
  jitter.
- The `jitter` closure is injected so tests assert the ladder and the bounds
  deterministically.

`maxAutoRetries` (1–5) caps `attempt`. A job that fails at `attempt ==
maxAutoRetries` with a retryable class goes terminal. At `maxAutoRetries == 1` a
single retry is attempted, then the job fails.

### 4.3 The "Retry" button — resume or retry

The row button reads **Retry** in the UI regardless. `handleRowAction(id,
.retry)` calls the engine intent `retry(_ id: UUID) async`, and the engine picks
one of two behaviours from the failed job's state:

**Resume** — when a usable `.part` file is on disk **and** the failure class is
`networkDown`, `incomplete`, or `unknown`:

- `job.state = .queued`, `job.finishedAt = nil`, re-enqueued at the tail,
- `job.attempt` **unchanged** — a resume is not a fresh start,
- `job.integrityVerdict = nil`, `job.actualQuality` cleared,
- `.part` kept — `yt-dlp` continues the partial download,
- logged as `jobResumed(id:)` (Phase 2 event),
- a resumed job that fails again re-enters the §2 auto-retry path from its
  current `attempt`.

**Retry** — otherwise (`rateLimited`, `diskFull`, `permissionDenied`,
`cookieReadFailed`, or no usable `.part`):

- `job.attempt = 0` — the full auto budget is restored,
- `.part` **deleted** — the download restarts clean,
- `job.state = .queued`, `job.finishedAt = nil`, re-enqueued at the tail,
- `job.integrityVerdict = nil`, `job.actualQuality` cleared,
- logged as `jobRetried(id:)` (new event — the diagnostics report counts
  retries, not resumes).

Both paths: no `deferStart` (the user chose the moment), then `bump` /
`emitSnapshot` / `evaluateSchedule`. The intent is a no-op on a job whose class
does not offer `retry`, or a non-`.failed` job (the UI already disables the
button; the engine re-checks).

"Usable `.part`" — a `.part` file matching the job's title stem exists in the
destination folder and is non-empty. The Phase 2 `titleStem` helper and the
`deletePartFiles` helper already cover the matching and the delete.

### 4.4 The Status cell during a retry

`RowModel.status(for:)` on a `.queued` job:

- `attempt == 0` → `Queued` (with `· #N` position, Phase 2).
- `attempt > 0` → `Retrying — attempt \(attempt + 1) of \(maxAutoRetries)`, no
  position badge, no countdown.

`maxAutoRetries` reaches `RowModel` with the event, not through a `RowStore`
dependency: `AppModel` (which holds `prefs`) passes the current
`maxAutoRetries` into `RowStore.apply(_:)` / the recompute alongside
`queuePosition`. `RowStore` stays `Preferences`-free.

A `.failed` job at the exhausted budget shows `Failed — \(presentation.sentence)`
with the Retry button enabled.

The live `m:ss` countdown is Phase 6, which owns the "clears in" machinery and
the per-second re-render. Its stub carries the hint.

### 4.5 Logging

```swift
public enum DeferReason: Sendable, Equatable {
    case backoff(attempt: Int)
}
```

A per-host cooldown case joins this enum when that deferral source is built; the
`jobDeferred` event and the seam already carry it.

`LogEvent` events:

- `jobDeferred(id:, until:, reason:)` (Phase 2) — fields
  `{ "reason": "backoff", "attempt": "\(n)", "until": <iso8601> }`.
- `jobRetried(id:)` — new; a from-scratch retry (not a resume). Category
  `.engine`, key `job.retried`, no extra fields.
- `showLogTargetMissing(jobID:)` — new; parallel to `revealTargetMissing`.
  Category `.ui`, key `show_log.target_missing`.

### 4.6 `EngineTuning`

Every retry / pacing knob is a value in one type, not a compiled literal, so the
numbers can be tuned or A/B'd through the environment without a build. Not
exposed in the UI.

```swift
public struct YtDlpTuning: Sendable, Equatable {
    public var retries: Int              // --retries
    public var fragmentRetries: Int      // --fragment-retries
    public var socketTimeout: Int        // --socket-timeout (seconds)
    public var retrySleep: String        // --retry-sleep value
    public var throttledRateKBps: Int    // --throttled-rate (K)
    public var fileAccessRetries: Int    // --file-access-retries
    public var sleepRequests: Int        // --sleep-requests (seconds)
    public var sleepInterval: Int        // --sleep-interval (seconds)
    public var maxSleepInterval: Int     // --max-sleep-interval (seconds)

    public static let `default` = YtDlpTuning(
        retries: 3, fragmentRetries: 10, socketTimeout: 30,
        retrySleep: "linear=1:10:2", throttledRateKBps: 100,
        fileAccessRetries: 5, sleepRequests: 1,
        sleepInterval: 1, maxSleepInterval: 5
    )
}

public struct EngineTuning: Sendable, Equatable {
    public var ytDlp: YtDlpTuning
    public var backoffLadder: [Int]      // seconds per attempt; last value holds
    public var backoffCap: Int           // ceiling applied to every entry

    public static let `default` = EngineTuning(
        ytDlp: .default,
        backoffLadder: [30, 60, 120, 300, 600],
        backoffCap: 600
    )

    // Every unset / malformed key keeps the default; a malformed key logs once.
    public static func resolved(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> EngineTuning { … }
}
```

Environment keys, all optional:
`MG_YTDLP_RETRIES`, `MG_YTDLP_FRAGMENT_RETRIES`, `MG_YTDLP_SOCKET_TIMEOUT`,
`MG_YTDLP_RETRY_SLEEP`, `MG_YTDLP_THROTTLED_RATE_KBPS`,
`MG_YTDLP_FILE_ACCESS_RETRIES`, `MG_YTDLP_SLEEP_REQUESTS`,
`MG_YTDLP_SLEEP_INTERVAL`, `MG_YTDLP_MAX_SLEEP_INTERVAL`,
`MG_BACKOFF_LADDER` (comma-separated ints), `MG_BACKOFF_CAP`.

`EngineDependencies` carries `tuning: EngineTuning` (default `.default`);
`EngineDependencies.live(...)` sets `.resolved()`. `YtDlpArguments.build` takes
`tuning: YtDlpTuning = .default`; `Backoff.delay` takes `tuning: EngineTuning =
.default` and reads `backoffLadder` / `backoffCap` in place of the inline
constants. Both defaults keep every existing call site compiling.

---

## 5. IntegrityCheck

### 5.1 The check

```swift
public struct IntegrityCheck: Sendable {
    public init(runner: ProcessRunning, ffprobeURL: URL?)

    public func verify(
        file: URL,
        expectedDurationSeconds: Int?
    ) async -> IntegrityResult
}

public struct IntegrityResult: Sendable, Equatable {
    public let verdict: IntegrityVerdict
    public let actualQuality: String?         // "720p" for video, nil for audio or unknown
}
```

- `ffprobeURL == nil` or not executable → `verdict: .skipped(reason: "ffprobe
  unavailable")`, `actualQuality: nil`, no spawn.
- Invocation:
  `ffprobe -v quiet -print_format json -show_format -show_streams <file>`.
- Parse: `format.duration` (float seconds); the first video stream's `height`
  → `actualQuality = "\(height)p"`; no video stream → `actualQuality = nil`.
- A malformed or non-zero `ffprobe` → `.skipped(reason: "ffprobe failed")`,
  `actualQuality: nil` — a broken probe never fails a download.

### 5.2 The duration verdict

`expectedDurationSeconds == nil` (the probe missed it, or a live stream) →
`.skipped(reason: "no expected duration")`; `actualQuality` is still read from a
video stream if present.

With `actual = format.duration` and `expected = expectedDurationSeconds`:

- **materially short** ⇔ `actual < expected * 0.95` **and**
  `expected - actual > 10` — both, so a few seconds of trailing-silence trim on
  a short clip passes, and a small drift on a long video passes,
- materially short → `.failed(reason: "recording is \(Int(expected - actual))s short")`,
- else → `.passed`.

### 5.3 A failed check and the retry budget

A `.failed` duration verdict is classified `ErrorClass.incomplete` and flows
through the §4.1 auto-retry path like a non-zero exit — `incomplete` is
auto-retryable, so a truncated download re-downloads on the backoff schedule and
consumes an attempt. After `maxAutoRetries` truncated attempts the job is
terminal `.failed(.incomplete)` with the `The download kept ending early`
sentence and a manual `retry`.

A `.skipped` verdict never fails the job — `.completed` stands and
`actualQuality` is stored if the probe read it.

### 5.4 The Quality column

`JobSnapshot.actualQuality` is populated on completion whenever the probe read a
video stream. `RowModel.quality(for:)`:

- `actualQuality == nil` → the request value (`"1080p"` / `"m4a"`).
- `actualQuality` equal to the request height → the request value.
- `actualQuality` different → `"1080p → 720p"` (request → actual).

`actualQuality` is runtime-only (the Phase 2 `JobSnapshot` note) — a restored
completed row shows the request value, acceptable for a finished download.

---

## 6. Persistence and restore

`PersistedJob` needs no schema change — `attempt` round-trips from Phase 2.

- A job mid-backoff at quit persists `.queued` with its current `attempt` (the
  Phase 2 write-clamp maps `.queued` → `.queued`). On restore it re-enters
  `.queued attempt: N` and the scheduler runs it with no remaining backoff delay
  — relaunching is a reasonable "try now" signal, and `maxAutoRetries - N` of
  the auto budget survives.
- A restored `.failed` job is `JobState.failed(.unknown(raw: reason))` (Phase 2)
  — the original `ErrorClass` case is not recovered, and **retry does not
  re-classify it**. `FailurePresentation.for(.unknown(raw:))` offers `retry`, so
  the button works; the re-queue is itself the fresh attempt, and the next
  failure (if any) is classified from new stderr. Round-tripping the enum
  through its string description is not a stable contract and recovering the old
  case gains nothing.
- `integrityVerdict` and `actualQuality` are runtime-only and do not persist.

---

## 7. Always-on download flags

`YtDlpArguments.baseArgv` includes, on every invocation, the flags built from
`YtDlpTuning` (§4.6 — the values below are its `.default`):

```
--retries 3
--fragment-retries 10
--socket-timeout 30
--retry-sleep linear=1:10:2
--throttled-rate 100K
--file-access-retries 5
--no-part-hint
--sleep-requests 1
--sleep-interval 1
--max-sleep-interval 5
```

These are `yt-dlp`'s **in-invocation** retry and pacing controls — a fragment
403, a transient 5xx, throttle detection, a locked output file — all handled
inside one `yt-dlp` process. They are **bounded** so a hard failure surfaces to
Phase 4's classifier and `Backoff` within a knowable time rather than being
swallowed:

- `--retries 3` — three HTTP-level retries on a transient error, then a non-zero
  exit; the classifier runs and `maxAutoRetries` takes over. The two retry
  layers compose instead of one hiding the other. `--retries infinite` is
  deliberately **not** used — it hangs on a dead link and never reaches
  `recordExit`.
- `--fragment-retries 10` — fragments flake more than whole requests (CDN edge
  hiccups); ten with a short sleep is ~1 min worst case, still bounded.
- `--socket-timeout 30` — a dead connection **fails** in 30 s instead of
  hanging. This is what makes `networkDown` reachable at `recordExit`.
- `--retry-sleep linear=1:10:2` — 1 s, 3 s, 5 s … capped at 10 s between the
  internal retries; small, since Phase 4's outer `Backoff` is the real wait.
- `--throttled-rate 100K` — if the download speed stays below 100 KB/s `yt-dlp`
  aborts and exits; that abort classifies as `rateLimited` (§3.3 adds the
  throttle-abort signature) and takes the backoff schedule, matching the parent
  §7.1 "silent throttling" response.
- `--file-access-retries 5` — retry a locked output file (an AV scanner, Finder
  holding a handle); local and finite.
- `--sleep-requests 1` — 1 s between metadata / API requests (playlist
  expansion, format probes); politeness.
- `--sleep-interval 1 --max-sleep-interval 5` — a random 1–5 s pause before each
  download starts (parent §7.5's "small random `--sleep-interval`"), with no RNG
  in our code.

Worst case for `yt-dlp` to give up on a hard failure and exit ≈
`socket-timeout + 3 retries × ~5 s ≈ 45 s`, then Phase 4's layer classifies and
schedules. Predictable.

`--no-part-hint` (not `--no-part`) keeps the `.part` files on disk for resume
(Phase 2 depends on them) and only suppresses the hint line.

---

## 8. `EnvironmentProbe`

`EnvironmentReport` carries `ffprobe: ToolInfo?`, resolved as `ffmpeg`'s
directory + `/ffprobe`, verified executable and version-parsed
(`ffprobe -version`). It is not an independent `PATH` search — `ffprobe` ships
with `ffmpeg`.

`EnvironmentReport.isReadyForDownloads` stays `ytDlp != nil && ffmpeg != nil` —
a missing `ffprobe` degrades `IntegrityCheck` to `.skipped`, it does not block
downloads.

`EngineDependencies` carries `ffprobeURL: URL?` (default `nil`), threaded into
`IntegrityCheck`. `EngineDependencies.live(...)` derives it from the same
`ffmpeg` resolution, or a direct
`/opt/homebrew/bin/ffprobe` / `/usr/local/bin/ffprobe` probe matching the
`resolveYtDlp` pattern in `MediaGrabberApp`.

The every-launch re-probe is the Phase 2 path: `AppModel.onAppear` →
`refreshOnboardingState()` → `envProbe.probe()` → `needsOnboarding`, and a dep
vanishing mid-session trips `queueHalt = .depMissing`. Phase 4 adds only the
`ffprobe` field to the report.

---

## 9. `showLog`

`handleRowAction(id, .showLog)` calls `AppModel.showLog(jobID:)`:

- the `JobLog` path is `<jobLogDir>/<jobID>.log` — `AppModel` builds it from the
  id and the dir (a small `engine.jobLogDir` accessor, or `JobLog.defaultDir`),
- the file exists → `NSWorkspace.shared.open(url)` (the default text editor),
- the file is absent (evicted by the 200-cap, or deleted externally) → a notice
  `ConfirmationRequest` (`cancelTitle: nil`), copy
  `The log for this download is no longer available.`, and
  `LogEvent.showLogTargetMissing(jobID:)` (parallel to `revealTargetMissing`).

`showLog` is in `availableActions` for every state whose job has run (§3.4).

---

## 10. Testing (TDD — test before implementation for every unit)

**`GrabberKitTests`:**

- **`ErrorSignatures` / `classifyStderr`** — each signature string → its
  `ErrorClass`; the `MetadataProbe`-shared `unavailable` strings classify the
  same on the download side; a throttle-abort line → `rateLimited`; `Retry-After:
  90` on a 429 line → `.rateLimited(retryAfterSeconds: 90)`; an HTTP-date
  `Retry-After` → `.rateLimited(retryAfterSeconds: nil)`; classification order
  (network first, table next, `ERROR:` fallthrough, nil for an unmatched
  non-`ERROR:` line). `MetadataProbe`'s classifier reads the same
  `ErrorSignatures` table for its shared strings.
- **`FailurePresentation`** — every `ErrorClass` case has a non-empty
  `sentence`; `offeredActions` matches §3.2; `unknown(raw:)` sentence is the raw
  text; `isAutoRetryable` is a subset of the classes offering `retry`.
- **`ErrorClass.key`** — every case has a distinct token.
- **`Backoff`** — an injected jitter at fraction `1.0` returns the ladder value;
  `attempt` 1–5 → `30/60/120/300/600`; `attempt` 6+ → the last ladder entry;
  `retryAfter: 45` → `45`, no jitter; `retryAfter: 0` → the ladder;
  `retryAfter` above `backoffCap` → clamped; the real `random` path stays in
  `0 ... base` over many draws; a non-default `EngineTuning` ladder / cap is
  honoured.
- **`EngineTuning.resolved`** — no env keys → `.default`; each key parses into
  its field; a malformed int → that field keeps its default (and logs once);
  `MG_BACKOFF_LADDER="10,20,30"` → `backoffLadder == [10, 20, 30]`;
  `MG_YTDLP_RETRY_SLEEP` passes through as a string.
- **`IntegrityCheck`** — a fixture `ffprobe` JSON within tolerance → `.passed`,
  `actualQuality` from `height`; a materially-short duration → `.failed`; a
  > 10 s but < 5 % gap → `.passed`; a < 10 s absolute gap → `.passed`;
  `expectedDurationSeconds: nil` → `.skipped`, `actualQuality` still read; an
  audio-only JSON → `actualQuality` nil, duration verdict still computed;
  `ffprobeURL: nil` → `.skipped`, no spawn; a non-zero `ffprobe` exit →
  `.skipped`.
- **`DownloadEngine` retry path** (`FakeProcessRunner` + `FakeClock`):
  - an auto-retryable non-zero exit at `attempt 0`, `maxAutoRetries 3` →
    `attempt == 1`, `.queued`, a `deferStart` at `clock.now + <ladder>`,
    `jobDeferred(reason: .backoff(attempt: 1))` logged, no `.failed` snapshot;
  - the clock advances past the deadline → the job runs again;
  - three consecutive failures at `maxAutoRetries 3` → the fourth is terminal
    `.failed`, `attempt == 3`;
  - a non-retryable class (`geoBlocked`) → immediate terminal `.failed`, no
    `deferStart`, `attempt == 0`;
  - a failed `IntegrityCheck` on an exit-0 run → the `.incomplete` retry path,
    not `.completed`;
  - a `.skipped` verdict → `.completed`, `actualQuality` stored when the
    fixture had a video stream;
  - `maxAutoRetries` read live between failures.
- **`engine.retry(_:)` — resume path** — a `.failed(.networkDown)` job with a
  non-empty title-matching `.part` on disk → `.queued` at the tail, `attempt`
  **unchanged**, `.part` kept, `jobResumed` logged, no `jobRetried`; a resumed
  job that fails again continues the auto-retry path from its prior `attempt`.
- **`engine.retry(_:)` — retry path** — a `.failed(.rateLimited())` job (class
  not in the resume set) → `attempt` → 0, `.part` deleted, `.queued` at the
  tail, `jobRetried` logged; a `.failed(.incomplete)` job with **no** `.part` →
  the retry path (no `.part` to resume); `integrityVerdict` / `actualQuality`
  cleared on both paths; no `deferStart` on either.
- **`engine.retry(_:)` — guards** — a no-op on a `.failed` job whose class omits
  `retry`; a no-op on a non-`.failed` job.
- **`availableActions`** — `.failed(.rateLimited())` includes `retry`, `showLog`,
  `remove`, `openInBrowser`, excludes `pause` / `forceStart`;
  `.failed(.geoBlocked)` excludes `retry`; `.cancelled` includes `showLog`;
  `.queued` / `.probing` exclude it.
- **`YtDlpArguments`** — `build` emits every §7 flag from `YtDlpTuning` in
  `baseArgv`, before the URL; a non-default `tuning` changes the emitted values;
  `--retries infinite` never appears; `redacted` still diverges only on proxy
  userinfo; the existing argv fixtures updated for the new tokens.
- **`EnvironmentProbe`** — `ffmpeg` present with a sibling `ffprobe` →
  `report.ffprobe` resolved; `ffmpeg` present, no sibling → `report.ffprobe`
  nil, `isReadyForDownloads` still true; `ffmpeg` absent → both nil.
- **`LogEvent`** — `jobDeferred(reason: .backoff(attempt: 2))` serialises
  `{ reason: "backoff", attempt: "2", until: <iso> }`; `jobRetried(id:)` →
  key `job.retried`, category `.engine`; `showLogTargetMissing(jobID:)` →
  key `show_log.target_missing`, category `.ui`.
- **Persistence** — a `.queued attempt: 3` job round-trips with `attempt == 3`;
  a `.failed` job restores `.failed(.unknown(raw:))` and its presentation offers
  `retry`; a `retry` on the restored job (class `.unknown`, `.part` present) →
  the resume path, class stays `.unknown(raw:)` until a fresh failure.

**`AppUnitTests`:**

- **`RowModel.status`** — a `.queued` job, `attempt 2`, `maxAutoRetries 5` →
  `Retrying — attempt 3 of 5`; `attempt 0` → `Queued · #N`; a `.failed` job →
  `Failed — <sentence>` from `presentation`.
- **`RowModel.quality`** — `actualQuality` nil → request value; `"720p"` with a
  1080p request → `1080p → 720p`; `"1080p"` with a 1080p request → `1080p`.
- **`AppModel.handleRowAction`** — `.retry` → `engine.retry(id)`; `.showLog`
  with an existing file → `NSWorkspace.open` (via a fake sink); `.showLog` with
  a missing file → the notice `ConfirmationRequest` and `showLogTargetMissing`
  logged.
- **`RowStore.apply` plumbing** — `maxAutoRetries` passed into `apply(_:)`
  reaches `RowModel.status`; `RowStore` has no `Preferences` dependency.
- **Row-action gating** — the Retry button's enabled state tracks
  `availableActions` (a `.failed(.geoBlocked)` row → disabled).

**Not tested:** real `ffprobe` execution (fixture JSON only), real `NSWorkspace`
calls, the deferred live countdown (not built), SwiftUI rendering.

**Manual smoke** (leaf checklist, added by the plan):

- Force a classified non-recoverable failure (a private or removed URL) → the
  row shows the plain sentence, the Retry button disabled, `showLog` opens the
  raw log.
- Disconnect mid-download → within ~45 s the row shows
  `Retrying — attempt 1 of N`, retries after the backoff, and on repeated
  failure stops at the budget; the Retry button then resumes from the `.part`.
- A normal completion → the Quality column shows the real resolution
  (`1080p → 720p` when the site served lower), the integrity check passes
  silently.
- Truncate a download (kill the connection near the end, or set a tiny
  `MG_YTDLP_SOCKET_TIMEOUT`) → the job fails `The download kept ending early`
  and auto-retries.
- Set `MG_BACKOFF_LADDER=2,4,6` in the environment → the retry waits shorten
  accordingly (proves the tuning path).
- Rename `ffprobe` away → downloads still complete, Quality shows the request
  value, no integrity failures.
- `showLog` on a job whose log was evicted → the "no longer available" notice.

---

## 11. Definition of done

- Everything in §1 "in this phase" built to final-app form.
- `xcodebuild ... test` green; `swiftformat --lint` + `swiftlint --strict` clean.
- The manual smoke checklist passes on a real machine.
- Parent spec §12.1 Phase 4 stub and §12.2 rows updated to reflect the shipped
  surface; the Phase 6 stub gains the live-countdown hint (§12).
- Commit tagged `phase-4`.

---

## 12. Parent-spec edits (same pass)

- **§7.5** — replace the `--retries infinite --fragment-retries infinite …`
  line with the bounded set (`--retries 3`, `--socket-timeout 30`, …) sourced
  from `YtDlpTuning`, and the rationale (a hard failure must exit `yt-dlp` and
  reach the classifier, not hang). *Done in this pass.*
- **§12.1 Phase 4 stub** — the shipped surface: generic `ErrorClass`
  classification with `FailurePresentation`, the live `retry` / `show-log`
  actions, the resume-vs-retry split on the Retry button, the `maxAutoRetries`
  budget, `Backoff` as the first `deferStart` caller, `EngineTuning` as the
  env-overridable home of every retry / pacing number, `IntegrityCheck` feeding
  `actualQuality` into the Quality column, `EnvironmentReport.ffprobe`. *Done.*
- **§12.1 Phase 6 stub** — the hint: *the Status cell's live `m:ss` backoff /
  cooldown countdown lands here; Phase 4 shows a static `attempt N of M` and
  leaves `JobSnapshot.cooldownUntil` nil.* *Done.*
- **§9** — `ErrorClass` staging reworded: the enum ships whole (Phase 1), its
  emit paths and failure UI stage; Phase 4 adds the classifier signatures and
  the `FailurePresentation` model. *Done.*
- **§12.2 `ErrorClass` row** — the generic-set signatures plus
  `FailurePresentation` + `ErrorClass.key` are Phase 4; Phase 5 wires
  `cookieReadFailed`; Phase 7 adds the YouTube cases as new `switch` arms.
  *Done.*
- **§12.2 row-action bar row** — `retry` and `showLog` live (the `.failed` arm
  reads `presentation.offeredActions`); only `retryWithCookies` stays gated
  (Phase 5). *Done.*
- **§12.2 `JobSnapshot` row** — already names Phase 4 for `attempt`,
  `integrityVerdict`, `actualQuality`; no edit needed.
- **§12.2 scheduler-loop row** — already names Phase 4 as the first `deferStart`
  caller; no edit needed.
- No Phase 5 / 7 assumption changes — the `deferStart` seam, the
  `SchedulerInput` struct, and `YtDlpArguments.build(for:options:)` all extend
  as those phases assume (the new `tuning:` parameter is additive and
  defaulted).
