# Media Grabber — macOS GUI downloader — Design

**Status:** ready for implementation planning
**Date:** 2026-08-28
**Leaf:** `apps/media-grabber/` (working directory name; product name is
deferred — see §14)

---

- [1. Purpose](#1-purpose)
- [2. Constraints and decisions](#2-constraints-and-decisions)
- [3. Module layout](#3-module-layout)
- [4. Data model](#4-data-model)
- [5. User interface](#5-user-interface)
- [6. Data flow (one download)](#6-data-flow-one-download)
- [7. Resilience and rate-limiting](#7-resilience-and-rate-limiting)
- [8. Logging and diagnostics](#8-logging-and-diagnostics)
- [9. Error handling](#9-error-handling)
- [10. Signing, distribution, dependencies](#10-signing-distribution-dependencies)
- [11. Testing](#11-testing)
- [12. Implementation phasing](#12-implementation-phasing)
- [13. Out of scope for v1](#13-out-of-scope-for-v1)
- [14. Deferred decisions](#14-deferred-decisions)

---

## 1. Purpose

A native macOS app that downloads video and audio from **any site `yt-dlp`
supports** (~1800 extractors), with a real download-queue UI and a
**rate-limiting / resilience layer** as the core engineering focus. Sites
actively block and throttle; the app degrades gracefully, explains every
failure, and never silently drops a job.

**Scope:** a general downloader. One generic flow for every site (URL → probe →
pick from the available formats → download). **YouTube gets full support** on
top: a resolution picker, playlist item selection, and the complete
resilience / cookie / `player_client` machinery in §7. Per-site helpers for
other messy sites (Instagram / Twitter / TikTok auto-cookies, and so on) are a
v1.1 concern.

**Audience:** consumer-facing, including non-technical users. The resilience
machinery is real but stays behind plain language — "downloader + media tools",
not "yt-dlp"; "bot-check shield", not "POT provider"; "couldn't verify you",
not an error code.

Not for: downloading content the user has no right to copy; DRM-protected
streams (Netflix, Spotify — `yt-dlp` refuses, and so does this); a hosted
service; the Mac App Store.

This design supersedes the CLI at `cli/youtube-downloader/`, which is left in
place untouched.

## 2. Constraints and decisions

| Area | Decision |
|---|---|
| UI framework | Swift + SwiftUI |
| Project generation | **Tuist**. Generated `.xcodeproj` / `.xcworkspace` are gitignored; `Project.swift` + `Tuist/` are committed. Tuist version pinned via `.mise.toml`. |
| Targets | `App` (thin SwiftUI layer) · `GrabberKit` (SPM lib: engine, resilience, logging, model — headless-testable) · `GrabberKitTests` · `AppUITests` (later). Names track the final product name once chosen. |
| Min OS | macOS 14 (Sonoma) |
| App shape | Regular windowed app, Dock icon, one window with in-app pages (Home · Preferences · Diagnostics). No separate macOS Settings scene. Onboarding is a full-window takeover. |
| Engine | Shell out to `yt-dlp`, one child process per download; parse `--progress-template` output. |
| Signing | **Ad-hoc signed, hardened runtime OFF** (no paid Apple Developer account). This lets the app spawn Homebrew's ad-hoc-signed binaries. Bundles **no** helper Mach-O — ad-hoc binaries are `SIGKILL`ed on other Macs. See §10. |
| Binary deps | All external, installed by the in-app onboarding flow — nothing bundled. **`yt-dlp`** and **`ffmpeg`** via Homebrew. **POT provider** (`bgutil-ytdlp-pot-provider`) via `pipx` / `uv tool` — a Python package, supervised as a child process on `127.0.0.1`. See §7.2, §10. |
| Concurrency | Adaptive (default 2, Preferences cap 5), rate-limit-aware scheduler — not a fixed semaphore. |
| Persistence | Queue, history, and table column state persisted to `~/Library/Application Support`; interrupted downloads resume on relaunch. |
| Destination folder | Default set in Preferences (user-editable, `~/Downloads`); per-download override in the Home runway's "Save to" slot; last-used remembered. |
| Add flows | Paste into the Home field; clipboard auto-detect on app activation; Services / Share ("Download with…"); drag a URL onto the window or Dock. Every flow lands in the same Home field. |
| Sandbox | **Not sandboxed** — it shells to brew paths, reads browser cookie databases, runs a local POT-provider process, and writes to a user folder. Distributed as an ad-hoc-signed `.app` in a zip via GitHub Releases; the user does a one-time Gatekeeper "Open Anyway". See §10. |
| Privacy | All logs local, no telemetry, no network egress from logging. Redaction rules in §8. |
| Publish | GitHub (this repo), free, MIT. |

### 2.1 Build tooling, CI, and repo fit

- **Generator:** Tuist. Committed: `Project.swift`, `Tuist/`, `.mise.toml` (pins the Tuist version). Gitignored: `*.xcodeproj`, `*.xcworkspace`, `Derived/`, Xcode user state — all scoped to `apps/media-grabber/`.
- **CI:** GitHub Actions on `macos-14`. Pipeline: `mise install → tuist generate → tuist build → tuist test`. The real-network integration tests (§11.2) are env-flag-gated and off by default.
- **Lint / format:** SwiftFormat + SwiftLint, config committed in the leaf; run in CI and as a pre-commit hook.
- **Repo fit:** the root Python `.venv` / `requirements.txt` are untouched — this leaf is self-contained Swift.
- **Shared-code path:** `GrabberKit` is a clean SPM package with no dependency on the `App` target — if another project ever needs its `ProcessRunner` / logging, it can be extracted to its own package repo later. Not a v1 concern.

## 3. Module layout

Directory names use the working name `media-grabber` / `GrabberKit`; they are
renamed to the final product name when §14 resolves.

```
apps/media-grabber/
  README.md                          # catalog leaf readme
  ticket-backlog.md
  PRIVACY.md                         # what the logs contain, all local
  Project.swift                      # Tuist project spec (committed)
  Tuist/                             # Tuist config (committed)
  .mise.toml                         # pins Tuist version
  docs/
    design-system.md                 # visual design tokens + component specs
    mockups/screens.html             # living mockup, all screens, skin/palette switcher
  Sources/
    App/                             # SwiftUI target — depends on GrabberKit
    GrabberKit/                       # SPM library target — no SwiftUI, headless-testable
  Tests/
    GrabberKitTests/
```

### `App` target (thin SwiftUI layer)

- `AppMain.swift` — `@main`, a single `WindowGroup`, no Settings scene
- `AppModel.swift` — root `@Observable`: dependency state, queue, current page, banner, toasts
- `MainWindow.swift` — window shell: brand row, health strip, nav, docked bottom banner, page switch (Home / Preferences / Diagnostics / Onboarding takeover)
- **Home/**
  - `HomeView.swift` — paste field, probe status, runway (Link · Type · Format · Language · Save to), Grab; hosts the Downloads table
  - `RunwaySlot.swift` — one labelled slot (a dropdown or a resolved value) with a filled / hollow state
  - `PlaylistPickerView.swift` — the modal checklist (thumbnail, title, duration; select all / none; filter; live count + size; Add N)
  - `DownloadsTable.swift` — column-model rendering: show/hide, column-header drag-reorder, per-column sort + filter menus, the synced 2-axis scroll, the virtualised row body, the playlist group header + spine (queue-row drag-reorder is deferred — no phase yet)
  - `DownloadRow.swift` — one video row: status pill, progress, contextual action buttons. No expansion.
  - `ColumnsMenu.swift` — the `⊞ Columns` checkbox menu
- `HealthStrip.swift` — the ambient-state chips (shield, engine freshness, online, per-host cooldown). Refreshable chips (`shield`, `engine`) grow a `↻` that runs the background fix (restart the POT provider / upgrade yt-dlp); the online chip is passive. On success a refreshable chip goes green; on failure the chip stays bad (the error toast is Phase 11). The cooldown chip has no `↻` — clicking it opens a why / when-it-clears / Retry-now popover (Retry-now only for a circuit-open host).
- `WarningBanner.swift` — the engine/host-level banner, chosen by a `BannerReason` priority resolver (circuit open, network down, POT provider down). Dependency-missing is the onboarding takeover, not a banner. Host cooldown is the chip + Status cell.
- `Toasts.swift` — the bottom-right toast stack
- **Preferences/**
  - `PreferencesView.swift` — grouped sidebar + pane host
  - `DownloadsSettings.swift`, `AppearanceSettings.swift` (skin + palette pickers), `NetworkSettings.swift`, `CookiesSettings.swift`, `UpdatesSettings.swift`, `LogsPrivacySettings.swift`, `AdvancedSettings.swift` — the 7 panes (contents in `docs/design-system.md` §4.6)
- `OnboardingView.swift` — the first-run / deps-missing checklist (Homebrew, downloader + media tools, bot-check shield, test run); blocks Home until yt-dlp + ffmpeg are present
- `DiagnosticsView.swift` — Run check → report card; Copy report; Copy diagnostic bundle
- **Theme/**
  - `SkinEnvironment.swift` — resolves the active `Skin` + `Palette` into SwiftUI environment values (fonts, radii, colours, elevation modifier)
  - `MotifView.swift` — the reel / orb, driven by an `isActive` flag; honours reduce-motion

History has no separate screen — completed and cancelled jobs stay in the
Downloads table, reached through the "Done" filter chip.

### `GrabberKit` target (engine — everything below is UI-free)

**Onboarding/**

- `EnvironmentProbe.swift` — locate `brew`, `yt-dlp`, `ffmpeg`, `pipx`, and the POT provider; read versions; produce a staleness verdict
- `OnboardingInstaller.swift` — drive first-run setup: Homebrew (show the official install command + Copy, or run it in Terminal.app), then `brew install yt-dlp ffmpeg`, then `pipx install bgutil-ytdlp-pot-provider`; stream progress
- `YtDlpUpdater.swift` — "Update yt-dlp" → `brew upgrade yt-dlp` (or `yt-dlp -U` where brew's copy allows it); surface the result
- `ProcessRunner.swift` — async `Process` launch + line-stream helper (pure, testable)

**PotProvider/**

- `PotProviderProcess.swift` — supervise the pipx-installed `bgutil-pot` server as a child process on `127.0.0.1:<free port>`; health check; restart on crash; stop on app quit
- `PotPluginInstaller.swift` — ensure the yt-dlp POT plugin is present (installed with the pipx package, or into a private `--plugin-dirs`) and pointed at by the engine

**Download/**

- `DownloadRequest.swift` — immutable: url, destFolder, kind, container, template, audioLanguage
- `DownloadJob.swift` — `@Observable` per-row state machine
- `DownloadEngine.swift` — actor: the rate-limit-aware scheduler; spawns one `yt-dlp` per job
- `YtDlpArguments.swift` — `DownloadRequest` + attempt context → argv (with a redaction view)
- `ProgressParser.swift` — progress-template lines → `ProgressEvent`; stderr → `ErrorClass`
- `MetadataProbe.swift` — serialized `yt-dlp -J --no-playlist` (one video) or `-J --flat-playlist` (playlist dump); `MetadataTokenBucket` paces both
- `IntegrityCheck.swift` — ffprobe output vs expected duration → verdict

**RateLimiting/**

- `RateState.swift` — per-host state: `normal | cooldown(until:) | circuitOpen`
- `Backoff.swift` — exponential + full jitter, capped; honours `Retry-After`
- `AdaptiveConcurrency.swift` — raise on a clean streak, drop on throttle
- `MetadataTokenBucket.swift` — ≤ N probe requests per rolling window

**Model/**

- `Preferences.swift` — `@Observable`, UserDefaults-backed (includes `skin`, `palette`)
- `Skin.swift` — `Skin` enum (`.tapeDeck | .aurora`): display / body / mono font, radius scale, border width, elevation style, motif kind
- `Palette.swift` — `Palette` enum (3 per skin) → the full colour token set; `Skin.palettes` lists its three
- `ColumnConfig.swift` — Downloads-table column state: visible set, order, per-column sort direction, active filters. `Codable`, persisted to `columns.json`, debounced.
- `Persistence.swift` — Codable load / save: `queue.json` (jobs + playlist groups), `history.json`, `columns.json` (debounced)

**Logging/**

- `LogWriter.swift` — actor: JSON Lines + `os.Logger` mirror, size rotation
- `LogEvent.swift` — the event enum + schema + redaction helpers
- `JobLog.swift` — per-job raw yt-dlp capture + a header block
- `DiagnosticBundle.swift` — zip the app-log tail + job log + diagnostics report

**Support/**

- `URLDetection.swift` — ask yt-dlp whether an extractor exists (not a regex on `youtube.com`); clipboard sniff; VPN-interface hint
- `NetworkMonitor.swift` — `NWPathMonitor` → the `waitingForNetwork` gate
- `Formatting.swift` — bytes, duration, ETA

Each unit has one job. `DownloadEngine` is the only component that spawns
download processes. `ProcessRunner`, `ProgressParser`, `YtDlpArguments`,
`Backoff`, and `AdaptiveConcurrency` are pure / fixture-testable. Because
everything non-UI lives in `GrabberKit`, the whole engine + resilience +
logging surface is unit-tested without launching the app.

## 4. Data model

### DownloadRequest (immutable; built by the Home runway, or one per item from the playlist picker)

- `url: String`
- `destFolder: URL` — the Preferences default, overridable per download
- `kind: .video(maxHeight: Int) | .audio(codec: AudioCodec)` — `AudioCodec ∈ {m4a, mp3}`
- `container: String?` — `mp4` for video; `nil` lets yt-dlp choose
- `outputTemplate: String` — default `%(title)s.%(ext)s`, from Preferences
- `audioLanguage` — `.unspecified | .original | .code(String)` (Phase 7)
- There is **no** `playlist` / range-syntax field. A playlist becomes N
  `DownloadRequest`s (one watch URL each) from the picker (Phase 8).

### DownloadJob (engine-internal from Phase 2; one per queue entry)

Phase 1 shipped this `@MainActor @Observable`, bound directly by the table.
Phase 2 demotes it to an engine-internal reference model (actor-isolated, not
`@Observable`); the engine emits immutable `JobSnapshot` values on its
`AsyncStream<QueueEvent>` and the UI binds to `RowStore`'s `RowModel`s built
from those. `JobSnapshot` carries the full field set below and is never edited
by a later phase — fields a later phase populates ship defaulted.

- `id: UUID`
- `request: DownloadRequest`
- `title: String?`, `extractor: String?`, `durationSeconds: Int?` — from the probe (or from `prefetchedMetadata` at submit); `extractor` is the Site identity
- `playlistGroupID: UUID?` — shared by items from one picker Add M; playlist rollup is a `RowStore` aggregate (`PlaylistGroup`), not a job field. `playlistIndex` orders children.
- `state: JobState` — `.queued | .probing | .running | .paused | .waitingForNetwork | .cooldown(until:) | .completed | .failed(ErrorClass) | .cancelled`
- `progress: Progress?` — `fraction`, `speedBytesPerSec?`, `etaSeconds?`, `downloadedBytes`, `totalBytes`
- `sizeBytes: Int64?` — the current download process's first-reported `total_bytes`; re-set by a fresh process on resume/restart
- `actualQuality: String?` — Phase 4 (the `IntegrityCheck` ffprobe reads the real resolution)
- `attempt: Int` — Phase 4; `maxAutoRetries` from `Preferences`
- `playerClientUsed: String?` — Phase 7
- `integrityVerdict: IntegrityVerdict?` — Phase 4
- `availableActions: Set<RowAction>` — computed by the engine from `state`
- `outputFiles: [URL]` — resolved on completion (for Reveal in Finder)
- `logPath: URL` — the per-job raw log (`JobLog`, exists from Phase 2)
- `addedAt: Date`, `finishedAt: Date?`

The queue also carries a `QueueSnapshot.queueHalt: QueueHaltReason?`
(`.depMissing` from Phase 2; `.circuitOpen` / `.networkDown` from Phase 6).

### Preferences (`@Observable`, UserDefaults-backed)

- `defaultDestFolder: URL` (default `~/Downloads`)
- `lastUsedDestFolder: URL` — seeds the runway's "Save to" slot
- `skin: Skin` (default `.aurora`), `palette: Palette` (default Aurora / Mint & Iris)
- `maxConcurrentDownloads: Int` (default 3, range 1…6 — a conservative ceiling until Phase 6's circuit breaker; Phase 6 may widen it)
- `defaultKind`, `defaultMaxHeight` (default 1080), `defaultAudioCodec` (default m4a)
- `outputTemplate: String`
- `clipboardAutoDetect: Bool` (default true)
- `cookiesFromBrowser: CookieSource` — `.none | .safari | .chrome | .brave | .edge | .firefox(profile:)` (default `.none`). Cookies are opt-in: nothing reads a browser's sign-in unless the user picks one here or presses Retry-with-cookies on a failed row. The Firefox profile rides inside `.firefox(profile:)`.
- `proxyURL: String?`
- `forceIPv4: Bool` (default false)
- `selfRateLimitKBps: Int?` — optional `--limit-rate`
- `maxAutoRetries: Int` (1…5, default 5) — the per-job auto-retry budget
- `autoCheckUpdates: Bool` (default true) — the daily yt-dlp / app release check
- `verboseLogging: Bool` (default false)

Column state (visible set, order, per-column sort direction, active filters) is
a separate `ColumnConfig`, persisted to `columns.json`.

### Persistence

- `~/Library/Application Support/MediaGrabber/queue.json` — jobs not yet completed (`queued / paused / failed / cooldown`); playlist items carry their group id. Written debounced (500 ms) on every state change.
- `.../history.json` — completed / cancelled jobs, capped at the last 200.
- `.../columns.json` — the Downloads-table column state. Debounced.
- On launch: reload `queue.json`; jobs previously `.running` reset to `.queued` (the yt-dlp `.part` on disk enables resume); history loads read-only; column state loads, or falls back to defaults.
- Destination folders are stored as plain paths (the app is not sandboxed). If sandboxing is ever adopted, switch to security-scoped bookmark data.

## 5. User interface

The full visual design — colour tokens, type scale, radii, spacing, per-skin
rules, and per-component specs — lives in
`apps/media-grabber/docs/design-system.md`. The living mockup with a
skin/palette switcher and every screen is
`apps/media-grabber/docs/mockups/screens.html`. This section is the behavioural
contract.

### 5.1 Skins and palettes

- A **skin** is the visual identity: type, shape language, elevation, and the signature motif. There are two:
  - **Tape Deck** — warm, light. Bricolage Grotesque / DM Sans / DM Mono; 2px outlines and a hard offset shadow; a spinning-tape-reel motif.
  - **Aurora** — dark, luminous. Sora / Inter / JetBrains Mono; hairline borders and a glow; a conic-gradient orb motif.
- A **palette** is a colour variant within a skin — three each, swapping colour tokens only:
  - Tape Deck: **Teal & Rust** (skin default), **Plum & Blush**, **Navy & Aqua**.
  - Aurora: **Mint & Iris** (app default), **Lime & Forest**, **Magenta & Violet**.
- Orientation is fixed per skin — Tape Deck light, Aurora dark. The user picks a skin, then a palette, in Preferences → Appearance.

### 5.2 App chrome

- **Brand row** — the wordmark (motif + name) on the left; nav (`Home · Preferences · Diagnostics`) on the right as in-app page links. The active page has a filled background.
- **Health strip** — below the brand row: small chips carrying ambient state — `bot-check shield`, `engine` (yt-dlp freshness), `online` / `offline`, and a per-host cooldown / circuit chip shown only while a host is cooling or paused. A green dot means ok, amber means attention. A chip in a bad state may grow a `↻` refresh icon at its right edge; clicking it runs that chip's background fix:
  - `shield · offline` → restart the POT provider process, re-run its health check
  - `engine · stale` → `brew upgrade yt-dlp` (or `yt-dlp -U`), re-read the version
  - `engine · missing` (a dependency is gone) → *not a refresh* — routes back to Onboarding as a hard block

  The **online / offline chip is passive** — no `↻`, no re-poll control. A single
  engine-owned, debounced `NWPathMonitor` subscription is the network truth
  (`QueueSnapshot.isOnline`); re-reading the monitor would not change it. On
  success a refreshable chip goes green and the icon disappears. On failure the
  chip stays bad; the error toast is Phase 11. The cooldown chip has no
  `↻`; clicking it opens a popover — which hosts are cooling or paused, the live
  `m:ss` until a cooldown clears, and a Retry-now button only for a circuit-open
  host.
- **Warning banner** — docked to the bottom of the window, floating over the table, with the table reserving bottom padding so its last row never hides under it. Reserved for **engine / host-level** conditions only. Content is chosen by a `BannerReason` priority resolver (`depMissing` > `networkDown` > `circuitOpen`, then `potProviderDown`) — not a `switch` on `queueHalt`. One sentence; the action button is optional (`networkDown` has none). A host cooldown is the chip + Status cell, not a banner. yt-dlp staleness is the engine-freshness chip, not a banner.

### 5.3 Home

- **Hero:** a kicker, a headline, and the paste field. No dashboard or stats widget.
- **First run, no download ever made:** the paste field plus three step cards ("Paste a link · Pick a format · Press Grab") fill the body. There is **no Downloads table** (no headers, filter chips, or Columns button) and **no runway** (there is no link yet).
- **After the first Grab:** the step cards are gone permanently, and the Downloads table renders from then on. The field sits above it; the runway appears when a pasted link resolves and is hidden otherwise.
- **Table emptied later** (every row removed): the table stays, showing a single centred line — "No downloads — paste a link above." The step cards do not return; they are first-run-only.
- **Runway** (the resolve-and-arm pattern) — **hidden until a pasted link resolves.** On resolve, the field shows an inline `✓ <title>` and the runway appears attached below it: a strip of labelled slots — **Link · Type · Format · Language · Save to** — each a filled dot when set, a hollow dot when not. Type / Format / Language / Save-to seed from last-used or Preferences; Language is always filled (YouTube's default track, or Original when that is the Preferences policy and the video has one). Format (video) lists only this probe's offered quality rungs. **Grab** sits at the end of the runway and is **disabled until the link is resolved and downloadable** — every other slot is pre-filled; the user may change any of them before Grab. The "Save to" slot is the per-download destination override. The runway is the entire add flow — there is no separate Add sheet.
- **Playlist:** YouTube watch URLs (even with `&list=`) stay one video. A YouTube `/playlist?list=PL…` page runs one `--flat-playlist` dump; a modal picker opens *before* any rows are added — a checklist (thumbnail, title, duration), Select all / none, a filter-in-playlist field, duplicate warnings, a live `M of N · K already in queue · ≈ duration`, and "Add M". Only checked videos become rows. Mix / Radio / Watch Later / Liked / channel pages do not open the picker. There is no range-syntax field; the engine never runs `--playlist-items`.

### 5.4 Downloads table

- One table, newest on top, **one row per video**. The paste field, filter chips, `⊞ Columns` button, and column header row are a fixed region; the rows scroll independently below (rows virtualised — thousands of rows without full materialisation). When visible columns overflow the width the body and the header row scroll horizontally in sync.
- Above it: filter chips (`All · Downloading · Done · Needs attention`, the last with a count badge; a "Clear filters" button appears when the active filters hide every row) and a `⊞ Columns` button (a checkbox menu, all 16 columns).
- **16 columns, full table in design-system §4.2.3.** Default-visible: Title · Status · Progress · Speed · ETA · Type · Quality · Size · **Actions**. Hidden by default: Site · Added at · Finished at · Duration · Destination · Attempt · Client used.
- Columns are **draggable to reorder**. Actions is pinned last and cannot hide or move; Title cannot hide but can move. Column order, visibility, the active sort, and filters persist.
- **One active sort column** (`↕` cycles asc → desc → off; a new column's `↕` clears the previous); per-column **filter** (`▽` opens a menu) where meaningful; Progress / Speed / ETA / Size are sort-only; Actions is neither. Nil values sort last regardless of direction.
- The Status cell shows the plain-language state (`queued` shows `· #N` position); a failure shows its reason sentence. The Actions column carries the contextual buttons: pause / resume, cancel, **force-start `⏫`**, retry, retry-with-cookies `🔑`, reveal in Finder, open in browser, remove, and show log (opens the raw log file in the default text editor). Every button is laid out; one that does not apply to the row's state renders disabled.
- **There is no per-row expansion, no detail view, and no row selection.** Failure detail is the status reason plus the row actions plus the external log.

### 5.5 Playlist group in the table

A group header row sits above the playlist's videos: a collapse caret, the
playlist name, a rollup (`N items · M done` plus a mini progress bar), and group
actions (Pause all · Retry failed · Cancel all). The children are indented
against one continuous vertical spine; the row dividers between children start
*after* the spine and never cross it. Collapsing the group hides the children;
the header remains, showing the rollup only. This is a grouping row, not a
detail view — nothing expands per video.

### 5.6 Force-start

`⏫` on a queued or cooling row starts it immediately. If the (adaptive)
concurrency cap is full it evicts the **oldest-started** running job and
re-queues it. Force-start **overrides** a host cooldown or open circuit for that
one job and does **not** clear the host's `RateState` — siblings stay gated. A
`.cooldown` job returns to `.queued` (its deferral is cancelled) and then starts.

### 5.7 Notifications — four non-overlapping channels

1. **Toast** (bottom-right, stacked, ~4s auto-dismiss) — download successes (with a Reveal action) and health-chip refresh failures.
2. **Row status + the "Needs attention" chip badge** — per-job download failures. These do **not** toast.
3. **Warning banner** (bottom) — engine / host-level conditions.
4. **Native macOS notification** — a download failure that happens while the app is backgrounded.

### 5.8 Onboarding

A full-window takeover on first run, or whenever `EnvironmentProbe` finds a
required dependency missing. It **blocks Home** until `yt-dlp` and `ffmpeg` are
present. The steps, each with a state icon:

1. **Homebrew** — if missing, show the official install command with a Copy button and an "Open in Terminal" action; re-check on return.
2. **Downloader + media tools** — `brew install yt-dlp ffmpeg`, run in-app with streamed progress. Required.
3. **Bot-check shield** — `pipx install bgutil-ytdlp-pot-provider` (plus the yt-dlp POT plugin). Recommended, not blocking.
4. **Test run** — a canary probe of a known-stable video; green-lights Home.

The exact command is always shown even though the label uses plain language.

### 5.9 Preferences

An in-app page with a grouped left rail and a right pane of `label + control`
fields, each with a one-line helper. Plain-language labels ("At the same time",
not `maxConcurrentDownloads`). Seven panes — Downloads, Appearance, Network,
Sign-in & cookies, Updates, Logs & privacy, Advanced. Full contents are in
`docs/design-system.md` §4.6. Appearance holds the Skin and Palette pickers.

### 5.10 Diagnostics

An in-app page with one primary button, **Run check**, which runs a canary probe
and then shows a report card — rows of `key : value` coloured by verdict:
canary result and time, yt-dlp version and freshness, ffmpeg version, bot-check
shield health and port, cookie source and readability, the detected client, the
`player_client` rotation order, an active cooldown, and network / VPN status.
**Copy report** puts a redacted plain-text block on the clipboard. **Copy
diagnostic bundle** produces the `DiagnosticBundle` zip; that action lives only
here.

### 5.11 Window and quality floor

The window is resizable and remembers its size and position across launches;
minimum width ~760 (the table needs room), default 980×720, centred on first
launch. Quality floor: full keyboard navigation, visible focus, VoiceOver
labels on every icon button, `prefers-reduced-motion` honoured (the motif stops
spinning), and the window usable narrow — the table scrolls horizontally inside
its own container and the page never scrolls sideways.

## 6. Data flow (one download)

1. **Add** — a URL reaches the Home field (paste / drag / Services / clipboard-detect). The runway's Type / Format / Language / Save-to slots seed from last-used or Preferences; the Link slot is still hollow.
2. Classify the URL. YouTube watch → `engine.preview` (`yt-dlp -J --no-playlist --no-warnings`, plus `ExtractorContext`). Title, duration, format list, audio tracks. YouTube `PL` playlist page → `engine.previewPlaylist` (`-J --flat-playlist`, one call, one token). On a video success the field shows `✓ <title>` and Grab arms. On a playlist success the field shows `✓ <playlist> · N items` and the picker opens.
3. The user presses Grab (a single item) or Add M in the picker → one `DownloadRequest` per item is built (playlist items inherit the runway) → a `DownloadJob(state: .queued)` per item is appended (playlist items share a group id and `playlistIndex`) → persisted. Happy-path playlist items skip per-item `-J` when the dump already has title, duration, and extractor.
4. `DownloadEngine`'s scheduler loop: if the host `RateState == .normal`, `running < AdaptiveConcurrency.current`, and the network is up → dequeue the next `.queued` job.
5. `YtDlpArguments` builds the argv: resilience flags (§7) + `--plugin-dirs` (the POT plugin) + the POT provider base URL + cookies + the `player_client` for this attempt. `ProcessRunner` launches; stdout is streamed line-by-line off the main actor.
6. `ProgressParser` parses progress-template lines → `ProgressEvent` → `job.progress` (hopping to the main actor). Raw lines are appended to `JobLog`. Error signatures → `ErrorClass` + `LogEvent`.
7. **Terminal:**
   - exit 0 **and** `IntegrityCheck` passes → `.completed`, resolve `outputFiles`, move to history.
   - non-zero → classify:
     - auto-retryable and `attempt < maxAutoRetries` → `.queued` again after a `Backoff` delay, with the next `player_client` in the rotation.
     - `rateLimited` → the host enters `.cooldown`; the job is set `.cooldown(until:)`; auto-retry after the cooldown.
     - non-retryable (`private`, `unavailable`, `geoBlocked`, `ageRestricted` without cookies) → `.failed(class)`, stop, show a remedy.
8. Persist on every transition (debounced).

## 7. Resilience and rate-limiting

This section is written around YouTube, the hardest case. The mechanisms are
per-host and apply to every site; other sites simply hit fewer of them.
`player_client` rotation and PO tokens are YouTube-specific.

### 7.1 Failure modes handled

- **HTTP 429** (Too Many Requests) — mostly from metadata bursts. Detected in stderr.
- **403 on fragments** — throttling or expired signed URLs. yt-dlp retries fragments.
- **Silent throttling** — the stream is capped to ~50–100 KB/s. Countered with `--throttled-rate`.
- **Bot check** ("Sign in to confirm you're not a bot") — datacenter / VPN IPs, and increasingly plain residential IPs. Countered with the POT provider plus cookies.
- **SABR / PO-token gating (2026)** — YouTube forces Server-Adaptive BitRate streaming and withholds good formats unless a valid proof-of-origin token is present. The `web` client is effectively SABR-crippled. Countered with the local POT provider plus the `tv` / `ios` clients. Residual forced-SABR cases exist (upstream yt-dlp issue #14390) → classified as `sabrGated`, surfaced honestly, no fix available.
- **"Only low-res / audio-only formats offered"** — the visible symptom of the above. Detected by comparing the offered formats to the metadata's expected max height.
- **Geo-block, private, unavailable, age-restricted** — classified, non-retryable (age-restricted is retryable *with* cookies).

### 7.2 Client identity and PO tokens (per attempt)

**POT provider (always on).** `bgutil-ytdlp-pot-provider` is installed via
`pipx` during onboarding — a Python package, so nothing to sign or bundle. The
engine owns `PotProviderProcess` on `127.0.0.1:<free port>` (`ensureShield` /
`restartShield`, `GET /ping`, stop on quit) and points yt-dlp at its POT plugin
via `--plugin-dirs`. yt-dlp then auto-negotiates per-video tokens. Paste and
Grab share one `ExtractorContext` (`engine.preview` and download spawn) so the
quality / language pickers match the first download attempt. This is the single
biggest reliability lever in 2026 — it neutralises most bot-check, SABR, and
"formats missing" failures. If the provider process is down, downloads still
proceed (degraded) and a banner shows it; that is not a `QueueHaltReason`.
`GrabberKit/PotProvider/` is structured so "bundled" vs "external" is a single
swappable resolver if a Developer ID account is ever obtained.

**player_client rotation** — `--extractor-args "youtube:player_client=<c>"`,
rotating across retry attempts. The order, held as the config constant
`PlayerClientRotation.default` so it can change without an app release (v1.1
fetches it from a small hosted JSON):

1. `tv` — the most reliable now; no token needed for many videos
2. `ios`
3. `tv_embedded`
4. `mweb`
5. `web_safari` — last; the most likely to be SABR-gated

`web` (plain) and `android` are skipped (SABR-crippled / frequently blocked).
`job.playerClientUsed` records the winner.

**Cookies from browser** — `--cookies-from-browser <choice>`, opt-in, default
`.none`. `cookieReadFailed` fires on a direct user-requested cookie read that
failed — a chosen browser in Preferences, or the Retry-with-cookies (`🔑`)
action on a failed row. `CookieResolver` resolves the argument at spawn time
(Firefox `profiles.ini` enumeration, a Safari Full-Disk-Access probe-read) and
`YtDlpArguments` redacts the spec in logs.

> A later always-on-cookies model would default `cookiesFromBrowser` to
> `.safari`, attempt the cookie read on every download, silently fall back to no
> cookies on a read failure, and classify `cookieReadFailed` only if the
> cookieless download then also fails. `CookieResolver` is built to support that
> unchanged.

**User-Agent** — aligned to the chosen client; a small rotating pool.

### 7.3 Cookie edge cases

- **Safari** — needs the app to have **Full Disk Access** (it reads the Safari container's `Cookies.binarycookies`). The check is a just-in-time probe-read from the Preferences pane — a failed read shows a `--warn` status row with a System Settings deep link to the Full Disk Access pane. No onboarding step.
- **Chrome / Brave / Edge** — cookies are Keychain-encrypted; the first use triggers a Keychain prompt. Chrome 127+ **app-bound encryption** prints no error — it is detected from a `Extracted 0 cookies` line on a run that carried a cookie argument and then failed downstream → `cookieReadFailed`; the "Learn more" link covers the fix (a different profile, or Safari / Firefox).
- **Firefox** — reads `cookies.sqlite`; multiple profiles need `firefox:PROFILE`. Enumerate the profiles and let the user pick in Preferences.
- **Locked database** — an open browser can lock it; yt-dlp usually copies first but can fail → `cookieReadFailed`, with a manual Retry / Retry-with-cookies on the row.
- **Recommended setup** (surfaced as a Preferences tip): a dedicated browser profile signed into YouTube, kept closed while downloading.

### 7.4 Scheduler and pacing

- **`RateHost`** — a total, URL-derived canonical key. YouTube properties
  (`youtube.com`, `youtu.be`, `m.youtube.com`, `music.youtube.com`,
  `gaming.youtube.com`, `youtube-nocookie.com`) fold into one `youtube` bucket;
  every other host is its own bucket after a `www.` strip. Unparseable URLs map
  to `.unresolved`.
- **Per-host `RateState`** — `normal | cooldown(until:strikes:) | circuitOpen`.
  The cooldown ladder reuses `Backoff` fed the host strike count (full jitter,
  same ladder + cap as per-job retry). A strike is only `ErrorClass.rateLimited`
  (HTTP 429 or a `--throttled-rate` abort), including a **terminal** 429 that
  exhausts the job's retry budget.
- **Adaptive concurrency** — one global cap. Starts at 2, `+1` per 5 consecutive
  clean completions from any host up to the Preferences cap, drops to 1 on any
  strike from any host. Per-host caps are a backlog item.
- **Circuit breaker** — per host. After `circuitStrikeThreshold` (default 4)
  consecutive strikes with no clean success, that host goes `circuitOpen`: no
  auto-retry, siblings stay `.queued` behind `blockedHostIDs`, a banner tells
  the user to wait / add cookies / turn off a VPN. Recovery is user-only
  (`resetCircuit` / `resetAllCircuits`). `queueHalt.circuitOpen` is a derived
  summary ("nothing startable is moving because of a breaker"), not a stored
  global halt.
- **Probes** are gated on the same per-host block (`blockedProbeHostIDs`) and on
  the hard `.networkDown` halt. A cooling YouTube does not get fresh metadata
  bursts; a healthy other host still does.
- **MetadataTokenBucket** — ≤ N probe requests per rolling 60 s (N small, e.g. 3). Playlist expansion is one `--flat-playlist` call, never N calls. Large playlists drip.
- **Backoff** — exponential with **full jitter** (`random(0, base)`), sequence 30 → 60 → 120 → 300 → 600 s, then holding at 600. Honours an explicit `Retry-After` when yt-dlp surfaces it. Per-job path for non-rate-limit auto-retries; host cooldown is a separate `deferStart` caller.

### 7.5 Download-level flags (always)

`yt-dlp`'s in-invocation retry / pacing controls, on every download.
**Bounded**, not infinite — a hard failure must exit `yt-dlp` and reach the
engine's classifier + `Backoff` within a knowable time (~45 s worst case)
rather than hang inside `yt-dlp`. The values are a tuning constant
(`YtDlpTuning`, env-overridable via `MG_YTDLP_*`, no UI), defaulting to:

`--retries 3 --fragment-retries 10 --socket-timeout 30 --retry-sleep linear=1:10:2 --throttled-rate 100K --file-access-retries 5 --no-part-hint --sleep-requests 1 --sleep-interval 1 --max-sleep-interval 5`

`--retries 3` (not `infinite`) so a transient error becomes a non-zero exit the
classifier can act on; `--socket-timeout 30` so a dead link fails instead of
hanging; a `--throttled-rate` abort classifies as `rateLimited` and takes the
backoff schedule. This layer composes with the per-job `maxAutoRetries` (§7.9,
which re-invokes `yt-dlp` after an exit) rather than one hiding the other.

### 7.6 Download-level flags (adaptive)

- `--concurrent-fragments` — 4 when the job's host `RateState == .normal`, 1 otherwise. `tuning`-controlled (`concurrentFragmentsNormal` / `concurrentFragmentsThrottled`), read at spawn. Independent of the engine's job-count adaptive cap.
- `--limit-rate` — from `Preferences.selfRateLimitKBps` when set (self-throttling reduces re-extraction churn).
- `--force-ipv4` — from `Preferences.forceIPv4`, or auto-tried as a retry variant after repeated connection failures.
- `--proxy` — from `Preferences.proxyURL` when set.

### 7.7 Resume and integrity

- On resume: verify the `.part` and `.ytdl` sidecar exist and are consistent; if the format URL rotated and yt-dlp cannot resume, restart that file clean rather than loop.
- **IntegrityCheck** — after exit 0, run `ffprobe` on the outputs; if the duration is materially short of the metadata duration, or a file is unplayable → `.failed(incomplete)` with a re-download action.

### 7.8 Network and environment

- **NetworkMonitor** — one engine-owned, debounced `NWPathMonitor` wrapper. No
  reachability probe. Offline after `networkOfflineGraceSeconds` (default 2) of
  continuous `.unsatisfied`; online after `networkOnlineSettleSeconds` (default
  2) of continuous `.satisfied`. The committed truth is `QueueSnapshot.isOnline`
  — the App layer never subscribes on its own. Offline is a hard
  `queueHalt.networkDown`: running / probing jobs park as `.waitingForNetwork`
  (attempt and `.part` kept); queued jobs stay queued. Online clears that halt
  and re-queues parked jobs at the tail. Retries are not burned against a dead
  link.
- **VPN hint** — a bot-check error plus an active VPN / utun interface → tell the user plainly: disable the VPN or add cookies.
- **yt-dlp staleness** — on launch and once daily, compare the resolved yt-dlp's `--version` to the latest GitHub release date; if more than ~14 days stale, the engine-freshness `HealthStrip` chip goes amber with a `↻` that runs `brew upgrade yt-dlp` (or `yt-dlp -U`). YouTube breakage is usually just a stale binary, so this is high-value. Staleness is a chip, never a banner.
- **POT provider health** — if the `bgutil-pot` process is unhealthy or down, a banner: "Bot-check protection is offline — some downloads may fail or be low-res" with a Restart button.

### 7.9 Failure UX

- Every terminal state is visible with a reason sentence and actions: **Retry**, **Retry with cookies**, **Show Log**, **Remove**, **Open in browser**.
- The per-job auto-retry budget is shown ("attempt 3 of 5"); after the budget, stop and wait for the user.
- **Retry failed** — a bulk action, global and per playlist group, available after a cooldown ends.
- Failure surfacing follows the four channels in §5.7.
- **Graceful quit** — active downloads on quit: a confirm dialog, then SIGTERM to yt-dlp (leaving `.part`), persist, resume next launch.

## 8. Logging and diagnostics

### 8.1 App log — structured, for support and later analysis

- `~/Library/Logs/MediaGrabber/app.log` — **JSON Lines**, one event per line.
- Mirrored to macOS unified logging via `os.Logger` (subsystem `app.<owner>.media-grabber`; categories `engine`, `scheduler`, `deps`, `ui`, `persistence`).
- Line schema: `ts` (ISO8601), `level` (`debug | info | warn | error`), `category`, `event` (a stable key, e.g. `job.state_changed`, `ratelimit.cooldown_entered`, `probe.completed`, `ytdlp.version_checked`), `jobID?`, `fields` (an event-specific dict).
- Rotation: 5 files × 5 MB. `LogWriter` is an actor (serialized writes; call sites never block).
- Default level `info`; `Preferences.verboseLogging` (or a `defaults write` key) raises it to `debug`.

### 8.2 Events logged (for analysis)

- Every job state transition, with a reason.
- Every probe: host, wall time, result (ok / `ErrorClass`), is-playlist, item count.
- Every yt-dlp process: launch (argv **redacted**), exit code, wall time, bytes, average speed, `player_client` used.
- Every rate-limit event: trigger (`429` / `throttle` / `botCheck`), host, concurrency at the time, cooldown length, backoff attempt number.
- Scheduler decisions: concurrency raised / lowered (from → to, and why); circuit breaker open / close.
- Dependency checks: found?, versions, staleness verdict.
- Error classification: the raw yt-dlp error (truncated) → the mapped `ErrorClass`.
- Completion integrity: expected vs actual duration, verdict.
- App lifecycle: launch; quit (clean / with N active); queue restored (N jobs).

### 8.3 Per-job log — raw, for support

- `~/Library/Logs/MediaGrabber/jobs/<jobID>.log` — verbatim yt-dlp stdout + stderr, preceded by a header: the **redacted** argv, yt-dlp version, ffmpeg version, cookie source, chosen `player_client`, timestamp.
- Kept for completed jobs; pruned with the history cap (200 jobs) and a 30-day age cap.
- "Show Log" on a row opens this file in the default text editor. "Copy diagnostic bundle" (Diagnostics page only) → `DiagnosticBundle` zips the app-log tail, the most recent or selected job's log, and the Diagnostics report.

### 8.4 Diagnostics panel

One click runs a **canary**: probe a known-stable video and report the yt-dlp
and ffmpeg versions, cookie status, detected client, `player_client` rotation
order, whether a 429 cooldown is currently active, and network status. The
output is copyable.

### 8.5 Privacy (mandatory)

- **Redacted in all logs:** cookie contents; proxy credentials (the host is kept, user / pass removed); any `--username` / `--password`; absolute paths under `/Users/<name>` rewritten to `~`.
- **Logged in the clear (needed for debugging):** video URLs, video / playlist titles, the destination folder (as `~/…`). Documented in `PRIVACY.md`.
- **No telemetry. No network egress from the logging subsystem. Ever.** Logs never leave the machine unless the user manually shares a diagnostic bundle.
- The diagnostic bundle re-runs redaction at zip time and lists exactly what it contains before saving.

## 9. Error handling

- `ProcessRunner` never throws into the UI — every failure becomes a `JobState.failed(ErrorClass)` plus a `LogEvent`.
- `ErrorClass` enum: `rateLimited`, `botCheck`, `sabrGated`, `formatsMissing`, `cookieReadFailed`, `geoBlocked`, `private`, `unavailable`, `ageRestricted`, `networkDown`, `diskFull`, `permissionDenied`, `incomplete`, `depMissing`, `potProviderDown`, `unknown(raw)`. Drives the UI copy and which actions are offered.
- The enum ships whole (Phase 1); its *emit paths* and *failure UI* are staged (§12.2). Phase 2 wires the terminal path to emit `incomplete`, `diskFull`, `permissionDenied`. Phase 4 adds the classifier signatures for the generic set — `rateLimited`, `geoBlocked`, `private`, `unavailable`, `ageRestricted`, `networkDown` — and the `FailurePresentation` model: a value keyed off `ErrorClass` giving each case its plain-English reason sentence and the row actions it offers (one switch). `rateLimited` carries an optional `Retry-After`. Phase 5 wires `cookieReadFailed`; Phase 7 emits `botCheck`, `sabrGated`, and `formatsMissing` on jobs and fills all four YouTube `FailurePresentation` arms — `potProviderDown` is chrome-only (banner + chip), never a row terminal state.
- Engine-level: the circuit breaker → `circuitOpen` banner, no auto-retry. Recovery is user-only (`resetCircuit` / `resetAllCircuits`).
- App crash mid-download: the `.part` on disk plus the persisted `.queued`-on-relaunch → resume.
- Disk full / permission denied on the destination → classified, actionable message.
- A dependency removed mid-session → caught on the next launch; a running job fails cleanly with `depMissing`.

## 10. Signing, distribution, dependencies

**No paid Apple Developer account.** This shapes everything below.

- **Not sandboxed, hardened runtime OFF, ad-hoc signed** (`codesign -s -`). Hardened runtime is only needed for notarization (not happening) and it *blocks* spawning Homebrew's ad-hoc-signed binaries — so it stays off. An ad-hoc app **without** hardened runtime spawns brew / pipx binaries fine.
- **Bundle no helper Mach-O.** Ad-hoc-signed binaries are `SIGKILL`ed by the kernel on any machine other than the one that signed them. So `yt-dlp`, `ffmpeg`, and the POT provider are **never** in the `.app` — all installed externally where their own toolchain already signed them.
- **Distribution:** the ad-hoc-signed `.app` zipped and attached to GitHub Releases. No DMG or `.pkg` (a signed one also wants an account).
- **First launch on another Mac** (macOS 15 Sequoia removed right-click → Open): the user hits "app is damaged / unverified" → **System Settings → Privacy & Security → Open Anyway** (the button shows for ~1 h after a failed launch), or `xattr -dr com.apple.quarantine /Applications/<App>.app`. One-time. Documented in the leaf README; the repo has a `quarantine-clear` tool.
- `Info.plist`: `LSMinimumSystemVersion 14.0`; `CFBundleURLTypes` for a custom scheme (Services / other-app handoff); a Services declaration for "Download with …".
- **If a Developer ID account is ever obtained:** switch to hardened runtime + notarization, bundle yt-dlp / ffmpeg / the POT provider, adopt Sparkle, and ship a DMG. The dependency layer (`EnvironmentProbe`, `PotProviderProcess`) is structured so "bundled" vs "external" is a single swappable resolver.

### 10.1 Dependency acquisition — the in-app onboarding

There is no separate installer. First run shows the onboarding screen (§5.8),
which gets the environment ready:

1. **Homebrew** — if `brew` is missing: show the official `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` with a **Copy** button and an **Open in Terminal** action. Re-check on return.
2. **yt-dlp + ffmpeg** — `brew install yt-dlp ffmpeg`, run from the app with a streamed progress view.
3. **POT provider** — `pipx install bgutil-ytdlp-pot-provider` (or `uv tool install`). A pure Python package, so no Mach-O signing issue. Installs the yt-dlp POT plugin alongside.
4. **Ready check** — a canary probe of a known-stable video; green-lights the main UI.

Ongoing: `EnvironmentProbe` re-runs on launch; a missing or broken dependency
routes back to the relevant onboarding step, not a crash.

### 10.2 App self-update

A **GitHub-release check** (not Sparkle — Sparkle wants signed updates). On
launch, throttled to daily, hit the Releases API; if there is a newer release,
show a non-blocking "New version — download" that opens the release page. The
user replaces the app manually and redoes the one-time Gatekeeper step. Revisit
Sparkle if a Developer ID account is obtained.

## 11. Testing

Xcode / Tuist test targets; `tuist test` runnable. Each phase (§12) has its own
manual smoke checklist.

### 11.1 Pure units (no network)

- `ProgressParser`: fixture yt-dlp progress lines → `ProgressEvent`s.
- `ProgressParser` error classification: fixture stderr → `ErrorClass`.
- `YtDlpArguments`: `DownloadRequest` + attempt context → the expected argv (including plugin-dirs, POT URL, the `player_client` for the attempt number); **and** the redacted view.
- `EnvironmentProbe`: parse `brew` / `yt-dlp` / `ffmpeg` / `pipx` presence and versions from fixture output; the staleness verdict.
- `PlayerClientRotation`: attempt N → the correct client.
- `PotProviderProcess`: health-check parsing; the restart-on-crash logic (with a fake process).
- `Backoff`: jitter within bounds, the sequence, the cap, `Retry-After` honoured.
- `AdaptiveConcurrency`: the state machine (streak up, throttle down).
- `MetadataTokenBucket`: the rate enforced over a rolling window.
- `Persistence`: queue / history round-trip; `.running` → `.queued` on reload.
- `LogEvent` redaction: cookies, credentials, home-dir paths.

### 11.2 Integration (opt-in, real network; gated by `MG_LIVE_TESTS=1`; CI skips by default)

- Probe plus a tiny download of a known Creative-Commons video (a Big Buck Bunny clip).

### 11.3 Full-v1 manual smoke checklist (in the leaf)

- Add via each of the four flows; a playlist add via the picker modal; cancel mid-download; quit-with-active then relaunch (resume); first-run onboarding (Homebrew + brew install + pipx); force a 429 (low sleep, high concurrency) and watch the cooldown UI, the banner, and the circuit breaker.

The 429-forcing item is **Phase 6**'s smoke test — Phase 6 owns `RateState`,
the cooldown UI, the banner cases, and the circuit breaker.

## 12. Implementation phasing

The app is built **version over version**, not module by module. Each phase is a
working app that does more than the previous one — it can be launched, used,
tested, and stopped at any phase boundary. Within a phase, work proceeds module
by module, but a phase only closes when those modules connect into a working
build.

**A phase is done when:** its DoD is met · `tuist test` is green · its manual
smoke checklist passes on a real machine · a commit is tagged `phase-N`.

**Planning cadence.** This section lists every phase as a one-paragraph stub.
When a phase is reached its full detail is written to its own
`docs/superpowers/specs/<topic>.md`, then a `docs/superpowers/plans/` file, then
it is built. Later phases are refined by what the earlier ones teach. Phase 1
(`specs/archived/core-download-pipeline.md`) is built. A phase's spec and plan
move to `specs/archived/` and `plans/archived/` once it is built; the living
reference docs (this file, `apps/media-grabber/docs/design-system.md`) are not
archived.

**Scoping rule (every phase).** When detailing a phase, each concern that comes
up is either *in* that phase or *deferred*. If in: it is built to its
final-app form — no stub a later phase must replace. If deferred: a one-line
hint (a few words — "review X", "plan Y") is added to the stub of the phase
that will own it, so it resurfaces when that phase is detailed. A phase already
marked built is closed — later work may change its code as part of the current
phase's rework, stated plainly as such, but its past choices are not
relitigated.

**Splitting a phase.** If a phase grows too large to detail or build as one
unit, split it into **new sibling phases** — insert a phase and renumber every
later one up (never `4a` / `4b`). Each resulting phase is still an
independently buildable, working-app-at-its-boundary increment. Complete the
design and spec for the first split phase in dependency order; mark the
remaining ones "in progress" and detail them at their normal turn. Renumber
this list and §12.2 in the same pass.

Everything non-UI lives in `GrabberKit` and is headless-testable. TDD
throughout: the test comes before the implementation for every unit.
Real-network tests are gated behind `MG_LIVE_TESTS=1` and are off in CI;
manual smoke checklists cover the rest.

### 12.1 Phases (intent — detailed when reached)

Eleven phases. The boundaries are **dependency cuts**: each phase is picked as
soon as everything it needs is built, and its scope is drawn so that no work
item inside it waits on a work item in a later phase. A phase that lays out a
shell (a banner, a chip strip, a pane, an enum) does so complete; later phases
add cases and wiring, never relayout — §12.2.

- **Phase 1 — Core download pipeline.** Onboarding installs `yt-dlp` / `ffmpeg` (and, non-blocking, the POT provider `pipx` package); paste one URL → the title resolves → the runway arms on defaults → Grab → a live progress bar → a saved file with Reveal. Aurora / Mint & Iris only, no picker. No queue, persistence, resilience, playlist, cookies, running POT provider, Preferences UI, Diagnostics, toasts, or banner. Built — full detail in `docs/superpowers/specs/archived/core-download-pipeline.md`.

- **Phase 2 — Queue foundation and window chrome.** The engine owns the queue: `DownloadEngine` holds the ordered job list and the scheduler loop, and emits `Sendable` `JobSnapshot` values on an `AsyncStream`; `AppModel` consumes the stream into `@Observable` row view models the table binds to; user intents (pause, cancel, force-start, reorder, remove) are `async` calls into the engine. The scheduler loop starts a job when `running < Preferences.maxConcurrentDownloads` — one condition, written so later phases add more (`&& host.rateState == .normal && !circuit.isOpen`) rather than rewrite it. The Downloads table (columns, show / hide, drag-reorder, per-column sort + filter, filter chips), the `ColumnConfig` model, the full contextual row-action bar (every button laid out; actions with no engine yet gated by a capability flag), force-start (`⏫`, round-robin). `Persistence` for `queue.json` and `columns.json` (debounced) — on launch the queue reloads and `.running` jobs reset to `.queued` (the yt-dlp `.part` enables resume); graceful quit (confirm dialog → SIGTERM → persist → resume next launch). In `MainWindow`: the empty `WarningBanner` shell (renders a sentence + one button; no cases yet) and the empty `HealthStrip` shell (a row of chips; no chips yet). `ErrorClass` gains `incomplete`, `diskFull`, `permissionDenied` — cases the engine's terminal path can already emit.

- **Phase 3 — Preferences screen (shipped).** The 7-pane `PreferencesView` (design-system §4.6) over the `@Observable Preferences` model — fixed-height window, left rail never scrolls, right pane scrolls. Filled panes: Downloads (folder, concurrency 1–6, retries, media type, video quality, audio format, filename-format presets + custom, clipboard toggle), Appearance (Theme + Palette as `SkinnedSegment` / swatches), Network (proxy / Force IPv4 / speed limit), Logs & privacy, Advanced (reveal folders, reset columns, reset settings via the confirmation dialog). Sign-in & cookies and Updates ship as stepless panes (title + sub + one "coming in a later update" line). Two reusable skinned controls built this phase — `SkinnedSegment` (equal-width, hug-content, flush-right) and `SkinnedPicker` (popover, not a modal; content-sized width clamped to 340pt) — also replace the native `Menu` dropdowns on the Home runway. New `Preferences` fields: `detectClipboardLinks`, `proxyURL`, `forceIPv4`, `speedLimitKBps` (Int, default 0), `lastVideoHeight` / `lastMediaType` / `lastAudioFormat` (runway last-selected, seeded via `runwaySeed(from:)`). `GlobalDownloadOptions` in `GrabberKit` + `YtDlpArguments` wiring for `--proxy` / `-4` / `--limit-rate`, read off `preferences` by `DownloadEngine` at spawn. Concurrency note (warn glyph + `--dim` line) when the cap is lowered below the live running count — no new drain logic, the Phase 2 scheduler drains on its own. `AppModel.Page.preferences(PreferencesPane = .downloads)` deep-link seam. Pre-release vocabulary sweep: `Skin` → `Theme` end to end (`SkinKind` → `ThemeKind`, `ResolvedTheme` collapsed into `Theme`), `AudioCodec` → `AudioFormat`, `KindSelector` → public `MediaType`, and the `Preferences` field renames (`defaultDestFolder` → `defaultDownloadFolder`, `defaultMaxHeight` → `defaultVideoHeight`, `outputTemplate` → `filenameTemplate`, `maxAutoRetries` → `maxAutoRetries`, etc.). Tape Deck `--warn` darkened to WCAG AA (`#9C5A00` / `#9A6410` / `#8E6318`).

- **Phase 4 — Retry and error classification (shipped).** Spec + plan:
  `docs/superpowers/specs/archived/2026-09-01-media-grabber-phase-4.md`,
  `docs/superpowers/plans/archived/2026-09-01-media-grabber-phase-4.md`. The generic
  `ErrorClass` cases (§9 — `rateLimited`, `geoBlocked`, `private`, `unavailable`,
  `ageRestricted`, `cookieReadFailed`, `networkDown`, `depMissing`, `unknown`)
  modelled as a `FailurePresentation` value keyed off `ErrorClass` — a
  plain-English reason sentence and the row actions each case offers, one switch
  extended by Phase 7's YouTube cases with no relayout; `ErrorClass` also gains a
  stable `key` string. `rateLimited` widens to carry an optional `Retry-After`.
  The `retry` and `show-log` row actions wired live in the Phase 2 action bar
  (force-start already live from Phase 2); `show-log` opens the per-job `JobLog`
  and reuses the `revealTargetMissing` notice pattern for a gone file. The
  per-job auto-retry budget (`Preferences.maxAutoRetries`, its control shipped
  Phase 3): an auto-retryable failure (`rateLimited`, `networkDown`,
  `incomplete`, `unknown`) with `attempt < budget` re-queues on the `Backoff`
  schedule; `diskFull` / `permissionDenied` / `cookieReadFailed` offer a manual
  Retry only; the rest are non-recoverable. The Retry button splits in the
  engine: a usable `.part` plus a transient class (`networkDown` / `incomplete`
  / `unknown`) **resumes** (keeps `.part` and `attempt`, logs `jobResumed`);
  otherwise it **retries** from scratch (deletes `.part`, resets `attempt`, logs
  `jobRetried` — the event the diagnostics report counts). `Backoff` (full
  jitter over a ladder + cap, integer `Retry-After`) — the first caller of the
  Phase 2 `deferStart` seam, logged via `DeferReason.backoff(attempt:)`. Every
  retry / pacing number — the ladder, the cap, the §7.5 `yt-dlp` flags — lives
  in one env-overridable `EngineTuning` constant (no UI, `MG_*` keys for
  testing). `IntegrityCheck`
  (ffprobe duration vs the probe's `durationSeconds` → `incomplete` when
  materially short — consuming a retry attempt; populates
  `JobSnapshot.integrityVerdict`; the same call reads the real resolution into
  `JobSnapshot.actualQuality` so the Quality column shows `1080p → 720p`);
  degrades to `IntegrityVerdict.skipped` when ffprobe or the expected duration is
  missing. `EnvironmentReport` gains
  `ffprobe` (derived from the `ffmpeg` location, non-blocking); the every-launch
  re-probe is the Phase 2 path. A restored `.failed(.unknown(raw:))` job is
  **not** re-classified on retry — the re-queue is itself the fresh attempt. A
  `rateLimited` result retries on the plain `Backoff` schedule — no per-host
  state (Phase 6).

- **Phase 5 — Cookies (shipped).** Spec + plan:
  `docs/superpowers/specs/archived/2026-09-02-media-grabber-phase-5.md`,
  `docs/superpowers/plans/archived/2026-09-02-media-grabber-phase-5.md`. `CookieSource` (`.none | .safari | .chrome | .brave | .edge | .firefox(profile:)`) and `CookieResolver` (Firefox `profiles.ini` enumeration, a Safari Full-Disk-Access probe-read, spawn-time argument resolution) in a self-contained `GrabberKit/Cookies/` unit. Opt-in — `Preferences.cookiesFromBrowser` default `.none`. The Sign-in & cookies pane filled: browser picker, Firefox-profile picker (shown at 2+ profiles), a just-in-time Full Disk Access status row + System Settings deep link (Safari only), a "Learn more" link, the recommended-setup tip. `--cookies-from-browser` threaded through `YtDlpArguments` and redacted in logs. `cookieReadFailed` classifier — stderr signatures plus an `Extracted 0 cookies` + downstream-failure override (the Chrome app-bound-encryption case). The `🔑` Retry-with-cookies row action, offered on `cookieReadFailed` / `ageRestricted` / `private`; `engine.retryWithCookies` does a from-scratch retry with a persisted `job.forceCookies`. `CookieHelpURL`. No Full-Disk-Access onboarding step — onboarding stays 4 steps. Needs Phase 4's `ErrorClass` set and live action bar; does not need rate limiting.

- **Phase 6 — Rate limiting and circuit breaker (shipped).** Spec + plan:
  `docs/superpowers/specs/archived/2026-09-04-media-grabber-phase-6.md`,
  `docs/superpowers/plans/archived/2026-09-04-media-grabber-phase-6.md`. `RateHost` +
  `RateState` per host (`normal | cooldown | circuitOpen`); cooldown ladder
  reuses `Backoff` on the host strike count; a per-host circuit trips on
  `circuitStrikeThreshold` consecutive `rateLimited` strikes (terminal 429s
  included) with user-only recovery. One global adaptive cap (start 2, streak
  up, any strike → 1) feeds `SchedulerInput.cap`; `blockedHostIDs` /
  `blockedProbeHostIDs` gate downloads and probes — no scheduler-loop rewrite.
  Only the job whose exit caused the current strike enters `.cooldown`; siblings
  stay `.queued`. `forceStart` overrides a host block for that one job without
  clearing `RateState`. Debounced `NetworkPathMonitoring` parks running jobs as
  `.waitingForNetwork` and publishes `QueueSnapshot.isOnline`. `queueHalt` gains
  derived `.circuitOpen` and hard `.networkDown`; `revalidate()` stays
  deps-only (`resetCircuit` / `resetAllCircuits` are their own APIs).
  `HealthController` emits the online chip and the cooldown/circuit popover chip
  (`ChipInteraction.popover`, `HealthChip.countdownUntil` as data).
  `BannerReason` priority resolver drives `WarningBanner` (`networkDown` has no
  button). Status cell + cooldown chip show a live `m:ss` via `TimelineView`.
  `--concurrent-fragments` is 4 when the host is `.normal`, 1 otherwise. Rate
  state is in-memory only. Per-host adaptive concurrency is a backlog deferral.
  Engine-freshness chip is Phase 10.

- **Phase 7 — YouTube hardening (shipped).** Spec + plan:
  `docs/superpowers/specs/archived/2026-09-07-media-grabber-phase-7.md`,
  `docs/superpowers/plans/archived/2026-09-07-media-grabber-phase-7.md`.
  Engine-owned `PotProviderProcess` + `PotPluginInstaller`; `ExtractorContext`
  shared by `engine.preview` and download spawn; `player_client` rotation
  (`tv → ios → tv_embedded → mweb → web_safari`); probe format-list parsing;
  runway **Language** slot + quality rungs restricted to this probe; Downloads
  pane **Audio language** policy (`YouTube default` | `Original`); YouTube
  `ErrorClass` emit (`botCheck`, `sabrGated`, `formatsMissing`) + copy; VPN hint
  on bot-check; shield `HealthStrip` chip + `↻`; `potProviderDown` banner (not a
  queue halt). Parked follow-up: refresh engine `shieldStatus` after shield
  crash auto-recovery so chip/banner track live provider status.

- **Phase 8 — Playlist (shipped).** Spec + plan:
  `docs/superpowers/specs/archived/2026-09-08-media-grabber-phase-8.md`,
  `docs/superpowers/plans/archived/2026-09-08-media-grabber-phase-8.md`.
  `PlaylistLink` classifies paste before probe. YouTube watch = one video
  (`--no-playlist`, even with `&list=`). YouTube `/playlist?list=PL…` = one
  `--flat-playlist` dump → `PlaylistPickerView` (checklist, select all / none,
  filter, duration footer, duplicate warnings) → N independent jobs sharing
  `playlistGroupID` + `playlistIndex`. Group header + spine + group actions are
  a `RowStore` aggregate; `MetadataTokenBucket` paces probes; per-request probe
  cancel. Mix / Radio / channel `/videos` / Watch Later / Liked stay out.
  Items inherit the Home runway's quality cap and `audioLanguage`. Cancel-all
  uses `ConfirmationRequest` `suppressionKey: "playlist-cancel-all"`.
  `screens.html` §5 depicts picker + group + skinned runway. Built out of
  numeric order ahead of Phase 7 (both now shipped).

- **Phase 9 — Add flows (design complete).** Spec + plan:
  `docs/superpowers/specs/2026-09-10-media-grabber-phase-9.md`,
  `docs/superpowers/plans/2026-09-10-media-grabber-phase-9.md`. Clipboard
  (activation + frontmost, prefs-gated), drag onto window/Dock, Services
  (“Download with …”), custom URL scheme — all land in the Home field via
  `IncomingLinkController`. Idle → silent fill+probe; busy → skinned confirm.
  Loose URL extract (`LinkExtractor`); probe stays the extractor truth. **Share
  Extension is not this phase** — sibling stub
  `docs/superpowers/specs/2026-09-10-media-grabber-share-extension-STUB.md`
  (insert as Phase 10 and renumber Diagnostics/Polish when scheduled).

- **Phase 10 — Share Extension (STUB — needs planning).** Reserved only. See
  `docs/superpowers/specs/2026-09-10-media-grabber-share-extension-STUB.md`.
  When opened: full spec + plan + e2e Share appex. Renumber: this becomes 10;
  Diagnostics 11; Polish 12.

- **Phase 11 — Diagnostics, staleness, updater.** *(was Phase 10; number
  shifts when Share Extension is scheduled — until then still “Phase 10” in
  older prose.)* The Diagnostics page (Run check → report card → Copy report /
  Copy diagnostic bundle); the `DiagnosticBundle` zip; the yt-dlp staleness
  daily check; `YtDlpUpdater`; the Updates pane rows (Phase 3). The
  engine-freshness `HealthStrip` chip is emitted here from `HealthController`
  (no Phase 6 slot) — amber when yt-dlp is stale, `↻` runs the upgrade;
  staleness is a chip, never a banner. The report card reflects Phase 4 / 6 /
  7 state, so it comes after them. *Hint: `DebugFlags` (`-MG*` launch args,
  struct from Phase 2) has grown across phases — add a Debug menu bound to it
  here if warranted.* *Hint: update the `screens.html` mockup — the Diagnostics
  screen (before-run and after-run states) and the Updates pane fill here;
  both are stepless / header-only in the current snapshot.*

- **Phase 12 — Polish.** *(was Phase 11; same provisional renumber note.)*
  Success and chip-refresh-failure toasts; native macOS notifications for
  backgrounded failures; the first-run cards → table transition and the
  emptied-table state; a full keyboard-navigation, VoiceOver, and
  `prefers-reduced-motion` pass over every screen; the GitHub-release
  self-update check (§10.2). Last because the a11y pass audits every screen
  the earlier phases built.

### 12.2 Shells built complete, filled later

A few components are laid out in an early phase because a later phase needs
somewhere to put its output. The early phase builds the shell **complete** — the
full layout, the empty container. Later phases add cases, chips, rows, or wiring
**without touching layout**. This keeps each phase's UI work self-contained and
means no screen is built twice.

| Shell | Built complete in | Filled by |
|---|---|---|
| Scheduler loop | Phase 2 — event-driven `evaluateSchedule()` after every mutation; two pure decisions, `nextDownloads(SchedulerInput)` (cap-gated) and `nextProbe(SchedulerInput)` (serial-probe-gated, independent of the download cap); a deferred-start seam (sorted `(jobID, notBefore)` list + one dormant sleep-`Task`, `deferStart(_:until:)`, no caller) | Phase 4 — first `deferStart` caller (backoff); Phase 6 — `blockedHostIDs` / `blockedProbeHostIDs` plus `cap` swapped to `min(adaptiveCap, prefsCap)` on `SchedulerInput`, second `deferStart` caller (host cooldown); neither rewrites the loop |
| Engine → UI channel | Phase 2 — `AsyncStream<QueueEvent>` (`.snapshot(QueueSnapshot)` on structural change, `.progress` delta on progress ticks); `DownloadJob` demoted to engine-internal model, `JobSnapshot` the only boundary type | not filled later — the shape is final |
| `JobSnapshot` | Phase 2 — the full field set. Populated now: `progress`, `durationSeconds?`, `extractor?`, `sizeBytes?`, `availableActions`, `outputFiles`, dates, `attempt`, `actualQuality?`, `cooldownUntil?`, `rateHost`, `playerClientUsed?`, `playlistGroupID?`, `playlistIndex?`, `integrityVerdict?`. Non-playlist fixtures pass `playlistGroupID` / `playlistIndex` as `nil` | Phase 4 populates `attempt` + `integrityVerdict` + `actualQuality`, Phase 6 `cooldownUntil` + `rateHost`, Phase 7 `playerClientUsed`, Phase 8 `playlistGroupID` + `playlistIndex` |
| `QueueSnapshot.queueHalt` + `engine.revalidate()` | Phase 2 — `QueueHaltReason?`, `.depMissing` case (scheduler stops, `AppModel` shows Onboarding takeover); `revalidate()` re-checks deps and clears `.depMissing` only, called on onboarding completion. `QueueSnapshot` also carries `hostRateSummary` + `isOnline` | Phase 6 — adds derived `.circuitOpen` and hard `.networkDown`; circuit reset is `resetCircuit` / `resetAllCircuits`, not `revalidate()`. Banner "Retry now" and the cooldown-chip popover call those |
| Downloads-table row-action bar | Phase 2 — every `RowAction` button laid out in fixed order; `availableActions: Set<RowAction>` per job from the engine; buttons not in the set render disabled | Phase 4 (`retry`, `showLog` — the `.failed` arm reads `ErrorClass.presentation.offeredActions`; `showLog` on every run state), Phase 5 (`retryWithCookies` `🔑`) — the engine adds them to the set, no UI change |
| `WarningBanner` | Phase 2 — the docked shell + `BannerContent { text, buttonTitle?, action? }`, always nil | Phase 6 wires a `BannerReason` priority resolver (`depMissing` > `networkDown` > `circuitOpen`; optional button — `networkDown` has none); Phase 7 adds `potProviderDown` as one resolver entry (Restart → `restartShield`; not a `QueueHaltReason`) |
| `HealthStrip` | Phase 2 — the chip row + `HealthChip { label, dot, interaction, countdownUntil? }`; `ChipInteraction` = `none \| refresh \| popover(PopoverKind)` (data, the strip renders interaction) | Phase 6 ships `HealthController` + online + cooldown chips + `.popover(.hostRate)`; Phase 7 adds the bot-check shield chip + live `.refresh` (`↻`); Phase 10 adds the engine-freshness chip; Phase 11 the chip-refresh toast |
| `ConfirmationRequest` + dialog host | Phase 2 — `ConfirmationRequest { title, message, confirmTitle, cancelTitle?, isDestructive, suppressionKey? }` (`cancelTitle == nil` → single-button notice), `AppModel.confirm(_:) async -> Bool`, one skinned dialog host (design-system §4.8); P2 users: duplicate-submit, graceful quit, reveal-missing (notice), write-failure (notice) — all `suppressionKey: nil` | Phase 8 "cancel all" (`suppressionKey: "playlist-cancel-all"`) and any later dialog — just call `confirm(...)` |
| `ErrorClass` emit paths + failure UI | Phase 2 wires `incomplete` / `diskFull` / `permissionDenied` · Phase 4 the generic-set classifier signatures + the `FailurePresentation` model (`{ sentence, offeredActions }` keyed off `ErrorClass`, one switch) + `ErrorClass.key` | Phase 5 (`cookieReadFailed`) · Phase 7 (`botCheck`, `sabrGated`, `formatsMissing` on jobs; `potProviderDown` presentation sentence exists, chrome-only, never a row terminal state) |
| `PreferencesView` panes | Phase 3 — all 7 panes; Downloads / Appearance / Network / Logs & privacy / Advanced filled, Sign-in & cookies + Updates stepless | Phase 4 (retry engine consuming `maxAutoRetries`), Phase 5 (the whole Sign-in & cookies pane — browser picker, Firefox-profile picker, Full Disk Access row, Learn more, tip), Phase 7 (Downloads **Audio language** policy row), Phase 10 (`autoCheckUpdates`) |
| Onboarding step list | Phase 1 — `OnboardingView` renders `ForEach(OnboardingStepID.allCases)`; ships `homebrew`, `downloaderTools`, `botCheckShield` (POT `pipx` install), `testRun` | — (stays 4 steps; cookies use a just-in-time Full Disk Access request from the Preferences pane) |

**No accepted throwaway.** The Phase 2 scheduler is extended in Phase 6, not
deleted. The runway defaults read the `Preferences` model from Phase 1, so
Phase 3 adds an editor — it does not swap a data source. Nothing a Phase 2+
phase builds is removed or replaced by a later one.

**Two Phase 2 deletions, both deliberate.** Phase 1's single-drain loop
(`drain` / `nextQueued` / `ensureDraining` / `drainTask` / `runningLineTask` /
the separate `queuedJobs`) is replaced by the multi-slot scheduler. Phase 1's
`DownloadJob` (`@MainActor @Observable`, bound directly by the UI) is demoted to
an engine-internal model; `JobSnapshot` values on the stream replace direct
binding. Both are part of the Phase 2 engine rework — the mutation invariant
that requires them postdates Phase 1.

**Accepted large rework** — the a11y sweep in Phase 11 reopens every screen from
Phases 1–10 for keyboard / VoiceOver / reduce-motion. This is a chosen tradeoff:
one consolidated pass rather than a per-phase DoD line item. The risk is that if
Phase 11 is cut or deferred, a11y ships incomplete.

## 13. Out of scope for v1

Subtitles / embed-thumbnail / embed-metadata options; per-site helpers beyond
YouTube (Instagram / Twitter / TikTok auto-cookies, and so on); a menu-bar item;
scheduled or recurring downloads; the browser extension (tracked separately as
BACKLOG T-006); a PO-token auto-provider; a lifetime-stats panel; per-download
bandwidth graphs; DRM-protected sites (not possible); a hosted or cloud POT
provider (the local one is v1); fetching the `player_client` order from a remote
JSON (v1.1); per-skin light/dark; a compact-window breakpoint.

## 14. Deferred decisions

**Product name.** The app ships under a name chosen at v1 release; until then
the code and directory use the working name `MediaGrabber` / `apps/media-grabber/`.
Renaming is a mechanical find-and-replace. ~20 candidates have been checked for
collisions; the video-downloader space is saturated (Downie, Grabbr, Parabolic,
Stacher, ClipGrab, …) and every short string is claimed somewhere. The
verified-clean options (no Mac app, no downloader, no dev tool, no famous
brand): **Weir** (`weir.app` is free), **Undertow**, **Vireo**, **Freshet**.
Bundle ID: `app.<name>.mac` (reverse-DNS, `mac` suffix leaves room for other platforms later).

**Icon direction.** Decided with the name.

**BACKLOG.md.** Left as-is for now — no new row, T-002 (the CLI) unchanged,
T-006's dependency unchanged. Revisit when this app reaches v1.
