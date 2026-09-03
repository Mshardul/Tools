# Rate limiting and circuit breaker (Phase 6)

**Status:** design complete. Plan: not yet written. Parent spec:
`docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §7.4, §7.6,
§7.8, §12.1.
Phase 2 (shipped): `docs/superpowers/specs/queue-foundation.md`.
Phase 3 (shipped): `docs/superpowers/specs/archived/2026-08-31-media-grabber-phase-3.md`.
Phase 4 (shipped): `docs/superpowers/specs/archived/2026-09-01-media-grabber-phase-4.md`.
Phase 5 (shipped): `docs/superpowers/specs/archived/2026-09-02-media-grabber-phase-5.md`.
Phase 1 (shipped): `docs/superpowers/specs/archived/core-download-pipeline.md`.

Phases 1–5 built the download pipeline, the engine-owned queue and scheduler, the
Downloads table with its row-action bar, per-job raw logs, persistence, the
Preferences editor, retry / error classification with per-job backoff, and
opt-in browser cookies. Phase 6 makes the app respond to a site pushing back.
When YouTube (or any host) returns HTTP 429 or silently throttles a transfer,
the app slows down for that host, escalates through a cooldown ladder, and — if
the host keeps refusing — trips a per-host circuit breaker that halts auto-retry
until the user intervenes. Concurrency starts cautious and adapts. A dropped
network connection parks downloads instead of burning their retry budgets.

Everything here is built to its final-app form. `RateHost`, `RateLimiter`,
`RatePolicy`, `HealthController`, and the wired `WarningBanner` / `HealthStrip`
are the shapes the app keeps. Phase 7 layers YouTube-specific hardening on the
same per-host state and the same banner / strip. Phase 10 adds the engine-
freshness chip to the `HealthController` output. Neither relayouts anything here.

---

## 1. Scope

**In this phase:**

- `RateHost` — a normalized per-site key derived from a job's URL, with an alias
  table folding the YouTube subdomains into one bucket.
- `RateLimiter` — an engine-owned value type holding per-host `RateState`, the
  global adaptive concurrency cap, and the clean-streak counter.
- `RatePolicy` — the pure state-machine core: strike / clean-success / user-reset
  events map an old `RateState` to a new one.
- The per-host state machine: `normal → cooldown → circuitOpen`, with the
  cooldown ladder reusing Phase 4's `Backoff`.
- Adaptive concurrency: a single global cap that starts at 2, ramps up on clean
  streaks, and drops to 1 on any strike. Feeds the Phase 2 scheduler through one
  new input field — the loop is not rewritten.
- Per-host cooldown as the second `deferStart` caller (Phase 4's backoff was the
  first).
- `NetworkPathMonitoring` — an `NWPathMonitor` wrapper that parks downloads when
  the connection drops and resumes them when it returns, without consuming retry
  attempts.
- `QueueHaltReason` gains `.circuitOpen` (a derived "everything startable is
  circuit-blocked" summary) and `.networkDown` (a hard global gate).
- `QueueSnapshot` gains `hostRateSummary`; `JobSnapshot` gains `rateHost` and
  populates the Phase 2-shelled `cooldownUntil`.
- `HealthController` — produces the `HealthStrip` chip array from live state.
  Ships the online/offline chip and the per-host cooldown chip. `ChipInteraction`
  gains a `.popover` case for the cooldown chip.
- `WarningBanner` — the `circuitOpen`, `networkDown`, and `depMissing` banner
  content wired, with the floating banner no longer able to hide the last table
  rows.
- The Status cell's live `m:ss` countdown for a cooling or backing-off row.
- `--concurrent-fragments` gated on host `RateState` (§5.6) — the download-level
  half of §7.6's adaptive pacing, distinct from the engine's job-count cap.
- `EngineTuning` gains the five Phase 6 numbers, all `MG_*`-overridable, no UI.
- The §11.3 429 smoke checklist.

**Deferred (hints in their phase):**

- Per-host adaptive concurrency — `apps/media-grabber/ticket-backlog.md`.
- The engine-freshness chip — Phase 10 (it needs the yt-dlp staleness check).
- A first-run hint that the app ramps concurrency cautiously — Phase 11 polish.
- The VPN hint on a bot-check failure — Phase 7 (§7.8).

**Not touched:** Phase 4's per-job backoff for non-rate-limit failures, the
cookie subsystem, the Preferences UI (no new controls), persistence schema
(rate state is in-memory only).

---

## 2. `RateHost`

`GrabberKit/RateLimiting/RateHost.swift`.

```swift
public struct RateHost: Hashable, Sendable, CustomStringConvertible {
    public let canonical: String
    public var description: String { canonical }

    public static let unresolved = RateHost(canonical: "unresolved")

    public init(urlString: String) { ... }
}
```

`init(urlString:)` is total — it never fails. It takes the URL string's host
(`URLComponents(string:)?.host`), lowercases it, strips a leading `www.`, then
applies the alias table. A string with no parseable host resolves to
`.unresolved` — every job always has a bucket.

**Alias table** — a code constant, not tunable:

| Raw host | Canonical |
|---|---|
| `youtube.com`, `youtu.be`, `m.youtube.com`, `music.youtube.com`, `gaming.youtube.com` | `youtube` |
| anything else | its own `host` after the `www.` strip |

Rate limiting is applied per IP by the site, so the YouTube properties share one
bucket. `generic`-extractor sites (a blog hosting a video) each get their own
canonical host, so one site's circuit never blocks another.

`RateHost` is not `Codable` — rate state is not persisted (§5.8) and
`JobSnapshot` is not persisted.

---

## 3. `RateState` and the state machine

```swift
public enum RateState: Sendable, Equatable {
    case normal
    case cooldown(until: Date, strikes: Int)
    case circuitOpen(since: Date, strikes: Int)
}
```

A host absent from the `RateLimiter`'s dictionary is `normal` and is not stored.

### 3.1 Transitions

Driven by three events (`RatePolicyEvent`):

- `.strike(retryAfter: Int?)` — a download for this host exited `.rateLimited`
  (§5.1). `retryAfter` is the server's `Retry-After` when yt-dlp surfaced it.
- `.cleanSuccess` — a download for this host reached `.completed`.
- `.userReset` — the user pressed "Retry now" (§7.3).

```
normal ──strike──▶ cooldown(until: now + delay(1), strikes: 1)

cooldown(strikes: n) ──strike (after until has passed)──▶
    if n + 1 >= circuitStrikeThreshold:
        circuitOpen(since: now, strikes: n + 1)
    else:
        cooldown(until: now + delay(n + 1), strikes: n + 1)

cooldown ──cleanSuccess──▶ normal          (strikes drop to 0)

circuitOpen ──cleanSuccess──▶ (cannot happen — no job for this host
                               starts while the circuit is open)

circuitOpen ──userReset──▶ normal          (strikes drop to 0)
cooldown    ──userReset──▶ normal          (strikes drop to 0)
```

- `delay(k)` is `Backoff.delay(attempt: k, retryAfter:, tuning:)` — the Phase 4
  full-jitter ladder (`attempt` is 1-based; the ladder is 30 → 60 → 120 → 300 →
  600, then holding at the cap), fed the **host strike count** in place of a
  job's attempt count. An explicit `Retry-After` still wins, still capped. So the
  first strike parks the host for ~30 s, the fourth (at the default threshold)
  trips the circuit instead of parking.
- **A strike while `until` has not yet passed** keeps the same deadline and
  strike count — the host is already parked; a second failure from a job that
  slipped through does not double-escalate. (In practice the adaptive cap is 1
  and jobs are `deferStart`-parked, so this is rare.)
- **"Consecutive"** means "strikes with no `.completed` for this host in
  between." A clean success resets the count to 0, so the count only climbs when
  the host is genuinely, repeatedly refusing. The circuit therefore trips only
  on `circuitStrikeThreshold` (default 4) straight failures.
- **`circuitOpen` does not auto-recover.** No timer. The parent design §7.4 is
  explicit — "no auto-retry … The user can force a retry." Recovery is
  `.userReset` only (§7.3).

### 3.2 `RatePolicy`

`GrabberKit/RateLimiting/RatePolicy.swift` — pure, stateless.

```swift
public enum RatePolicy {
    public static func next(
        state: RateState,
        event: RatePolicyEvent,
        now: Date,
        tuning: EngineTuning
    ) -> RateState
}
```

Every ladder / threshold test targets this with an injected `now` and no engine.

---

## 4. `RateLimiter`

`GrabberKit/RateLimiting/RateLimiter.swift` — a `struct` with `mutating`
methods, stored on `DownloadEngine`. Not an actor: it runs on the engine's
isolation, so its reads on every `evaluateSchedule()` are synchronous and free,
and a strike mutates host state, the adaptive cap, and re-queues a job in one
synchronous block that emits one consistent snapshot.

```swift
struct RateLimiter {
    private var states: [RateHost: RateState] = [:]
    private(set) var adaptiveCap: Int
    private var cleanStreak = 0
    let tuning: EngineTuning

    init(tuning: EngineTuning, preferencesCap: Int)

    // Outcomes
    mutating func recordStrike(host: RateHost, retryAfter: Int?, now: Date)
    mutating func recordCleanSuccess(host: RateHost, now: Date)

    // Queries
    func state(for host: RateHost) -> RateState        // .normal if absent
    func blocked(host: RateHost, now: Date) -> Bool    // cooling & until > now, or circuitOpen
    var circuitOpenHosts: Set<RateHost>
    func cooldownDeadline(for host: RateHost) -> Date?

    // User actions
    mutating func resetCircuit(host: RateHost)
    mutating func resetAllCircuits()

    // Concurrency
    mutating func setPreferencesCap(_ cap: Int)        // re-clamp on a live pref change
}
```

- `recordStrike` calls `RatePolicy.next(… .strike …)`, then sets
  `adaptiveCap = 1` and `cleanStreak = 0`.
- `recordCleanSuccess` calls `RatePolicy.next(… .cleanSuccess …)`, then
  increments `cleanStreak`; at `cleanStreak == tuning.cleanStreakToRaise` it
  does `adaptiveCap = min(adaptiveCap + 1, preferencesCap)` and resets the
  streak to 0.
- `adaptiveCap` is always clamped to `[1, preferencesCap]`. A live Preferences
  cap change re-clamps immediately (a raise does **not** jump the adaptive cap
  to the new ceiling — it keeps climbing from where it is).

### 4.1 Adaptive concurrency

- Starts at `min(tuning.adaptiveConcurrencyStart, preferencesCap)` (default 2).
- `+1` per `tuning.cleanStreakToRaise` (default 5) consecutive `.completed`
  downloads from **any** host, up to the Preferences cap.
- `→ 1` on **any** strike from **any** host.
- The cap is global. Rate limiting is mostly per-IP, so a strike anywhere means
  "this IP is being watched" and backing everything off is the right response.
  Per-host caps are a backlog item.
- The scheduler reads `rateLimiter.adaptiveCap` in place of the raw
  `preferences.maxConcurrentDownloads` (§6.1).

---

## 5. Engine wiring

### 5.1 What counts as a strike

Only `ErrorClass.rateLimited`. Phase 4 already folds both cases into it:

- HTTP 429 / "Too Many Requests" — matched in stderr by `ErrorSignatures`.
- A `--throttled-rate` abort — yt-dlp exits when the transfer speed drops below
  the floor; `ProgressParser.classifyStderr` maps this to `.rateLimited`.

Nothing else strikes. `networkDown`, `incomplete`, `unknown`, `diskFull`, a bot
check — none touch host rate state; they take Phase 4's per-job path unchanged.
This keeps the circuit trustworthy: when it trips and the banner says "YouTube
keeps rate-limiting you," that is literally what happened.

As part of this phase, confirm `ErrorSignatures.rateLimited` covers the common
2026 429 phrasings and the throttle-abort line; a gap is a one-line table
addition, in scope here.

### 5.2 `recordExit` split

`DownloadEngine+Mutations.swift`. On an auto-retryable failure with
`attempt < maxAutoRetries`:

- **`errorClass == .rateLimited`** → the host-rate path:
  1. `rateLimiter.recordStrike(host: job.rateHost, retryAfter:, now:)` — this
     also drops the adaptive cap to 1.
  2. `job.attempt += 1`, `job.progress = nil`.
  3. **Only the struck job** changes state now:
     - host went to `cooldown` (deadline `T = rateLimiter.cooldownDeadline(for:
       host)`): `job.state = .cooldown(until: T)`, `job.cooldownUntil = T`,
       `deferStart(job.id, until: T)`.
     - host tripped the **circuit**: `job.state = .queued`,
       `job.cooldownUntil = nil`, no `deferStart`.
  4. **The host's other `.queued` jobs are not mutated.** They are held by the
     scheduler's `blockedHostIDs` gate (§5.3), which covers both a cooling and a
     circuit-open host, and their Status cell reads the situation from
     `hostRateSummary` (§7.4) — the same no-churn treatment a circuit-open
     host's jobs get. A 500-row playlist striking once is **one** job mutation,
     not 500.
  5. `emitSnapshot()`, `evaluateSchedule()`.
- **any other auto-retryable class** (`networkDown`, `incomplete`, `unknown`) →
  Phase 4's `reQueueForBackoff` unchanged, except it now also sets
  `job.cooldownUntil` to the backoff deadline (Phase 4 left it nil). The job
  stays `.queued` — a per-job backoff is not a `.cooldown` (that state means
  "this host is rate-limited", §7.5).

So `.cooldown(until:)` is entered by **at most one job per host at a time** — the
one whose exit caused the current strike. Everything else for that host waits as
`.queued` behind `blockedHostIDs`. Only one deferral path fires per failure, so
`deferStart` (last-write-wins, unchanged) never composes two live reasons for one
job. The invariant — **at most one deferral reason is live per job** — is a
documented contract, not enforced in `deferStart`. `DeferReason` gains
`.hostCooldown(host: String, strikes: Int)`.

### 5.3 The scheduler

A rate-limited host's `.queued` jobs are held by one new `SchedulerInput` field:

```swift
var blockedHostIDs: Set<UUID>   // .queued jobs whose RateHost is cooling (until > now) or circuitOpen
```

`Scheduler.nextDownloads` gains one filter clause parallel to the existing
`deferredIDs` check — a job is startable only if `!blockedHostIDs.contains(job.id)`.
`Scheduler` gains no `RateHost` knowledge. `evaluateSchedule()` builds the set:
for each `.queued` job, `rateLimiter.blocked(host: job.rateHost, now:)`.

The one `.cooldown(until:)` job per host (§5.2 step 3) is not `.queued`, so it is
not a scheduler candidate and not in `blockedHostIDs` — its `deferStart` timer
is what brings it back (§5.4).

The `cap` field of `SchedulerInput` becomes `rateLimiter.adaptiveCap`. **The
loop body is unchanged** — one more `Set<UUID>` filter and a different `Int` for
`cap`.

### 5.4 `deferStart` — second caller, and the resume

Host cooldown parks the one struck job through the existing Phase 2 seam, with
deadline `T` (§5.2 step 3).

When the deferral timer fires at `T`, `fireDueDeferrals()` (Phase 2,
`+Deferral.swift`) gains one step before its `evaluateSchedule()` call: a
`.cooldown(until:)` job whose `until <= now` returns to `.queued` (in place —
order preserved), `cooldownUntil = nil`. `RateState` is unchanged here — the host
stays in `cooldown` with its strike count until a `.completed` arrives; only the
job moves back so it becomes a scheduler candidate. (Phase 4's backoff jobs are
already `.queued` throughout their wait, so this step is a no-op for them.)

Once that job is back to `.queued`, `blockedHostIDs` no longer contains it (the
cooldown `until` has passed), so the scheduler can start it — and, because the
adaptive cap is 1, only it. The host's other `.queued` jobs also unblock at `T`
(same `blocked(host:now:)` check), but the cap-1 limit means they wait for the
first to finish. The strike count clears only on a `.completed`, so a
still-rate-limited host keeps being eased in one at a time. If that first job
strikes again before completing, §5.2 runs again: a fresh strike, a new
`.cooldown(until: T2)` on that job, the cap back to 1, the rest still gated.

`+Deferral.swift` gains `cancelDeferral(_ id: UUID)` — remove the job's entry,
re-arm the timer. Used if the struck job's strike **tripped the circuit** rather
than setting a cooldown (§5.2 step 3, circuit branch): that job is `.queued` with
no deferral, so any stale entry for it is cancelled.

### 5.5 Network monitor

`GrabberKit/RateLimiting/NetworkPathMonitoring.swift`:

```swift
public protocol NetworkPathMonitoring: Sendable {
    var isOnline: Bool { get async }
    var stream: AsyncStream<Bool> { get }
}
```

Live impl wraps `NWPathMonitor` on a dedicated dispatch queue and emits
**debounced** booleans:

- goes **offline** after `tuning.networkOfflineGraceSeconds` (default 2) of
  continuous `.unsatisfied` — absorbs momentary drops.
- goes **online** after `tuning.networkOnlineSettleSeconds` (default 2) of
  continuous `.satisfied` — absorbs a flapping connection (bad wifi, AP
  switching, sleep/wake).

No reachability probe. A satisfied path that is actually a captive portal will
let jobs start and fail once against a dead link; that failure classifies as
`.networkDown`, takes Phase 4's bounded backoff (yt-dlp's own `--socket-timeout
30` keeps it fast), and auto-recovers when real internet arrives. Avoiding that
one wasted attempt is not worth an unsolicited network request in a
privacy-mandatory app (§8.5).

Injected via `EngineDependencies`. The engine subscribes in a long-lived `Task`
alongside the deferral task; `shutdown()` cancels it.

**Offline transition** (debounced):

- `queueHalt = .networkDown` — a **hard global gate**, checked in the
  `evaluateSchedule()` guard exactly like `.depMissing`.
- Every `.running` / `.probing` job: SIGTERM its child, set `.waitingForNetwork`,
  **keep `attempt` and the `.part` file**.
- `.queued` jobs stay `.queued`. The halt stops them starting; restating 500
  playlist rows as `.waitingForNetwork` on a wifi blip is churn the banner
  already covers.

**Online transition** (settled):

- If `queueHalt == .networkDown`, clear it.
- `.waitingForNetwork` jobs → `.queued`, moved to the tail (consistent with
  Phase 2 resume and Phase 4 retry), `attempt` unchanged.
- `evaluateSchedule()`. No attempt was burned.

### 5.6 `--concurrent-fragments` gated on host state

`YtDlpArguments.build` (Phase 3 threads `--proxy` / `-4` / `--limit-rate` through
it) gains `--concurrent-fragments`: **4** when the job's host `RateState` is
`.normal`, **1** otherwise. `DownloadEngine.launchDownload` reads
`rateLimiter.state(for: job.rateHost)` at spawn (it already reads `preferences`
there) and passes the count into the argument builder. Value is
`tuning`-controlled — `EngineTuning` gains `concurrentFragmentsNormal` (4) /
`concurrentFragmentsThrottled` (1), keys `MG_CONCURRENT_FRAGMENTS_NORMAL` /
`MG_CONCURRENT_FRAGMENTS_THROTTLED`. This is the download-level pacing of §7.6,
independent of the engine's job-count adaptive cap (§4.1) — a host that just
recovered from a cooldown still starts its next job with `--concurrent-fragments
1` until its `RateState` is back to `.normal` (which needs a `.completed`, §3.1).

Redaction: `--concurrent-fragments <n>` is not sensitive; it appears verbatim in
the job log.

### 5.7 `revalidate()`

Extended. Currently re-probes dependencies and clears `.depMissing`. Phase 6
adds: `rateLimiter.resetAllCircuits()`, then re-evaluate. This is what the
`circuitOpen` banner's "Retry now" calls.

### 5.8 Rate state is not persisted

The engine builds a fresh `RateLimiter(tuning:, preferencesCap:)` every launch.
A restored `.queued` job that was mid-cooldown or `.waitingForNetwork` last
session starts under `normal` host state and the cautious cap-2 default. No
restore path. Cooldowns are transient (30–600 s) and a quit-relaunch gap makes
them stale; the adaptive cap starting at 2 every launch is already the intended
cautious default; a persisted `circuitOpen` would relaunch the user into a bare
`queueHalt` with no session context. If real use shows people quit-relaunch to
dodge rate limits, `RateLimiter` is a value type and serializing it is a clean
additive change later.

---

## 6. Queue halt and the circuit

### 6.1 `QueueHaltReason`

```swift
public enum QueueHaltReason: Sendable, Equatable {
    case depMissing
    case networkDown
    case circuitOpen
}
```

- `.depMissing` (Phase 2) and `.networkDown` (§5.5) are **hard gates** —
  `evaluateSchedule()` returns early when either is set.
- `.circuitOpen` is a **derived summary**, computed in `buildSnapshot()`, never
  checked in the scheduler guard. It is set when **at least one `.queued` job's
  host circuit is open** and **no job is `.running` or `.probing`** and **the
  scheduler would start nothing** (every remaining `.queued` job is
  circuit-blocked; the non-circuit-blocked ones, if any, are all `.cooldown` or
  deferred). In plain terms: a circuit is open and it is the reason nothing is
  downloading. It drives the banner and nothing else — if a job for a healthy
  host is running or could start, `.circuitOpen` is not set even though a
  circuit is open somewhere (the cooldown chip covers that host instead).

**Precedence** (only one banner shows): `.depMissing` > `.networkDown` >
`.circuitOpen`.

### 6.2 Why the circuit is per-host, not global

A tripped YouTube breaker must not stop a queued Vimeo download — mixed-site
queues arrive with playlists and matter more over time. So the circuit lives
per host in `RateLimiter`, and the scheduler's `blockedHostIDs` gate (§5.3) is
what stops a circuit-open host's jobs. `queueHalt.circuitOpen` is only the
UI-level "nothing is moving and the reason is a breaker" signal.

In the common single-host queue (a YouTube-only session), every startable job is
YouTube, so a YouTube breaker trip makes `queueHalt.circuitOpen` true and the
banner shows — it behaves exactly as if the circuit were global, with no
special-casing.

### 6.3 `QueueSnapshot.hostRateSummary`

```swift
public struct HostRateDisplayState: Sendable, Equatable {
    public let state: RateState                 // cooldown or circuitOpen
    public let lastErrorKey: String?            // ErrorClass.key of the last strike
}

// on QueueSnapshot:
public let hostRateSummary: [RateHost: HostRateDisplayState]
```

Only hosts in `cooldown` or `circuitOpen` appear. Feeds the banner (§7.2), the
cooldown chip and its popover (§7.1), the Status cell (§7.4), and the derived
`queueHalt.circuitOpen`.

### 6.4 `JobSnapshot`

- Gains `rateHost: RateHost`, populated in `buildSnapshot` /
  `job.snapshot(availableActions:)` from `job.request.url`. One `URLComponents`
  parse per job per structural snapshot (not on progress ticks).
- `cooldownUntil: Date?` (Phase 2-shelled, nil until now) is populated on the
  one struck `.cooldown` job **and** — retroactively — on a Phase 4 backoff
  `.queued` job (§5.2). The host's other queued jobs keep `cooldownUntil == nil`
  and get their countdown from `hostRateSummary` (§7.4).

---

## 7. UI

### 7.1 `HealthController` and the strip

`Sources/App/Chrome/HealthController.swift` — `@MainActor @Observable`.

```swift
@Observable
final class HealthController {
    private(set) var chips: [HealthChip] = []
    func update(snapshot: QueueSnapshot, isOnline: Bool, now: Date)
}
```

`AppModel` owns one, feeds it every snapshot plus the latest network state, and
`AppModel.healthChips` returns `healthController.chips`.

**Chips produced:**

1. **online / offline** — always present. `dot: .ok` + `"online"` when up;
   `dot: .attention` + `"offline"` when down. `interaction: .none`.
2. **cooldown** — present only when `hostRateSummary` is non-empty. **One chip
   for all affected hosts:**
   - one host: `"YouTube — 2:14"` (the `— m:ss` is a live `TimelineView`
     suffix, §7.4) or `"YouTube — paused"` when its circuit is open.
   - several: `"2 sites cooling down"`, no countdown in the label.
   - `dot: .attention`. `interaction: .popover(PopoverContent)`.

The engine-freshness chip is **Phase 10** (it needs the yt-dlp staleness check).
Phase 6 builds `HealthController` and the strip's dynamic `ForEach(chips)` to
final form; Phase 10 emits one more chip from the controller — no relayout, the
same way Phase 4/5 added row actions to a `Set` the engine emits.

**`ChipInteraction`** gains a case (additive; Phase 2's `.none` / `.refresh`
untouched, Phase 7's bot-check chip uses `.refresh`):

```swift
enum ChipInteraction {
    case none
    case refresh(@Sendable () async throws -> Void)
    case popover(PopoverContent)
}

struct PopoverContent {
    let title: String
    let rows: [PopoverRow]
    let footerActionTitle: String?
    let footerAction: (@Sendable () async -> Void)?
}

struct PopoverRow: Identifiable {
    let id: String
    let label: String            // host name
    let detail: String           // "Cooling down — 2:14" / "Rate-limited — paused"
                                 //   + ", concurrency reduced to 1" when a strike lowered the cap
    let actionTitle: String?     // "Retry now"
    let action: (@Sendable () async -> Void)?
}
```

The cooldown chip's popover: one `PopoverRow` per affected host with a per-host
"Retry now" (`resetCircuit(host:)` for an open circuit; for a plain cooldown the
row has no action — waiting is the only option), and a `"Retry all"` footer
(`revalidate()`). The current reduced concurrency is stated in a row's `detail`
when a strike lowered it — this is the only place the adaptive cap surfaces in
the UI.

### 7.2 `WarningBanner`

`BannerContent` is wired for three reasons, chosen by `queueHalt` precedence
(§6.1). A plain cooldown gets **no** banner — the chip covers it.

| `queueHalt` | Text | Button |
|---|---|---|
| `.depMissing` | (Phase 2 — onboarding takeover, unchanged) | — |
| `.networkDown` | "No internet connection — downloads paused. They'll resume automatically." | (no button) |
| `.circuitOpen` | "Downloads from {host} keep getting rate-limited. Wait a while, add browser cookies in Preferences, or turn off a VPN." | "Retry now" → `revalidate()` |

When several hosts have open circuits at once, the text says "{n} sites keep
getting rate-limited." "Retry now" resets all of them.

**Floating-banner fix.** The banner already floats over the page
(`MainWindow` is a `ZStack(alignment: .bottom)` with `WarningBanner` last), so it
is never scrolled off with the table. The gap: when the table is scrolled to the
end, the floating banner covers the last rows. Fix — the banner publishes its
rendered height (an `onGeometryChange` / layout-preference read); `MainWindow`
holds it in `@State`; the `page` content takes a bottom safe-area inset of that
height plus the banner's margins **when `bannerContent != nil`**, zero
otherwise. The height is measured, so a wrapped-text banner still lets the last
row clear. This wiring lands with Phase 6 because Phase 6 is the first phase that
sets `bannerContent` non-nil.

### 7.3 "Retry now"

Resets the affected host(s) fully: `circuitOpen` (or `cooldown`) → `normal`,
strikes → 0. The global adaptive cap is left where it is (probably 1 from the
strikes; it climbs on clean successes). The banner button calls `revalidate()`
(all circuits); the popover's per-host row calls `resetCircuit(host:)`.

A reflexive "Retry now" that fixed nothing lands the host back in `cooldown` on
the first fresh 429 and re-trips after `circuitStrikeThreshold` more — but with
the adaptive cap at 1 and jobs parked behind the ladder, the IP is being probed
one download at a time, which is the gentlest possible retry. "Retry now" means
retry now; it does not half-reset.

### 7.4 Status cell and the countdown

`RowModel` learns its job's host from `snapshot.rateHost`. `RowModel.statusText`
(still cached, still recomputed on `patch` only — **no** per-second recompute)
holds the semantic prefix:

| Job state | Extra condition | `statusText` prefix | Countdown? |
|---|---|---|---|
| `.cooldown(until:)` | — | "Cooling down" | yes — from `cooldownUntil` |
| `.queued` | `rateHost` in `hostRateSummary` as `cooldown` | "Cooling down" | yes — from the summary's deadline |
| `.queued` | `rateHost` in `hostRateSummary` as `circuitOpen` | "Rate-limited — paused" | no |
| `.queued` | `attempt > 0`, `cooldownUntil` in the future (Phase 4 backoff) | "Retrying" | yes — from `cooldownUntil` |
| `.waitingForNetwork` | — | "Waiting for network" | no |
| anything else | — | (Phase 4 logic unchanged) | — |

Rows 1 and 2 both read "Cooling down" — the one struck job (state `.cooldown`)
and the host's other `.queued` jobs (blocked, host in the summary) look
identical to the user, which is correct: the whole host is cooling. Only the
struck job actually carries the `.cooldown` state and its own `deferStart`.

So `RowModel` needs `hostRateSummary` alongside the job's snapshot — `RowStore`
passes it into `patch` the way it already passes `maxAutoRetries`.

The **live `— m:ss` suffix** is a view concern. The Status cell and the cooldown
chip each wrap their countdown in `TimelineView(.periodic(from: .now, by: 1))`,
active only when there is a future `cooldownUntil` (cell) or `hostRateSummary`
deadline (chip). Inside, `deadline - context.date` is formatted by a shared
`CountdownFormat.mmss` helper. `TimelineView` auto-pauses off-screen, so a
1000-row playlist with one cooling host re-renders only the visible cooling
cells, once a second, with zero model churn. A `circuitOpen` row's
"Rate-limited — paused" has no countdown (no deadline).

### 7.5 `JobState` — already shelled

`.cooldown(until:)` and `.waitingForNetwork` exist from Phase 2 with their
`availableActions` arms and RowStore chip / filter handling. Phase 6 makes them
real:

- **`.cooldown(until: T)`** — the single job per host whose exit caused the
  current strike (§5.2 step 3). Carries the host deadline `T`; returns to
  `.queued` when `T` passes (§5.4). The host's *other* queued jobs stay
  `.queued` and are gated by `blockedHostIDs` — they show "Cooling down" via
  `hostRateSummary` (§7.4) without a state change, so a big playlist striking
  once is one mutation, not N. A per-job Phase 4 backoff is **not** this state
  either — that job stays `.queued` with `cooldownUntil` set. `.cooldown` means
  exactly "this job's exit just rate-limited its host."
- **`.waitingForNetwork`** — a job that was running when the connection dropped
  (§5.5). Not entered for `.queued` jobs during an outage.

A `circuitOpen`-host job stays `.queued` — there is no timed wait, so `.cooldown`
would misrepresent it; the derived `statusText` and the banner carry the
meaning. No `JobState` edit.

---

## 8. `EngineTuning`

Five new fields, all injectable and `MG_*`-env-overridable (the `EngineTuning`
precedent — internal knobs for testing and rare tuning, never a Preferences
control):

| Field | Default | Key |
|---|---|---|
| `circuitStrikeThreshold` | 4 | `MG_CIRCUIT_STRIKE_THRESHOLD` |
| `adaptiveConcurrencyStart` | 2 | `MG_ADAPTIVE_CONCURRENCY_START` |
| `cleanStreakToRaise` | 5 | `MG_CLEAN_STREAK_TO_RAISE` |
| `networkOfflineGraceSeconds` | 2 | `MG_NETWORK_OFFLINE_GRACE_SECONDS` |
| `networkOnlineSettleSeconds` | 2 | `MG_NETWORK_ONLINE_SETTLE_SECONDS` |
| `concurrentFragmentsNormal` | 4 | `MG_CONCURRENT_FRAGMENTS_NORMAL` |
| `concurrentFragmentsThrottled` | 1 | `MG_CONCURRENT_FRAGMENTS_THROTTLED` |

The host cooldown ladder reuses the existing `backoffLadder` / `backoffCap`.
`EngineTuning.resolved()` gains the seven parse lines; every unset / malformed
key keeps the default.

---

## 9. Logging

`GrabberKit/Logging/LogEvent.swift`:

- `DeferReason` gains `.hostCooldown(host: String, strikes: Int)` — the second
  `DeferReason` case beside `.backoff(attempt:)`.
- New events (JSON Lines, feeding §8.2 and the Phase 10 report):
  - `hostRateStateChanged(host: String, from: String, to: String)`
  - `circuitOpened(host: String, strikes: Int)`
  - `circuitReset(host: String, byUser: Bool)`
  - `adaptiveConcurrencyChanged(from: Int, to: Int, reason: String)` —
    `reason` is `clean_streak` or `throttle`
  - `networkPathChanged(online: Bool)`

Host names in log fields are the `RateHost.canonical` string. No URLs, no
per-video identifiers — §8.5.

---

## 10. Testing

### 10.1 Pure units (no engine, no network)

- **`RatePolicy`** — the core. Injected `now`, a tiny `EngineTuning`
  (`circuitStrikeThreshold: 3`, `backoffLadder: [1, 2]`):
  - `normal` + strike → `cooldown(until: now + delay(1), strikes: 1)`.
  - strike after the deadline → `cooldown(strikes: 2)`; next strike (`3 >= 3`)
    → `circuitOpen(strikes: 3)`.
  - strike before the deadline passes → state unchanged.
  - `cleanSuccess` from `cooldown` → `normal`, strikes 0.
  - `userReset` from `circuitOpen` or `cooldown` → `normal`, strikes 0.
  - a `.strike(retryAfter: n)` uses `min(n, backoffCap)` for the deadline
    instead of the ladder.
- **`RateLimiter`** — synchronous value-type API:
  - adaptive cap starts at `min(start, prefsCap)`.
  - `cleanStreakToRaise` clean successes → `+1`, capped at `prefsCap`.
  - any strike → cap 1, streak 0.
  - `setPreferencesCap` re-clamps; a raise does not jump the cap.
  - `blocked(host:now:)` true for a future cooldown and for `circuitOpen`,
    false once the deadline passes.
  - `circuitOpenHosts` / `cooldownDeadline` reflect the dict.
- **`RateHost`** — the alias table folds the five YouTube hosts; `www.` strip;
  a `generic` host keeps its domain; an unparseable string → `.unresolved`.
- **`CountdownFormat.mmss`** — boundaries (0:00, 0:59, 1:00, 9:59, negative → 0:00).

### 10.2 Engine (injected `Clock`, fake runner, fake `NetworkPathMonitoring`)

- A `.rateLimited` exit strikes the host, sets `adaptiveCap` to 1, moves **only
  the struck job** to `.cooldown(until: T)` with `cooldownUntil == T`, leaves the
  host's other `.queued` jobs untouched, and `blockedHostIDs` contains all of
  them until `T`. At `T` the struck job returns to `.queued` and the scheduler
  starts one (cap 1).
- A second strike (from that resumed job) before any `.completed` puts it back in
  `.cooldown` at the next-rung deadline; the `circuitStrikeThreshold`-th strike
  trips the circuit instead — the struck job stays `.queued`, no `deferStart`,
  `blockedHostIDs` still holds the host's jobs.
- A non-rate-limit auto-retryable exit takes the Phase 4 path, stays `.queued`,
  and does **not** touch host state (regression guard).
- `buildSnapshot` sets `queueHalt.circuitOpen` when a circuit is open and it is
  the reason nothing runs; it does **not** when a job for another host can run.
- `revalidate()` clears all circuits (the jobs are already `.queued`;
  `blockedHostIDs` just empties) and re-schedules.
- Fake monitor toggled offline → `queueHalt.networkDown`, running jobs
  `.waitingForNetwork` with `attempt` unchanged, queued jobs still `.queued`.
  Toggled online → halt cleared, jobs re-queued at the tail, no attempt burned.
- Debounce: a sub-grace offline blip does not halt; a flapping toggle settles.
- `hostRateSummary` and `JobSnapshot.rateHost` are populated correctly.
- `launchDownload` passes `--concurrent-fragments 4` for a `.normal` host and
  `1` for a host in `cooldown` (assert on the captured `ProcessLaunch`
  arguments).

### 10.3 App

- `HealthController.update` produces the online chip always and the cooldown
  chip only when `hostRateSummary` is non-empty; one chip for multiple hosts;
  the popover rows carry the right per-host action.
- `RowModel.statusText` prefix picks "Rate-limited — paused" / "Cooling down" /
  "Retrying" from the snapshot + `hostRateSummary`, and does not recompute on a
  progress tick.
- `MainWindow` applies the measured bottom inset when `bannerContent != nil` and
  removes it when nil.

### 10.4 §11.3 manual smoke (real yt-dlp)

Run with `MG_CIRCUIT_STRIKE_THRESHOLD=2 MG_BACKOFF_LADDER=3,5
MG_ADAPTIVE_CONCURRENCY_START=2` and a high enough concurrency / low enough
sleep to actually draw a 429 from a burst of small downloads:

1. Queue ~10 downloads. Observe concurrency start at 2, not the Preferences cap.
2. Force a 429 (burst). The struck host enters cooldown: affected rows show
   "Cooling down — 0:03" counting down, a cooldown chip appears with a countdown,
   its popover names the host and says concurrency dropped to 1, and the other
   queued jobs for that host are parked.
3. Let the cooldown expire; one download starts (cap 1). If it 429s again, the
   second strike trips the circuit: the banner appears ("… keep getting
   rate-limited …"), `queueHalt.circuitOpen`, no further auto-retry.
4. Press "Retry now". The circuit resets, downloads resume at cap 1 and ramp.
5. Toggle Wi-Fi off mid-download: the banner switches to "No internet
   connection …", running rows go "Waiting for network", no retry attempts are
   consumed. Toggle Wi-Fi on: downloads resume, attempt counts unchanged.
6. Scroll the table to the end with a banner showing — the last row is fully
   visible above the banner, not covered.

---

## 11. Parent design spec updates (same pass as the plan)

`docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md`:

- **§7.4** — reword to the shipped design: per-host `RateState` keyed on a
  URL-derived `RateHost` (YouTube subdomains folded); the cooldown ladder reuses
  `Backoff` fed the host strike count; the circuit is per-host and trips on
  `circuitStrikeThreshold` consecutive strikes with no clean success; recovery
  is user-only; adaptive concurrency is one global cap.
- **§7.6** — the `--concurrent-fragments` bullet: reword "raised to 3–4 only
  when the host `RateState == .normal`" to match §5.6 (4 when `.normal`, 1
  otherwise, `tuning`-controlled, read at spawn). Leave the `--limit-rate` /
  `--force-ipv4` / `--proxy` bullets — those shipped in Phase 3.
- **§7.8** — `NetworkMonitor` reflects the debounced, no-reachability-probe
  design and the "queued jobs stay queued, running jobs park" behavior.
- **§12.1 Phase 6** — rewrite the stub to match this spec's scope; move the
  engine-freshness chip line to Phase 10; note the per-host adaptive-concurrency
  deferral.
- **§12.1 Phase 10** — add the engine-freshness `HealthStrip` chip (the slot is
  not pre-built in Phase 6; Phase 10 emits it from `HealthController`).
- **§12.2 shell table** — update the *Scheduler loop*, *`QueueSnapshot.queueHalt`*,
  *`WarningBanner`*, and *`HealthStrip`* rows: Phase 6 adds `blockedHostIDs` +
  the adaptive cap to `SchedulerInput` (no loop rewrite), `.circuitOpen` /
  `.networkDown` to `queueHalt`, the three banner contents, and the
  online + cooldown chips + `ChipInteraction.popover`; the freshness chip is
  Phase 10.

`apps/media-grabber/ticket-backlog.md` — the per-host adaptive concurrency
ticket is already added under "Phase 6 deferrals".

`apps/media-grabber/CLAUDE.md` — no change (the two-doc-tree note already covers
a repo-root Phase 6 spec; this spec follows Phase 5's location).
