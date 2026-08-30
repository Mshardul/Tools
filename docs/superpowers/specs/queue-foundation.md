# Queue foundation and window chrome (Phase 2)

**Status:** not started. Parent spec:
`docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1.
Phase 1 (built, archived): `docs/superpowers/specs/archived/core-download-pipeline.md`.

Phase 1 ran one download at a time with no visible queue. Phase 2 makes the
engine own an ordered job list and a multi-slot scheduler, emits `Sendable`
value events the UI binds to, adds the Downloads table with its column system,
the full row-action bar, force-start, per-job raw logs, persistence across
launches, graceful quit, a reusable confirmation dialog, and the `WarningBanner`
/ `HealthStrip` chrome shells.

Everything built here is built to its final-app form. Where a later phase fills
in a case or a value, the container / type / seam is complete now and the fill
is additive — no shape a later phase must replace (parent §12 scoping rule).

---

## Architecture

The engine owns the queue. Nothing outside it reads engine state directly — a
single `AsyncStream<QueueEvent>` is the only channel out, and user intents are
`async` calls in.

- **`DownloadEngine`** (actor) holds one ordered job list — active *and*
  terminal jobs together, terminal jobs capped at 200 in memory
  (oldest-`finishedAt` evicted). The same 200, keyed on `finishedAt`, is the
  cap for `history.json` and for `JobLog` files — one set, three stores in
  lockstep, so every visible "Done" row maps to a live engine job the user can
  act on. It runs the scheduler and emits `QueueEvent` values.
- **`QueueEvent`** — `.snapshot(QueueSnapshot)` on any structural change (state,
  queue membership, order, completion, `queueHalt`); `.progress([UUID:
  Progress], revision:)` on progress-only ticks. One stream, two shapes. The
  rule: *progress is a delta; every other change is a full snapshot.* A progress
  line that also flips a job terminal emits `.snapshot`.
- **`QueueSnapshot`** — `{ jobs: [JobSnapshot], revision: UInt64, queueHalt:
  QueueHaltReason?, generatedAt: Date }`. **`revision` is the authoritative
  ordering signal** — strictly increasing across *both* event kinds,
  session-scoped, starts at 0 each launch, never persisted or compared across
  sessions. `generatedAt` is display / diagnostics only (a "last updated"
  indicator, log correlation); never used for ordering.
- **`JobSnapshot`** — the immutable per-job value. Full field set now
  (§ "JobSnapshot"); fields other phases populate are defaulted, never added
  later.
- **`AppModel`** consumes the stream in one long-lived `Task` and feeds
  **`RowStore`**, which turns events into identity-stable `@Observable`
  `RowModel`s the table binds to. `AppModel` never touches the engine's state,
  only its intents and its stream.
- **User intents** — `submit`, `pause`, `resume`, `cancel`, `remove`,
  `forceStart`, `restore`, `revalidate` — are `async` calls into the engine. No
  `reorder` this phase (§ "Deferred").

### Engine mutation invariant (Phase 2 onward)

`DownloadEngine` state changes happen only in **synchronous, non-`async`**
methods. Async work — child spawn, metadata probe, and later cooldown/backoff
timers — runs outside actor isolation and re-enters through those sync methods,
keyed by job id, never holding a reference to mutable job state across an
`await`. Every sync mutation bumps `revision` and emits the appropriate
`QueueEvent`. A future phase that adds a time-based or network-based wait puts
the wait outside isolation and the resulting state change inside. This makes
every emitted event a consistent point-in-time view and makes actor reentrancy
harmless.

No `Mutation` enum is mandated — small sync private methods
(`markRunning(_:)`, `recordExit(_:_:)`, `pauseJob(_:)`, …) satisfy the rule. An
enum stays an option if a later phase wants mutation replay or logging.

### Scheduler

Event-driven. `evaluateSchedule()` runs after every sync mutation: it reads the
current job list, asks the pure functions below which jobs may start
downloading and which may probe, marks them, and hands each spawn to a detached
launcher outside isolation. A completed spawn (or probe) re-enters via a sync
method, which itself calls `evaluateSchedule()`.

Two independent scheduling decisions, both pure:

- **`nextDownloads(_ input: SchedulerInput) -> [UUID]`** — the probe-complete
  queued jobs, in queue order, skipping any with a pending deferral, taking
  `max(0, cap - runningCount)`. `cap` is `maxConcurrentDownloads`; it gates
  **downloads only**.
- **`nextProbe(_ input: SchedulerInput) -> UUID?`** — the head queued job that
  still needs metadata, **iff** the serial probe is idle. Probing is gated only
  by the one-at-a-time `MetadataProbe` (its Phase 1 tail-chain), **not** by
  `maxConcurrentDownloads`. So the steady state during a burst of fresh URLs is
  `cap` downloads running **plus** one probe running — the pipeline fills
  instead of stalling at 1. A `-J` probe is cheap (no download), so the extra
  process is not a resource concern. A job submitted with prefetched metadata
  never enters `.probing`.

`SchedulerInput` is a struct (`queued: [JobSnapshot]`, `running: [JobSnapshot]`,
`cap: Int`, `deferredIDs: Set<UUID>`, `probeIdle: Bool`) so later phases add
fields (`hostStates`, `circuitOpen`, adaptive cap) without changing either
signature.

- **Deferred-start seam.** The engine holds a sorted list of `(jobID, notBefore:
  Date)` and a single sleep-`Task`, lazily created on first use, that wakes at
  the earliest deadline and calls `evaluateSchedule()`. Private API
  `deferStart(_ id: UUID, until: Date)`. **Nothing in Phase 2 calls
  `deferStart`** — it is the seam Phase 4 (backoff) and Phase 6 (host cooldown)
  plug into with no scheduler rewrite. Built, unit-tested with an injected
  clock, dormant. Not smoke-tested (an uncalled seam has no user flow).
- **A lowered cap never kills a running job.** If the cap drops below the
  running count (a test flag now, the Phase 3 slider or Phase 6 adaptive
  concurrency later), running jobs drain naturally and no new job starts until
  `running < cap`. `nextDownloads` already yields `[]` in that case. *Deferred:
  Phase 3 adds an inline note under the cap slider — "running downloads
  continue; restart to apply now."*

### Systemic halt

`QueueSnapshot.queueHalt: QueueHaltReason?` — `nil` in the healthy case. Phase 2
defines the one case `.depMissing`.

The trigger: a spawn that fails to exec the binary. `ProcessRunner` (Phase 1)
reports a launch failure as exit `127` + a `"launch failed:"` stderr line — the
engine classifies that specific signature as `depMissing` (not `.unknown`).
A `MetadataProbe` failure of the same kind classifies the same way.

On a `depMissing` failure the engine sets `queueHalt = .depMissing` and the
scheduler starts nothing. **The job that hit it is put back to `.queued`**, not
failed and not paused — the cause is systemic, not the job's fault, so it just
waits with the rest. The queue persists.

Recovery is an explicit intent, not a state read. `AppModel` sees `.depMissing`
→ flips `needsOnboarding = true` → the Onboarding takeover (parent §4.1, wired
from Phase 1). When onboarding completes, `AppModel` calls
**`engine.revalidate()`** — the engine re-runs its `EnvironmentProbe`, and if
deps are back it clears `queueHalt` and `evaluateSchedule()` resumes the queue
(the requeued job runs like any other). If deps are still missing, the halt
stands. `revalidate()` is the seam Phase 6's "Retry now" affordance
(`WarningBanner` dep-missing button, cooldown-chip popover) reuses.

`QueueHaltReason` gains `.circuitOpen` / `.networkDown` in Phase 6 — additive,
same scheduler-respected mechanism.

### The two deliberate deletions

Phase 1's single-drain loop is replaced, not extended: `drain()`,
`nextQueued()`, `ensureDraining()`, `drainTask`, `runningLineTask`, and the
separate `queuedJobs` array are removed; `submit`'s "second call waits FIFO
in-actor" behaviour goes with them. `pump(_:)`, `finish(_:)`,
`resolveOutputFiles`, `errorClass(for:)`, and `titleStem` are kept and adapted.

Phase 1's `DownloadJob` (`@MainActor @Observable`, bound directly by the UI) is
demoted to an engine-internal reference model (actor-isolated, not
`@MainActor`, not `@Observable`); `JobSnapshot` values on the stream replace
direct binding. Both changes are part of the Phase 2 engine rework — the
mutation invariant that requires them postdates Phase 1 (parent §12 rule 3:
current work may change completed-phase code, stated plainly as such).

### JobSnapshot

```
struct JobSnapshot: Sendable, Equatable, Identifiable {
  let id: UUID
  let url: String
  let title: String?
  let state: JobState
  let progress: Progress?
  let durationSeconds: Int?            // from the probe (Phase 1 MediaMetadata carries it)
  let extractor: String?              // yt-dlp extractor key from the probe ("youtube", "vimeo", …); the Site identity
  let addedAt: Date
  let finishedAt: Date?
  let destFolder: URL
  let outputFiles: [URL]
  let sizeBytes: Int64?                // the current download process's first-reported total_bytes; re-set by a fresh process on resume/restart; nil while queued/probing or if yt-dlp reports no total
  let actualQuality: String?           // nil until Phase 4 (IntegrityCheck's ffprobe reads the real w×h)
  let attempt: Int                     // 0 until Phase 4 populates
  let cooldownUntil: Date?             // nil until Phase 6
  let playerClientUsed: String?        // nil until Phase 7
  let playlistGroupID: UUID?           // nil until Phase 8
  let integrityVerdict: IntegrityVerdict?   // nil until Phase 4
  let availableActions: Set<RowAction>
}
```

Not `Codable` — runtime only.

- `type` and `quality` are **not** stored — `RowStore` derives them (Audio/Video
  and the request selector from `request.kind`) and caches them on `RowModel`.
- `site` (`siteLabel`) is derived by `RowStore` from `JobSnapshot.extractor` —
  the yt-dlp extractor key from the probe's `-J` output (Phase 1's
  `MetadataProbe` decodes the JSON; add `extractor` to `MediaMetadata` and
  carry it onto the snapshot). This makes `youtube.com`, `youtu.be`,
  `m.youtube.com` one Site (`YouTube`), so the Site checklist filter works.
  Before a job has probed, `siteLabel` is **em-dash** (no domain parsing, no
  PSL) — it fills in with the extractor label once probed, like every other
  not-yet-known field.
- Queue position (`#3`) is **not** stored — it changes on every dequeue without
  the job changing. `RowStore` derives it from snapshot order for `.queued`
  rows.
- `availableActions` is computed by the engine per job from its state (below).
  Phase 4/5 add `retry` / `retryWithCookies` / `showLog` to the set with no UI
  change.

```
enum IntegrityVerdict: Sendable, Equatable {
  case passed
  case failed(reason: String)
  case skipped(reason: String)        // no ffprobe / audio-only / live stream
}

enum QueueHaltReason: Sendable, Equatable {
  case depMissing
  // Phase 6: .circuitOpen, .networkDown
}

enum RowAction: Sendable, Hashable {
  case pause, resume, cancel, remove, forceStart, reveal, openInBrowser
  case retry, retryWithCookies, showLog     // gated — never in the Phase 2 set
}
```

| Job state | `availableActions` (Phase 2) |
|---|---|
| `.queued` | pause, cancel, forceStart, remove, openInBrowser |
| `.probing` | cancel, remove, openInBrowser |
| `.running` | pause, cancel, remove, openInBrowser |
| `.paused` | resume, cancel, remove, openInBrowser |
| `.completed` | reveal, remove, openInBrowser |
| `.cancelled`, `.failed` | remove, openInBrowser |

The action bar renders **every** `RowAction` button in a fixed layout; a button
whose action is not in the job's `availableActions` renders disabled. `retry`,
`retryWithCookies`, `showLog` are therefore always disabled this phase. Phase 4
enables `retry` + `showLog` (the `JobLog` files exist from Phase 2), Phase 5
enables `retryWithCookies` — by adding the action to the engine-computed set,
no UI change.

### Intent semantics

- **`submit(_ request: DownloadRequest, force: Bool, prefetchedMetadata:
  MediaMetadata?) async -> SubmitResult`**
  - `SubmitResult = .queued(UUID) | .duplicateExists(existing: UUID, wasCompleted: Bool)`.
  - Duplicate check (skipped when `force: true`): **any** job in **any** state
    whose `DownloadRequest` is **equal** (URL + destFolder + kind + container +
    template — `DownloadRequest` is `Equatable`) → return
    `.duplicateExists(existing:, wasCompleted:)`, create nothing. A different
    format / folder / template is a different request, not a duplicate.
  - `AppModel` shows the confirm dialog — copy differs by `wasCompleted`
    ("already in your queue" vs "you've already downloaded this"). On confirm →
    `submit(force: true, …)`, which always returns `.queued` and creates a
    **distinct** job: a new row, and — since the request (and so the output
    template) matches — yt-dlp's default numbering writes `Video (1).mp4`, the
    earlier download is untouched. No `--force-overwrites`. On cancel: nothing
    (for a completed match, scroll to / flash the existing row).
  - On `.queued`: append a `.queued` job at the tail, log `jobEnqueued`,
    `evaluateSchedule()`. If `prefetchedMetadata` is provided, the job's title +
    `extractor` + `durationSeconds` are filled from it and the engine skips its
    own probe (job goes `.queued` → `.running`, no `.probing` hop). If `nil`,
    the engine probes as normal. No staleness check on prefetched metadata — the
    download attempt is the check.
  - Playlist URLs get no special handling this phase — the Phase 1
    `--no-playlist` behaviour stands, `playlistGroupID` stays nil.
- **`pause(_ id: UUID)`** — running → SIGTERM child, `.part` kept. State →
  `.paused`. The job **leaves the pending queue**: the scheduler ignores it, it
  does not count against the cap, it sits out until resumed. Log `jobPaused`.
- **`resume(_ id: UUID)`** — `.paused` → `.queued`, **re-enqueued at the tail**
  (old position lost). No `.resuming` state. The `.part` makes it resume, not
  restart, when the scheduler reaches it. Log `jobResumed`.
- **`cancel(_ id: UUID)`** — running → SIGTERM child. `.part` **kept** (retry
  wiring is Phase 4; the file is there for it). State → `.cancelled` (terminal).
  Row stays visible; counts toward the 200 cap. Its `JobLog` file is kept.
- **`remove(_ id: UUID)`** — running → SIGTERM child. `.part` **deleted**, the
  `JobLog` file **deleted**. The job leaves the list entirely and is purged from
  `history.json` on the next write. No history entry, no row. Log `jobRemoved`.
- **`forceStart(_ id: UUID)`** on a `.queued` job — **one atomic sync
  mutation**, not a sequence: within a single non-`await` method the engine
  moves the forced job to the queue head, and if `running == cap` moves the
  oldest-`startedAt` running job to `.queued` **at the tail** and marks the
  forced job `.running`; then it bumps `revision` once and emits **one**
  `.snapshot` (showing forced-running + victim-queued-at-tail simultaneously);
  then `evaluateSchedule()` runs against that consistent state. The victim's
  child SIGTERM and the forced job's spawn are handed to the detached launcher
  after the sync mutation returns. If `running < cap`, just mark + start.
  Because eviction and start land in the same snapshot, the scheduler never
  sees an intermediate `running == cap-1` world and cannot re-pick the victim.
  Not offered on a non-queued job. Log `jobForceStarted(id:, evicted:)`.

### Restore

`restore(active:history:)` — the engine sets its job list **from the on-disk
order** (§ Persistence), active jobs as `.queued`, terminal jobs inert. A
restored active job whose `PersistedJob` carries `title` **and** `extractor`
**and** `durationSeconds` enters `.queued` **probe-complete** — the scheduler
takes it straight to download, no re-probe. A restored job missing any of the
three re-probes when scheduled. `restore` also forces `hasGrabbedOnce = true` if
it produced any job.

`DownloadRequest` round-trips through `PersistedJob` with exact `Equatable`
fidelity (every field, including `DownloadKind`'s associated values, the
container, and the template) — asserted by a round-trip test — so re-pasting a
restored link is still caught by the duplicate check.

### `DownloadEngineProtocol`

```
protocol DownloadEngineProtocol: Sendable {
  var events: AsyncStream<QueueEvent> { get }
  func currentSnapshot() async -> QueueSnapshot      // ground truth for a (re)subscribing consumer
  func hasActiveJobs() async -> Bool                 // .probing / .running — for QuitCoordinator

  func submit(_ request: DownloadRequest, force: Bool, prefetchedMetadata: MediaMetadata?) async -> SubmitResult
  func restore(active: [PersistedJob], history: [PersistedJob]) async
  func revalidate() async     // re-run EnvironmentProbe; clear queueHalt if deps are back

  func pause(_ id: UUID) async
  func resume(_ id: UUID) async
  func cancel(_ id: UUID) async
  func remove(_ id: UUID) async
  func forceStart(_ id: UUID) async

  func shutdown() async     // SIGTERM every child + cancel the in-flight probe task, await reap, return
}
```

The engine is constructed with an **`EngineDependencies`** struct
(`.live(ytDlpURL:debugFlags:)` for production; a test factory builds one with
fakes, defaulted). The struct grows in later phases (`NetworkMonitor`,
`RateController`, `PotProviderProcess`) — call sites using the factory do not
change.

`events` is one stream, one consumer (the `AppModel` task, created once at
`AppModel` scope and never torn down while the app runs). A (re)subscribing
consumer calls `currentSnapshot()` for ground truth, then reads the stream.

`shutdown()` cancels the engine's current probe `Task` alongside download
children. A job caught mid-probe persists `.queued` and re-probes on restore.
*Deferred: Phase 8 adds per-request probe cancellation (a removed job whose
probe is queued behind others in the tail-chain) — additive to the chain.*

---

## App layer

### RowStore

Lives in the `App` target next to `AppModel` (it produces `@Observable`
view-models — an App concern; GrabberKit stays UI-free). Pure logic, headless-
testable.

- **`RowModel`** — `@Observable final class`, one per job id. Mirrors
  `JobSnapshot` and holds cached display strings (`statusText`, `speedText`,
  `etaText`, `formattedSize`, `formattedDuration`, `siteLabel`, `typeLabel`,
  `qualityLabel`, `queueBadge`) recomputed on patch only when the source field
  changed — never in a view body.
- **`apply(_ event: QueueEvent)`** — two paths:
  - `.snapshot` → keyed patch of `[UUID: RowModel]` (mutate only fields that
    differ so SwiftUI invalidation stays scoped; create new, drop missing),
    rebuild the ordered `rows`, recompute `visibleRows`, `groups`, `chipCounts`.
    A `.snapshot` with no structural row change (detected during the patch pass)
    skips the filter/sort recompute unless the active sort column is
    `progress`, `speed`, `eta`, or `size`.
  - `.progress` → patch `progress` + `speedText` / `etaText` / `formattedSize`
    on the referenced `RowModel`s only. Recompute `visibleRows` order only if
    the active sort column is `progress`, `speed`, `eta`, or `size`.
- **`resync(_ snapshot: QueueSnapshot)`** — used after the consumer-task spin
  guard (§ "AppModel changes"). Treats the snapshot as ground truth: full
  rebuild, resume tracking from its `revision`.
- **Owns all derived state:**
  - `rows` — all rows, stable identity, snapshot order.
  - `visibleRows` — after the active filter chip + per-column filters + the
    single active column sort. **Computed over the full `rows` list** — the
    table's lazy rendering (§ "Downloads table") is a view-materialisation
    optimisation only; sort, filter, and `chipCounts` always see every row.
  - Sort rule: nil values sort **last** regardless of direction. Single active
    sort column (a new column's `↕` clears the previous).
  - `groups` — `[PlaylistGroup]`, **empty this phase**. `PlaylistGroup { id,
    title, totalCount, completedCount, failedCount, rollupFraction, isCollapsed
    }` is defined now; Phase 8 populates and renders it. *Deferred: Phase 8 —
    the per-column group aggregate and the quantised rollup-progress rule are
    recorded in the parent §12.1 Phase 8 stub.*
  - `chipCounts` — `All` / `Downloading` / `Done` / `Needs attention`. "Needs
    attention" = `.failed` or `.cooldown`.
- Driven by `(QueueEvent, ColumnConfig)`.

### AppModel changes

- Drop `job: DownloadJob?`. Add `rows` (from `RowStore`).
- The consumer task — owned by `AppModel`, started in `onAppear`, never
  cancelled while the app lives:
  ```
  while !Task.isCancelled {
    for await event in engine.events { rowStore.apply(event) }
    log(.consumerStreamEnded)              // should never fire — the stream lives with the engine
    try? await Task.sleep(for: .seconds(1))   // spin guard
    await rowStore.resync(engine.currentSnapshot())
  }
  ```
- Keep the Phase 1 first-run-cards → table transition
  (`AppStorage("mg.hasGrabbedOnce")`). Add the emptied-table state: table
  chrome stays, body shows the single centered line
  `No downloads — paste a link above.` The step cards do not return.
- `grab()` builds the `DownloadRequest` via `RequestBuilder` (below), passing
  the runway state as overrides and `resolved` as `prefetchedMetadata`, then
  calls `engine.submit(force: false, …)`. On `.duplicateExists(existing:,
  wasCompleted:)` → `await confirm(...)` with copy chosen by `wasCompleted`; if
  confirmed, `engine.submit(force: true, …)`; if cancelled and `wasCompleted`,
  scroll to the existing row. It may keep the returned `UUID` transiently to
  scroll the new row into view.
- Row actions dispatch to `engine` by the row's id.
- `reveal()` filters the row's `outputFiles` to paths that exist; reveals those
  via `RevealSink`; if none exist, presents the "file no longer at that
  location" notice via `confirm` (notice mode) and logs `.revealTargetMissing`.
- Holds `ColumnConfig` (`@Observable`); its `didSet` calls
  `Persistence.saveColumns(_:)` (debounced there, not on `AppModel`).
- Holds the filter-chip selection (`All` default) — view state, **not
  persisted**, resets each launch.
- Holds `pendingConfirmation: ConfirmationRequest?` and `confirm(_:) async ->
  Bool` (§ "Confirmation dialog").
- Reads `DebugFlags` (parsed once in `MediaGrabberApp.init` from
  `CommandLine.arguments`): `forceOnboarding` (folds in the Phase 1
  `-MGForceOnboarding`), `concurrencyCapOverride: Int?` (wins over
  `Preferences`), `resetState: Bool` (skip the persistence file loads on
  launch). *Deferred: Phase 10 — a Debug menu bound to `DebugFlags` if
  warranted.*

### RequestBuilder

```
struct RunwayOverrides { var kind: DownloadKind?; var destFolder: URL? }   // nil = use the pref default

enum RequestBuilder {
  static func build(from resolved: MediaMetadata, prefs: Preferences, overrides: RunwayOverrides) -> DownloadRequest
  // a private per-item helper does the actual construction;
  // Phase 8's buildPlaylist(from:, selection:, prefs:, overrides:) -> [DownloadRequest] reuses it
}
```

Pure, unit-tested (prefs-only, full override, partial override). Phase 2 wires
the Home runway's `@State` (Type / Format / Save-to) through `grab()` into
`overrides` so a runway change applies to that download — closing the Phase 1
runway-not-applied gap as a plain Phase 2 change.

### Downloads table

Hand-rolled (`DownloadsTable`, `DownloadRow`, `ColumnsMenu`) — **not** SwiftUI
`Table`, which cannot do column drag-reorder + per-column filter menus + the
Phase 8 playlist group header.

- **Home layout** — `HomeView` is restructured: a **fixed header region**
  (paste field, runway when shown, filter chip row, `⊞ Columns` button, the
  column header row) + an **independently scrolling table body** filling the
  remaining height. First-run state (no table): the fixed region is just the
  paste field + hero + step cards, centered. This replaces Phase 1's single
  `ScrollView` — a plain Phase 2 restructure.
- **Virtualised rows** — the body renders `visibleRows` through a `LazyVStack`
  in the vertical scroll; only viewport-adjacent rows are materialised. No
  pagination, no page controls. Handles end-state playlist scale (thousands of
  rows) without full materialisation. Sort / filter / counts are unaffected —
  they run over the full list (§ RowStore).
- **Two-axis scroll** — when visible columns exceed the window width the body
  scrolls horizontally; the column header row scrolls horizontally **in sync**
  with it. Vertical scroll for rows, horizontal for columns; headers pinned
  vertically, moving horizontally with the body. `DownloadsTable` owns the
  synced 2-axis scroll.
- **Filter chips** `All · Downloading · Done · Needs attention` — "Needs
  attention" shows a count badge when > 0. A "Clear filters" text button appears
  when the current chip + column filters hide every row; it resets the chip to
  `All` and clears column filters. The filtered-empty body shows
  `No downloads match this filter.` (distinct from the empty-queue line).
- **`ColumnConfig`** (`Codable`, → `columns.json`): visible set, column order,
  the single active sort column + direction, active per-column filters.
  Invariants enforced on load and on mutate: **Actions** pinned last, always
  visible, not movable; **Title** always visible (movable).
- **16 columns, all defined and in the `⊞ Columns` menu from Phase 2**
  (design-system §4.2.3 is the reference). `ColumnID` enum:
  `title, status, progress, speed, eta, type, quality, size, site, addedAt,
  finishedAt, duration, destination, attempt, clientUsed, actions`.
  Default-visible (8): `title, status, progress, speed, eta, type, quality,
  size`. Hidden by default (7): `site, addedAt, finishedAt, duration,
  destination, attempt, clientUsed`. Pinned: `actions`.
  - `type` = `Audio` / `Video`, `quality` = the **request** selector (`1080p` /
    `720p` / … / `m4a` / `mp3`) — derived by `RowStore` from `request.kind`,
    cached, both checklist-filterable. For video `maxHeight` is a ceiling; the
    cell shows the request value, never em-dash. *Deferred: Phase 4 —
    `IntegrityCheck`'s ffprobe reads the real resolution into
    `JobSnapshot.actualQuality`; the cell then shows `1080p → 720p` when
    request ≠ actual.*
  - `speed` / `eta` — separate columns, both default-visible, sort-only, blank
    on non-running rows.
  - `size` — `JobSnapshot.sizeBytes`: the engine captures `total_bytes` once
    when the download starts and never changes it (`Progress` carries the live
    "how far along"; `sizeBytes` is the fixed total). Em-dash while queued /
    probing, or if yt-dlp reports no total.
  - A column whose `JobSnapshot` field is nil renders an em-dash now; when a
    later phase wires the field (`attempt` → P4, `clientUsed` → P7) values
    appear automatically — no menu change, no `ColumnConfig` migration.
  - **No `playlist` column** — playlist membership is the group header + spine
    (§4.2.4, Phase 8), not a column.
- **Column headers draggable to reorder** (except Actions). **One active sort
  column** (`↕` cycles asc → desc → off; a new column's `↕` clears the
  previous) and filter (`▽` menu) per the §4.2.3 table; `progress` / `speed` /
  `eta` / `size` are sort-only. Nil values sort last regardless of direction.
  A checklist filter with only "(none)" (a not-yet-populated field) is allowed,
  not special-cased.
- **Status cell** — plain-language state with a leading dot per design-system
  §4.2.3. A `.queued` row shows its queue position: `queued · #3` (1-based,
  derived by `RowStore`). Running/terminal rows show no number. A failure shows
  its plain reason sentence, not a code.
- **No drag-reorder of the queue this phase**, and **no row selection** — the
  Actions column is the entire per-row interaction model (parent §4.2.3 /
  §5.4). Ad-hoc multi-select is an explicit non-feature; if ever wanted it is a
  design-doc change first, then its own phase.
- No per-row expansion, no detail view — ever.
- The body reserves ≈ 80 px bottom inset so its last row never sits under the
  docked `WarningBanner`.

### Window

`MediaGrabberApp` — bump the minimum to `minWidth: 820, minHeight: 560`;
`.windowResizability(.contentMinSize)` (freely resizable, not content-sized);
`.defaultSize` stays 980×720; `WindowFrameAutosave` unchanged. A plain Phase 2
change to the Phase 1 window config.

### Confirmation dialog

A reusable modal — the app has a handful of these across its life and they
share a shape.

```
struct ConfirmationRequest: Identifiable {
  let id: UUID
  let title: String
  let message: String
  let confirmTitle: String
  let cancelTitle: String?        // nil → a single-button notice, no choice
  let isDestructive: Bool
  let suppressionKey: String?     // non-nil → a "Don't ask again" checkbox, persisted to AppStorage
}

protocol Confirming { func confirm(_ request: ConfirmationRequest) async -> Bool }
```

- `AppModel.confirm(_:)` sets `pendingConfirmation`, awaits the choice via a
  continuation, returns `Bool` (a notice returns `true` on dismiss; callers
  ignore it).
- One dialog host in `MainWindow` bound to `pendingConfirmation`.
- If `suppressionKey` is set and previously suppressed, `confirm` returns `true`
  immediately without showing.
- **Visual** — new design-system §4.8 (written as part of this phase):
  centered skinned sheet over a scrim (`--ground` ~60% alpha), max-width ~420px,
  skin card treatment (`--panel-solid`, skin border + radius + elevation).
  Layout: optional `warning` glyph (§3.4, destructive only) · title
  (`displayFont` 15 semibold) · message (`bodyFont` 13, `--dim`) · optional
  "Don't ask again" checkbox row · right-aligned buttons — Cancel
  (plain/`--panel`, omitted in notice mode) then Confirm (`--danger` fill when
  `isDestructive`, else `--accent` / skin `--go`). Motion `--dur`/`--ease`,
  disabled under reduce-motion. Return = confirm, Esc = cancel/dismiss; focus
  starts on Cancel for destructive actions, Confirm otherwise. VoiceOver:
  modal-alert semantics, focus trapped, message read.
- Phase 2 users: **duplicate submit** (`suppressionKey: nil` — always prompts;
  suppressing it would silently double-download a re-pasted link months later,
  and there is no Preferences UI in Phase 2 to un-suppress), **graceful quit**
  (`suppressionKey: nil`), **reveal-target-missing** (notice mode), **persistence
  write failure** (notice mode, once). The `suppressionKey` mechanism is built
  but unused in Phase 2 — the seam for Phase 8 "cancel all" and later dialogs.
- `FakeConfirmer` returns canned answers for tests.

### Graceful quit

`@NSApplicationDelegateAdaptor` → a thin `AppDelegate` whose only real method is
`applicationShouldTerminate(_:)` → returns `.terminateLater`, hands off to a
**`QuitCoordinator(engine:persistence:confirmer:)`**:

1. if `await engine.hasActiveJobs()` **or** the latest snapshot's `queueHalt`
   is non-nil → `await confirm(.quitWithActiveJobs)` (copy notes the halt when
   present — "Downloads are paused — yt-dlp needs reinstalling. Quit anyway?");
   on cancel, `reply(false)` and stop. A non-empty but purely `.queued` queue
   with no halt does not prompt — it persists and resumes cleanly.
2. `await persistence.flushNow()` — cancel the debounce timers, write
   `queue.json` / `history.json` / `columns.json` synchronously. A failure here
   does **not** block quit; if the confirm dialog showed, its message notes the
   save failure.
3. `await engine.shutdown()` — SIGTERM every child + the in-flight probe task,
   await reap.
4. `NSApp.reply(toApplicationShouldTerminate: true)`.

`QuitCoordinator` is a first-class type (a later phase's "quit to update" reuses
it), tested with fakes for the engine, persistence, and confirmer.

---

## Persistence

Three files under `~/Library/Application Support/MediaGrabber/`, each a
schema-versioned wrapper, each a projection of the one engine job list. Plain
paths, not sandboxed.

```
struct QueueFile:   Codable { var schemaVersion: Int; var jobs: [PersistedJob] }   // non-terminal
struct HistoryFile: Codable { var schemaVersion: Int; var jobs: [PersistedJob] }   // terminal, ≤ 200
struct ColumnsFile: Codable { var schemaVersion: Int; var config: ColumnConfig }
```

`schemaVersion == 1` for Phase 2.

```
struct PersistedJob: Codable {
  var id: UUID
  var request: DownloadRequest        // already Codable; round-trips with exact Equatable fidelity
  var title: String?
  var extractor: String?              // stored so a restored job skips re-probe
  var durationSeconds: Int?           // ditto
  var state: PersistedState           // queued | paused | completed | cancelled | failed(reason: String)
  var attempt: Int
  var playlistGroupID: UUID?
  var addedAt: Date
  var finishedAt: Date?
}
```

A restored active job with `title` + `extractor` + `durationSeconds` all present
enters `.queued` probe-complete (no re-probe); missing any → re-probe when
scheduled.

- **Order is preserved.** `queue.json` stores the non-terminal jobs **in engine
  list order**, and `restore` rebuilds the list in exactly that order — it does
  **not** re-sort by `addedAt`. So a force-started job's front-of-queue
  position (and any future drag-reorder) survives a relaunch. `addedAt` stays
  on `PersistedJob` for the "Added at" column but is not the restore sort key.
  No `queueOrder` field — the array order is the source of truth, persistence
  just doesn't reorder it.
- On write, live state clamps: `running` / `probing` → `queued`;
  `cooldown` / `waitingForNetwork` (Phase 6) → `queued`.
- `failed` persists a **raw reason string**, not `ErrorClass` — the enum gains
  cases in Phase 4/7 and keeping it off disk avoids a migration. On load a
  `failed` job restores as a terminal row with that text.
- Debounced 500 ms (injected clock). `.progress` events never trigger a write.
  Before each write, the projected `[PersistedJob]` is compared to the last
  written set and the write is skipped if unchanged.
- Writers: the engine's terminal transitions drive `history.json`; every other
  job-list change drives `queue.json`. `ColumnConfig` stays `@Observable` on
  `AppModel`, but its `didSet` calls `Persistence.saveColumns(_:)` — all three
  files' debounced writes live in `Persistence`, so `flushNow()` covers all
  three in one path.
- `PersistedState.failed` stores a plain reason string only. On restore a
  `failed` job becomes `JobState.failed(.unknown(raw: reason))` — the text is
  preserved, the original `ErrorClass` case is not. *Deferred: Phase 4 — decide
  whether retry re-classifies a restored `.unknown` failure.*
- **Write failure** — logged every time (`persistenceWriteFailed(file:,
  error:)`); the *first* failure also presents a one-time notice via `confirm`
  ("Couldn't save your queue — changes may be lost if the app closes"). The
  flag clears on the next successful write (`persistenceRecovered`, no notice).

### Load behaviour

| Situation | Action |
|---|---|
| `DebugFlags.resetState` | Skip all three loads; start clean. |
| File absent | Start empty (or `ColumnConfig` defaults). No log. |
| Valid, `schemaVersion == 1` | Load. |
| `schemaVersion < 1` | Run the migration chain (none exist yet). |
| `schemaVersion > 1` (user ran a newer build, downgraded) | Discard, start empty, `persistenceSchemaAhead(file:)`. Do not parse. |
| Corrupt JSON / decode failure | Discard, start empty, `persistenceCorrupt(file:)`. Never crash. |
| Unknown extra object fields | Ignored. |
| Missing newly-added optional field | Decodes to nil/default. |
| `columns.json` names an unknown column | That entry dropped. |
| `columns.json` omits a known column | Appended at its default visibility/position. |

A discarded file is overwritten on the next debounced save; the `LogEvent` is
the only record.

### Launch resume

`MediaGrabberApp` loads `queue.json` + `history.json`, calls
`engine.restore(active:history:)`. The engine rebuilds its list: active jobs
enter as `.queued` (`running` / `probing` already clamped on disk), terminal
jobs enter inert. The yt-dlp `.part` files on disk let the engine's existing
`pump` path resume rather than restart. `columns.json` loads into
`ColumnConfig`, or falls back to the defaults.

`hasGrabbedOnce` is `@AppStorage`, independent of the queue files. On launch, if
`restore` produced **any** job (active or history), `hasGrabbedOnce` is forced
`true` — persisted jobs are proof the user has grabbed before, so the table
renders, not the first-run cards. A wiped/corrupt queue with `hasGrabbedOnce ==
true` shows the emptied-table state, not first-run.

---

## Logging

Phase 1 `LogWriter` (actor, JSON Lines + `os.Logger` mirror) and `LogEvent`
(discrete enum) are extended. New cases:

- **Queue lifecycle** (category `.scheduler` / `.engine`) — discrete,
  engine-authored:
  `jobEnqueued(id:, url:, queuePosition:)`,
  `jobStartedByScheduler(id:, running:, cap:)`,
  `jobPaused(id:)`, `jobResumed(id:)`,
  `jobForceStarted(id:, evicted: UUID?)`,
  `jobRemoved(id:, wasRunning: Bool)`,
  `jobDeferred(id:, until: Date, reason: DeferReason)` — `DeferReason` is
  defined now with **no case a Phase 2 path can emit** (Phase 4 adds
  `.backoff(attempt:)`, Phase 6 `.hostCooldown(host:)`); the event + enum exist
  so the deferred-start seam has somewhere to log.
  `jobStateChanged` (Phase 1) still covers `.running` → terminal transitions.
- **Duplicate submit:** `jobDuplicateSubmitPrompted(existing:)`,
  `jobDuplicateSubmitConfirmed`, `jobDuplicateSubmitCancelled`.
- **Persistence** (category `.persistence`): `persistenceLoaded(file:, count:)`,
  `persistenceCorrupt(file:)`, `persistenceSchemaAhead(file:)`,
  `persistenceWriteFailed(file:, error:)`, `persistenceRecovered(file:)`.
- **Misc:** `revealTargetMissing(jobID:)`, `consumerStreamEnded`.

### JobLog

Built to final form now (its data path — the `pump` line stream — is already
open from Phase 1).

- `JobLog` — a header block (url, redacted request, start time, yt-dlp version)
  then the raw stdout/stderr lines appended as they stream, one file per job at
  `~/Library/Logs/MediaGrabber/jobs/<id>.log`.
- Redaction per §8.5 (home paths → `~`, credentials stripped).
- Deleted on `remove`; kept on `cancel` / terminal. Total capped at 200,
  evicted by the **owning job's `finishedAt`** — the *same* key and the *same*
  200 jobs as the in-memory terminal cap and `history.json`, so all three stay
  in lockstep (a visible "Done" row always has both its history entry and its
  log file). Not file mtime — a restored job's file has an old mtime but the
  job is fresh in memory.
- The `showLog` row action stays **disabled** this phase — Phase 4 enables the
  button; the files it will open exist from Phase 2.

---

## Chrome shells (layout complete, cases / values added later)

- **`WarningBanner`** — docked to the window bottom, floating over the table,
  `left/right: 16`, `bottom: 16`. Renders from an optional
  `BannerContent { text: String; buttonTitle: String; action: @Sendable () async -> Void }`
  — **nil this phase**. Skin-styled per design-system §4.1. The table's ~80 px
  bottom inset is reserved regardless. Phase 6/7 supply content (cooldown,
  circuit-open, dep-missing, POT-down); a ticking countdown re-emits its
  `BannerContent` rather than needing a date field.
- **`HealthStrip`** — the Phase 1 single static "online" pill becomes a chip
  **row**. A `HealthController` (folded into `AppModel` or standalone) produces
  `[HealthChip]`; Phase 2 returns exactly one — the static "online" chip. The
  strip renders whatever it is given.
  ```
  struct HealthChip: Identifiable {
    let id: String
    let label: String
    let dot: DotState              // .ok (green) | .attention (amber)
    let interaction: ChipInteraction
  }
  enum ChipInteraction { case none; case refresh(@Sendable () async throws -> Void) }
  ```
  Phase 6 fills the controller (engine-freshness / online / per-host-cooldown
  chips) and adds `ChipInteraction.popover(PopoverContent)` for the cooldown
  chip (additive — the strip's `switch` gains a case). Phase 7 adds the
  bot-check shield chip.

## `ErrorClass`

Already the full enum (Phase 1). Phase 2 wires the engine's terminal path to
emit `diskFull` and `permissionDenied` on a write failure detected from
yt-dlp's stderr / exit (a deleted or unwritable destination folder maps to
`permissionDenied`), and `incomplete` when a download ends short of the
expected size. Failure copy for these three is added to the row Status
sentence. The rest of the enum stays unemitted until its phase.

## Preferences

Add `maxConcurrentDownloads: Int` to the Phase 1 `Preferences` model
(UserDefaults-backed, key `mg.maxConcurrentDownloads`). Default **3**, clamped
to **1–6** on set (a conservative ceiling until Phase 6's circuit breaker;
Phase 6 may widen it). `DebugFlags.concurrencyCapOverride` wins over it. No
Preferences *UI* this phase — the scheduler reads the model; Phase 3 adds the
editor.

---

## Deferred (named)

- Retry / `Backoff` / `maxAutoAttempts` wiring, `IntegrityCheck` → **Phase 4**.
  Phase 2 leaves `attempt` at 0, `integrityVerdict` nil, `retry` / `showLog`
  disabled; the `deferStart` seam has no caller; `DeferReason` has no emittable
  case.
- `RateState` / cooldown / circuit breaker / adaptive concurrency /
  `NetworkMonitor` / `WarningBanner` content / `HealthStrip` real chips /
  `queueHalt.circuitOpen` + `.networkDown` / `ChipInteraction.popover` →
  **Phase 6** (bot-check chip → **Phase 7**).
- Playlist grouping (`groups`, group header + spine, per-column aggregates, the
  quantised rollup-progress rule) → **Phase 8**; `PlaylistGroup` type and
  `playlistGroupID` exist now. Per-request probe cancellation → **Phase 8**.
- Cap-slider "restart to apply now" inline note → **Phase 3**.
- Drag-reorder of the queue → not claimed by any phase; add on demand.
- Row multi-select → explicit non-feature; design-doc change first if ever.
- Preferences UI → **Phase 3**. Debug menu → **Phase 10**.
- Toasts + native notifications (including a "download saved" / "file moved"
  toast) → **Phase 11**.

---

## Test support

A real **`TestSupport`** target (framework, `@testable import GrabberKit`),
depended on by `GrabberKitTests` and `AppUnitTests`. Holds the shared
primitives and fakes:

- `LockedBox` (delete the two existing copies), `FakeClock`.
- `FakeProcessRunner`, `FakeMetadataProbe`, `FakeEnvironmentProbe` (moved from
  `GrabberKitTests`).
- `FakeEngine` (new protocol), `EventCollector` (accumulates `QueueEvent`s,
  `latestSnapshot()`, `waitForState(_:_:timeout:)`), `FakeQueuePersisting`,
  `FakeConfirmer`.
- `Fixture` — a typed loader for the checked-in yt-dlp output corpus.

Every later phase adds its fakes here.

---

## Build order

Each step is a TDD unit with its own DoD. The phase closes when the last step's
DoD passes and every prior DoD still holds. Implementation runs a few
contiguous steps per session.

1. **`TestSupport` target.** Create the framework target in `Project.swift`;
   move `FakeProcessRunner` / `FakeMetadataProbe` / `FakeEnvironmentProbe` in;
   consolidate `LockedBox` (delete both copies); add `FakeClock` and the
   `Fixture` loader. Both test targets depend on it. **DoD:** `tuist generate`
   clean, both test targets build, the moved fakes' existing tests pass.

2. **Value types** (GrabberKit/Download). `JobSnapshot` (full field set),
   `QueueSnapshot`, `QueueEvent`, `RowAction`, `IntegrityVerdict`,
   `QueueHaltReason`, `PersistedState`, `SubmitResult`, `DeferReason` (no
   emittable case), `SchedulerInput`. Add `extractor: String?` to Phase 1's
   `MediaMetadata` (decoded from `-J`'s `extractor` key) and to `PersistedJob`.
   All `Sendable`; `JobSnapshot` `Equatable` + `Identifiable`, not `Codable`.
   **Tests:** `Equatable` behaviour (progress change ≠ equal; all-nil snapshot
   valid); `RowAction` set membership; `MediaMetadata` decodes `extractor` from
   a fixture `-J` blob. **DoD:** types compile, equality/identity asserted.

3. **`nextDownloads` + `nextProbe` + `SchedulerInput`** (GrabberKit/Download).
   Two pure functions. `nextDownloads`: probe-complete queued jobs in order,
   minus `deferredIDs`, take `max(0, cap - running.count)`. `nextProbe`: the
   head queued job needing metadata, iff `probeIdle`. **Tests:** empty → `[]` /
   `nil`; `running < cap` → fills in queue order; `running >= cap` → `[]` but
   `nextProbe` still returns an unprobed head; a deferred id skipped; a job
   needing a probe is not in `nextDownloads`; order preserved. **DoD:** every
   case asserted, no engine dependency.

4. **`DownloadEngine` rebuild — scheduler core + `EngineDependencies`
   (TDD: ported Phase 1 tests + new scheduler tests drive it)**
   (GrabberKit/Download + TestSupport). Build `EventCollector`. Rewrite the
   Phase 1 `DownloadEngineTests` scenarios (happy path, non-zero exit →
   `.failed`, cancel kills child, output files resolved) against `QueueEvent` —
   these are the first failing tests. Then the engine: the actor owns one
   ordered `[DownloadJob]` (demoted model); sync mutation methods per the
   invariant; `evaluateSchedule()` after each running both scheduling
   decisions; detached launcher; `recordExit` / a probe-done method re-enter
   and re-evaluate. `events` + `currentSnapshot()` + `hasActiveJobs()`.
   Dedicated `MetadataProbe` instance (probing is **not** capped by
   `maxConcurrentDownloads`). `EngineDependencies` struct + `.live` factory.
   Delete the drain loop and `DownloadJob`'s `@MainActor`/`@Observable`.
   Keep/adapt `pump` / `finish` / `resolveOutputFiles` / `errorClass` /
   `titleStem`. `submit(_:force:prefetchedMetadata:) -> SubmitResult` (duplicate
   check on full `DownloadRequest` equality against **any** job state; prefetched
   metadata fills title/extractor/duration and skips `.probing`). `sizeBytes`
   set from the current process's first `total_bytes`, re-set by a fresh
   process. **Tests:** the ported scenarios pass; `cap == 1` downloads strictly
   sequential; `cap == 2` two downloads concurrent + a third waits, while a
   probe still runs alongside; a burst of 3 fresh URLs pipelines (probe A →
   download A + probe B → …), not stall-at-1; a lowered cap kills nothing; every
   mutation's `revision` strictly increases; progress lines → `.progress`, state
   changes → `.snapshot`; a duplicate request in any state → `.duplicateExists`
   with the right `wasCompleted`; `force: true` → `.queued`, a distinct job;
   prefetched metadata → no `.probing` hop, no probe spawned; `sizeBytes`
   re-set on a resume spawn. **DoD:** the pipelined scheduler drives fake
   downloads to completion under a cap; Phase 1 behaviours hold, asserted via
   `QueueEvent`.

5. **Intents — pause / resume / cancel / remove** (GrabberKit/Download).
   Semantics per § "Intent semantics", including `.part` and `JobLog` file
   effects and the log events. **Tests:** pause a running job → child
   SIGTERMed, `.paused`, excluded from the next `nextDownloads` input, a queued
   job takes the slot; resume → `.queued` at tail, a fresh spawn re-sets
   `sizeBytes`; cancel → `.cancelled`, `.part` + `JobLog` kept, child killed;
   remove a running job → child killed, `.part` + `JobLog` gone, absent from
   the next snapshot; remove a terminal job → gone, absent from a later
   `history.json` projection. **DoD:** all four assert state, queue-membership,
   child-process, file effects.

6. **Force-start** (GrabberKit/Download). One atomic sync mutation per
   § "Intent semantics": head-move + at-cap eviction (oldest-`startedAt` → tail,
   `.part` kept) + mark-running, then one `revision` bump + one `.snapshot`,
   then `evaluateSchedule()`; the victim SIGTERM + forced spawn go to the
   launcher after. Tracks `startedAt`. **Tests:** `running < cap` → nothing
   evicted; `running == cap` → **exactly one** `.snapshot` showing the forced
   job `.running` and the victim `.queued` at the tail simultaneously, victim's
   `.part` kept; two rapid force-starts churn once then stabilise; not in
   `availableActions` on a non-queued job. **DoD:** exact, single-snapshot,
   thrash-free.

7. **Deferred-start seam + systemic halt + `revalidate`** (GrabberKit/Download).
   The sorted `(jobID, notBefore)` list + lazily-created sleep-`Task` (injected
   clock) + `deferStart(_:until:)`; `nextDownloads` already skips deferred ids
   (step 3). `queueHalt` — a `depMissing` spawn/probe failure (exit 127 +
   `"launch failed:"`) sets `.depMissing`, the scheduler stops, the offending
   job goes back to `.queued`. `revalidate()` — re-runs `EnvironmentProbe`,
   clears the halt if deps are back. **Tests:** a deferred job starts only after
   its deadline (clock advanced); earliest deadline wakes first; a nearer
   deadline re-arms; emptied list suspends the task; `shutdown` cancels it; a
   `depMissing` failure → `queueHalt == .depMissing`, offending job `.queued`,
   no further starts; `revalidate()` with deps present → halt cleared, queue
   resumes; `revalidate()` with deps still missing → halt stands. **DoD:** the
   seam fires on a fake clock; the halt stops and `revalidate` resumes the
   scheduler.

8. **`availableActions`** (GrabberKit/Download). Computed per job from state
   (the § "JobSnapshot" table — note `.probing` has no `pause`); gated actions
   never included. **Tests:** each `JobState` → its exact set; a transition
   updates the set in the next snapshot. **DoD:** every state asserted.

9. **`JobLog`** (GrabberKit/Logging). Header block + streamed raw-line append,
   one file per job, §8.5 redaction, delete-on-remove, 200-file cap evicted by
   the owning job's `finishedAt`. Engine writes to it from `pump`. **Tests:** a
   fake run → the file has the header + the streamed lines; redaction applied;
   `remove` deletes it; 201 terminal jobs → the oldest-`finishedAt` job's file
   gone (same job the memory + history caps drop). **DoD:** per-job raw logs
   exist and the three caps evict the same set.

10. **`Persistence`** (GrabberKit/Model). The three `*File` wrappers,
    `PersistedJob` (with `extractor` / `durationSeconds`), `saveQueue` /
    `saveHistory` / `saveColumns` each debounced 500 ms (injected clock),
    projection-compare skip, one `flushNow()` that flushes all three, the load
    table, the 200-cap terminal eviction (by `finishedAt`),
    `PersistedState.failed` → `.unknown(raw:)` on restore, the write-failure log
    + flag, all new `LogEvent` cases. **Tests:** round-trip each file;
    `DownloadRequest` full round-trip equality (video+height, audio+codec,
    container, template, deep folder path); `running`/`probing` clamp to
    `queued`; queue-order preserved on restore (no `addedAt` re-sort); a
    restored `failed` job → `.failed(.unknown(raw:))`; corrupt → empty +
    `persistenceCorrupt`, no throw; `schemaVersion` ahead → empty +
    `persistenceSchemaAhead`; `.progress`-only change → no write; 201 terminal
    jobs → oldest dropped; `columns.json` unknown/missing column per the table;
    a change within the debounce window then `flushNow()` → written; a write
    throw → `persistenceWriteFailed` logged + flag set, next success →
    `persistenceRecovered`; `DebugFlags.resetState` → no loads. **DoD:** every
    load-table row and the debounce / skip / cap / failure behaviours are
    fixture-covered.

11. **Engine ⇄ Persistence wiring + launch resume** (GrabberKit). The engine
    holds `QueuePersisting` (no-op in tests); terminal transitions drive the
    history projection, other changes the queue projection, both debounced.
    `restore(active:history:)` rebuilds the list from the on-disk order (active
    `.queued`, terminal inert), forces `hasGrabbedOnce = true` if any job
    loaded, and `evaluateSchedule()` resumes them. A restored active job with
    `title` + `extractor` + `durationSeconds` skips the re-probe; one missing
    any re-probes. **Tests:** a fake persisting layer records the expected save
    calls at transitions; `restore` with a mixed set → list + first snapshot
    match, on-disk order preserved; a full-metadata restored job → no probe
    spawned, straight to download; a partial-metadata one → probe spawned; a
    restored active job with a fake `.part` resumes not restarts. **DoD:** a
    headless restore → resume → complete cycle passes, with and without
    re-probe.

12. **`RowStore` + `RowModel`** (App). The `@Observable` row model + cached
    strings (recompute only on changed source field; `siteLabel` em-dash until
    `extractor` known); `apply(_:)` two paths + `resync(_:)`; `rows` /
    `visibleRows` (full-list sort/filter, nils last, single sort column) /
    `groups` (empty) / `chipCounts`; queue badge for `.queued` rows;
    `PlaylistGroup` type defined. **Tests:** a `.snapshot` sequence → stable
    `RowModel` identities, only changed fields mutate; a `.progress` event
    patches progress without disturbing identity or non-Progress-sort order;
    filter chip + column filter + sort compose in `visibleRows`; `chipCounts`
    correct; "Needs attention" = `.failed` + `.cooldown`; `resync` rebuilds
    from a snapshot; `siteLabel` em-dash pre-probe, extractor label after.
    **DoD:** fully driven and asserted headless, no SwiftUI.

13. **Confirmation dialog + design-system §4.8** (App + docs). Write §4.8.
    `ConfirmationRequest`, `Confirming`, `AppModel.confirm(_:) async -> Bool`,
    the skinned dialog host in `MainWindow`, notice mode (`cancelTitle == nil`),
    the `suppressionKey` mechanism (unused in Phase 2). **Tests (with
    `FakeConfirmer` for consumers, a rendering check for the host):** `confirm`
    resolves to the user's choice; a suppressed key returns `true` without
    showing; notice mode shows one button; renders in both skins per §4.8;
    Return / Esc / focus behaviour; VoiceOver modal semantics. **DoD:** the
    dialog works in both skins, both modes, and the suppression mechanism
    persists.

14. **`ColumnConfig` + `DownloadsTable` + `DownloadRow` + `ColumnsMenu`** (App).
    The `Codable` column model + invariants; the hand-rolled table — visible
    columns in order, header drag-reorder, single-column sort cycle, per-column
    filter menus, the synced 2-axis scroll, the `LazyVStack` virtualised body;
    `DownloadRow` with the Status pill (+ queue badge), derived Progress bar,
    the fixed-layout action bar (disabled buttons for actions absent from
    `availableActions`); `⊞ Columns` menu (all 16); the filter chip row + "Needs
    attention" badge + "Clear filters" + the two empty-body lines. Persists to
    `columns.json` via `ColumnConfig.didSet → Persistence.saveColumns`.
    **Tests:** invariants enforced on load + mutate; a nil field → em-dash,
    column still sorts; action bar shows the right enabled/disabled buttons per
    state; `columns.json` unknown/missing column; filtered-empty shows the right
    line; a `ColumnConfig` change within the debounce window then `flushNow()` →
    written. **DoD:** every column renders, all controls work, config survives a
    relaunch (headless round-trip; UI in step 16).

15. **`RequestBuilder` + Home restructure** (App). `RequestBuilder.build`
    (public) + the private per-item helper; `RunwayOverrides`. `HomeView`
    restructured — fixed header region + independently scrolling table body;
    first-run centered state; runway `@State` wired through `grab()` into
    `overrides` + `resolved` as `prefetchedMetadata`. **Tests:**
    `RequestBuilder` — prefs-only, full override, partial override → exact
    `DownloadRequest`. **DoD:** the builder is pure and asserted; Home lays out
    with and without the table.

16. **`MainWindow` chrome + `WarningBanner` / `HealthStrip` shells + `AppModel`
    rewire + `QuitCoordinator` + `AppDelegate` + `DebugFlags` + leaf docs +
    smoke** (App + GrabberKit). `WarningBanner` (nil `BannerContent`) + the
    reserved inset; `HealthStrip` + `HealthController` returning one static
    chip; `AppModel` drops `job`, adds `rows` + the guarded consumer task + the
    empty-table state + `pendingConfirmation` + `maxConcurrentDownloads` +
    `DebugFlags`; `reveal()` filter-and-notice; the onboarding-completion →
    `engine.revalidate()` call; `AppDelegate` via
    `@NSApplicationDelegateAdaptor`; `QuitCoordinator` (confirm on
    `hasActiveJobs() || queueHalt != nil` → `flushNow` → `shutdown` → `reply`,
    quit proceeds on flush failure); window minimums + resizability. Update
    `apps/media-grabber/README.md`, `ticket-backlog.md`, `PRIVACY.md` (the
    per-job logs) for the Phase 2 surface; note the drag-reorder and
    multi-select deferrals.
    **Smoke checklist:** queue three URLs → two download at `cap == 2` while a
    third probes, then downloads → pause a running job (it stops, a queued one
    takes the slot) → resume it (runs at the tail) → force-start a queued job (a
    running one is evicted to the tail) → paste an already-queued URL + Grab →
    the duplicate dialog → "Download Again" → a second job + a `(1)` file →
    cancel one (row stays, Done filter) → remove one (row gone) → delete a
    completed job's file on disk, hit Reveal → the "file moved" notice → quit
    with a job running (confirm sheet → children die → relaunch → the queue is
    back in order, the job resumes from its `.part`, restored jobs with full
    metadata do not re-probe) → rename `yt-dlp` away mid-session → the queue
    halts, Onboarding takes over → put it back, finish onboarding → the queue
    resumes → hide / reorder / sort a column, relaunch → the column state
    persisted → toggle a skin → the confirmation dialog restyles. **DoD:** *the
    phase is done* — the checklist passes on a real machine and every prior
    step's DoD still holds.
