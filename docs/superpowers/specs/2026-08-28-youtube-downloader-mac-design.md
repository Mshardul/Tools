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
  - `HomeView.swift` — paste field, probe status, runway (Link · Type · Format · Save to), Grab; hosts the Downloads table
  - `RunwaySlot.swift` — one labelled slot (a dropdown or a resolved value) with a filled / hollow state
  - `PlaylistPickerView.swift` — the modal checklist (thumbnail, title, duration; select all / none; filter; live count + size; Add N)
  - `DownloadsTable.swift` — column-model rendering: show/hide, drag-reorder, per-column sort + filter menus, the playlist group header + spine
  - `DownloadRow.swift` — one video row: status pill, progress, contextual action buttons. No expansion.
  - `ColumnsMenu.swift` — the `⊞ Columns` checkbox menu
- `HealthStrip.swift` — the ambient-state chips (shield, engine freshness, online, per-host cooldown). A chip in a bad state grows a `↻` refresh icon that runs its background fix (restart the POT provider / upgrade yt-dlp / re-poll the network); on success the chip goes green, on failure an error toast explains why and the chip stays bad. The cooldown chip has no `↻` — clicking it opens a why / when-it-clears / Retry-now popover.
- `WarningBanner.swift` — the engine/host-level banner (cooldown, circuit open, dependency missing, POT provider down)
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

- `DownloadRequest.swift` — immutable: url, destFolder, kind, container, playlist, template
- `DownloadJob.swift` — `@Observable` per-row state machine
- `DownloadEngine.swift` — actor: the rate-limit-aware scheduler; spawns one `yt-dlp` per job
- `YtDlpArguments.swift` — `DownloadRequest` + attempt context → argv (with a redaction view)
- `ProgressParser.swift` — progress-template lines → `ProgressEvent`; stderr → `ErrorClass`
- `MetadataProbe.swift` — serialized `yt-dlp -J --flat-playlist` → title / playlist info
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
- `Persistence.swift` — Codable load / save: `queue.json`, `history.json`, `columns.json` (debounced)

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
- `playlist: PlaylistSelection` — `.notPlaylist | .all | .items(String)` (yt-dlp range syntax `"1-5,8"`)
- `outputTemplate: String` — default `%(title)s.%(ext)s`, from Preferences

### DownloadJob (`@Observable`; one per table row)

- `id: UUID`
- `request: DownloadRequest`
- `title: String?` — filled by the metadata probe
- `playlistGroupID: UUID?` and `playlistProgress: (index: Int, total: Int)?`
- `state: JobState` — `.queued | .probing | .running | .paused | .waitingForNetwork | .cooldown(until:) | .completed | .failed(ErrorClass) | .cancelled`
- `progress: Progress?` — `fraction`, `speedBytesPerSec?`, `etaSeconds?`, `downloadedBytes`, `totalBytes`
- `attempt: Int` — `maxAutoAttempts` comes from `Preferences` (1…5, default 5)
- `playerClientUsed: String?` — which YouTube client the last attempt impersonated
- `outputFiles: [URL]` — resolved on completion (for Reveal in Finder)
- `logPath: URL` — the per-job raw log
- `addedAt: Date`, `finishedAt: Date?`

### Preferences (`@Observable`, UserDefaults-backed)

- `defaultDestFolder: URL` (default `~/Downloads`)
- `lastUsedDestFolder: URL` — seeds the runway's "Save to" slot
- `skin: Skin` (default `.aurora`), `palette: Palette` (default Aurora / Mint & Iris)
- `maxConcurrentDownloads: Int` (default 2, range 1…5)
- `defaultKind`, `defaultMaxHeight` (default 1080), `defaultAudioCodec` (default m4a)
- `outputTemplate: String`
- `clipboardAutoDetect: Bool` (default true)
- `cookiesFromBrowser: BrowserChoice` — `.none | .safari | .chrome | .brave | .firefox | .edge` (default `.safari`)
- `firefoxProfile: String?` — used only when `cookiesFromBrowser == .firefox`
- `proxyURL: String?`
- `forceIPv4: Bool` (default false)
- `selfRateLimitKBps: Int?` — optional `--limit-rate`
- `maxAutoAttempts: Int` (1…5, default 5) — the per-job auto-retry budget
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
- **Health strip** — below the brand row: small chips carrying ambient state — `bot-check shield`, `engine` (yt-dlp freshness), `online`, and a `<host> · cooldown m:ss` chip shown only during a cooldown. A green dot means ok, amber means attention. A chip in a bad state grows a `↻` refresh icon at its right edge; clicking it runs that chip's background fix:
  - `shield · offline` → restart the POT provider process, re-run its health check
  - `engine · stale` → `brew upgrade yt-dlp` (or `yt-dlp -U`), re-read the version
  - `offline` → re-poll `NWPathMonitor`
  - `engine · missing` (a dependency is gone) → *not a refresh* — routes back to Onboarding as a hard block

  On success the chip goes green and the icon disappears. On failure an error
  toast shows the reason and the chip stays bad. The `cooldown` chip has no `↻`;
  clicking it opens a popover — why the cooldown happened, when it clears, and a
  Retry-now button.
- **Warning banner** — docked to the bottom of the window, floating over the table, with the table reserving bottom padding so its last row never hides under it. Reserved for **engine / host-level** conditions only: the cooldown explainer, circuit-breaker open, a missing dependency, POT provider down. One sentence, one action button.

### 5.3 Home

- **Hero:** a kicker, a headline, and the paste field. No dashboard or stats widget.
- **First run, no download ever made:** the paste field plus three step cards ("Paste a link · Pick a format · Press Grab") fill the body. There is **no Downloads table** (no headers, filter chips, or Columns button) and **no runway** (there is no link yet).
- **After the first Grab:** the step cards are gone permanently, and the Downloads table renders from then on. The field sits above it; the runway appears when a pasted link resolves and is hidden otherwise.
- **Table emptied later** (every row removed): the table stays, showing a single centred line — "No downloads — paste a link above." The step cards do not return; they are first-run-only.
- **Runway** (the resolve-and-arm pattern) — **hidden until a pasted link resolves.** On resolve, the field shows an inline `✓ <title>` and the runway appears attached below it: a strip of labelled slots — **Link · Type · Format · Save to** — each a filled dot when set, a hollow dot when not. Type / Format / Save-to seed from the Preferences defaults. **Grab** sits at the end of the runway and is **disabled until every slot is filled** (the link resolved *and* downloadable, plus type, format, and destination). The "Save to" slot is the per-download destination override. The runway is the entire add flow — there is no separate Add sheet.
- **Playlist:** when the probe resolves to a playlist, a modal picker opens *before* any rows are added — a checklist (thumbnail, title, duration), Select all / none, a filter-in-playlist field, a live `M of N · ≈ size`, and "Add M". Only checked videos become rows. There is no range-syntax field in the UI; the engine still uses ranges internally.

### 5.4 Downloads table

- One table, newest on top, **one row per video**.
- Above it: filter chips (`All · Downloading · Done · Needs attention`, the last with a count badge) and a `⊞ Columns` button (a checkbox menu to show / hide columns).
- **Default columns:** Title · Site · Format · Status · Progress · Speed/ETA · **Actions**.
- **Available to add:** Added · Finished · Size · Destination · Attempt · Playlist · Duration · Client used.
- Columns are **draggable to reorder**. Actions is pinned last and cannot hide or move; Title cannot hide but can move. Column order and visibility persist.
- Per-column **sort** (`↕` cycles asc → desc → off) and **filter** (`▽` opens a menu) where meaningful; Progress and Speed/ETA are sort-only; Actions is neither.
- The Status cell shows the plain-language state; a failure shows its reason sentence. The Actions column carries the contextual buttons: pause / resume, cancel, **force-start `⏫`**, retry, retry-with-cookies `🔑`, reveal in Finder, open in browser, remove, and show log (opens the raw log file in the default text editor).
- **There is no per-row expansion and no detail view.** Failure detail is the status reason plus the row actions plus the external log.

### 5.5 Playlist group in the table

A group header row sits above the playlist's videos: a collapse caret, the
playlist name, a rollup (`N items · M done` plus a mini progress bar), and group
actions (Pause all · Retry failed · Cancel all). The children are indented
against one continuous vertical spine; the row dividers between children start
*after* the spine and never cross it. Collapsing the group hides the children;
the header remains, showing the rollup only. This is a grouping row, not a
detail view — nothing expands per video.

### 5.6 Force-start

`⏫` on a queued row starts it immediately and stops the **last-started**
running job (round-robin, staying within the per-host pacing budget), re-queuing
the stopped one.

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

1. **Add** — a URL reaches the Home field (paste / drag / Services / clipboard-detect). The runway's Type / Format / Save-to slots seed from Preferences; the Link slot is still hollow.
2. `MetadataProbe` (a serialized actor plus the token bucket) runs `yt-dlp -J --flat-playlist --no-warnings <url>` → title, duration, is-playlist, item count. On success the field shows `✓ <title>` and the Link slot fills; Grab arms once every slot is filled. If it is a playlist, `PlaylistPickerView` opens — the user checks items, then confirms with "Add N".
3. The user presses Grab (a single item) or confirms the picker → one `DownloadRequest` per item is built → a `DownloadJob(state: .queued)` per item is appended to `AppModel.queue` (playlist items share a group id) → persisted.
4. `DownloadEngine`'s scheduler loop: if the host `RateState == .normal`, `running < AdaptiveConcurrency.current`, and the network is up → dequeue the next `.queued` job.
5. `YtDlpArguments` builds the argv: resilience flags (§7) + `--plugin-dirs` (the POT plugin) + the POT provider base URL + cookies + the `player_client` for this attempt. `ProcessRunner` launches; stdout is streamed line-by-line off the main actor.
6. `ProgressParser` parses progress-template lines → `ProgressEvent` → `job.progress` (hopping to the main actor). Raw lines are appended to `JobLog`. Error signatures → `ErrorClass` + `LogEvent`.
7. **Terminal:**
   - exit 0 **and** `IntegrityCheck` passes → `.completed`, resolve `outputFiles`, move to history.
   - non-zero → classify:
     - auto-retryable and `attempt < maxAutoAttempts` → `.queued` again after a `Backoff` delay, with the next `player_client` in the rotation.
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
app supervises its server on `127.0.0.1:<free port>` and points yt-dlp at its
POT plugin; yt-dlp then auto-negotiates per-video tokens. This is the single
biggest reliability lever in 2026 — it neutralises most bot-check, SABR, and
"formats missing" failures. If the provider process is down, downloads still
proceed (degraded) and a banner shows it. `GrabberKit/PotProvider/` holds the
supervision and plugin-install code, structured so "bundled" vs "external" is a
single swappable resolver if a Developer ID account is ever obtained.

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

**Cookies from browser** — `--cookies-from-browser <choice>`, default `.safari`.
On an unreadable cookie database, fall back to no cookies, log it, and classify
as `cookieReadFailed` only if the download then fails.

**User-Agent** — aligned to the chosen client; a small rotating pool.

### 7.3 Cookie edge cases

- **Safari** — needs the app to have **Full Disk Access** (it reads the Safari container's `Cookies.binarycookies`). Detect the permission failure and prompt with a System Settings deep link to the Full Disk Access pane.
- **Chrome / Brave / Edge** — cookies are Keychain-encrypted; the first use triggers a Keychain prompt. Chrome 127+ **app-bound encryption** can defeat `--cookies-from-browser` → detect, fall back, and tell the user to use a different browser profile or Safari / Firefox.
- **Firefox** — reads `cookies.sqlite`; multiple profiles need `firefox:PROFILE`. Enumerate the profiles and let the user pick in Preferences.
- **Locked database** — an open browser can lock it; yt-dlp usually copies first but can fail → `cookieReadFailed`, fall back, don't hard-fail.
- **Recommended setup** (surfaced as a Preferences tip): a dedicated browser profile signed into YouTube, kept closed while downloading.

### 7.4 Scheduler and pacing

- **AdaptiveConcurrency** — starts at 2. After a clean streak (5 downloads, no throttle) → +1 up to the Preferences cap. On any 429 / throttle → drop to 1 and enter a cooldown.
- **MetadataTokenBucket** — ≤ N probe requests per rolling 60 s (N small, e.g. 3). Playlist expansion is one `--flat-playlist` call, never N calls. Large playlists drip.
- **Backoff** — exponential with **full jitter** (`random(0, base)`), sequence 30 → 60 → 120 → 300 → 600 s, then holding at 600. Honours an explicit `Retry-After` when yt-dlp surfaces it.
- **Per-host RateState** — `[Host: RateState]`; `youtube.com` and `youtu.be` share one bucket.
- **Circuit breaker** — after K (e.g. 4) consecutive 429s across cooldowns → `queue.suspended`, no auto-retry, a banner instructing the user (wait / add cookies / check the IP / disable the VPN). The user can force a retry.

### 7.5 Download-level flags (always)

`--retries infinite --fragment-retries infinite --retry-sleep exp=1:120 --throttled-rate 100K --file-access-retries 5 --no-part-hint`,
plus `--sleep-requests 1` and a small random `--sleep-interval` before each
download.

### 7.6 Download-level flags (adaptive)

- `--concurrent-fragments` — 1 by default; raised to 3–4 only when the host `RateState == .normal` and there is no recent throttle.
- `--limit-rate` — from `Preferences.selfRateLimitKBps` when set (self-throttling reduces re-extraction churn).
- `--force-ipv4` — from `Preferences.forceIPv4`, or auto-tried as a retry variant after repeated connection failures.
- `--proxy` — from `Preferences.proxyURL` when set.

### 7.7 Resume and integrity

- On resume: verify the `.part` and `.ytdl` sidecar exist and are consistent; if the format URL rotated and yt-dlp cannot resume, restart that file clean rather than loop.
- **IntegrityCheck** — after exit 0, run `ffprobe` on the outputs; if the duration is materially short of the metadata duration, or a file is unplayable → `.failed(incomplete)` with a re-download action.

### 7.8 Network and environment

- **NetworkMonitor** (`NWPathMonitor`) — no network → jobs go `.waitingForNetwork` and auto-resume on reconnect; retries are not burned against a dead link.
- **VPN hint** — a bot-check error plus an active VPN / utun interface → tell the user plainly: disable the VPN or add cookies.
- **yt-dlp staleness** — on launch and once daily, compare the resolved yt-dlp's `--version` to the latest GitHub release date; if more than ~14 days stale, a non-blocking banner with a one-click **Update yt-dlp**. YouTube breakage is usually just a stale binary, so this is high-value.
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
- Engine-level: the circuit breaker → `queue.suspended` banner, no auto-retry.
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

## 12. Implementation phasing

The app is built **version over version**, not module by module. Each phase is a
working app that does more than the previous one — it can be launched, used,
tested, and stopped at any phase boundary. Within a phase, work proceeds module
by module, but a phase only closes when those modules connect into a working
build.

**A phase is done when:** its DoD is met · `tuist test` is green · its manual
smoke checklist passes on a real machine · a commit is tagged `phase-N`.

**Planning cadence.** This spec defines Phase 1 in full and Phases 2–11 as
intent paragraphs. After the spec is reviewed, the `writing-plans` skill
produces a plan file for **Phase 1 only**. Phase 1 is built. Then Phase 2 is
detailed here, planned, and built. And so on — later phases are refined by what
the earlier ones teach.

Everything non-UI lives in `GrabberKit` and is headless-testable. TDD
throughout: the test comes before the implementation for every unit.
Real-network tests are gated behind `MG_LIVE_TESTS=1` and are off in CI;
manual smoke checklists cover the rest.

### 12.1 Phase 1 — "one file, start to finish"

**Definition of done:** launch the app → if `yt-dlp` or `ffmpeg` is missing, a
blocking onboarding screen installs them → paste one URL → the title resolves
and the runway arms on defaults → press Grab → a real progress bar runs to a
saved file → the row shows "saved" with Reveal. Aurora / Mint & Iris only, no
picker. No queue, persistence, resilience, playlist, cookies, POT provider,
Preferences UI, Diagnostics, toasts, or banner.

Build order (each step is a TDD unit; its DoD is noted):

1. **Project skeleton.** `Project.swift` (Tuist) with targets `App`, `GrabberKit`, `GrabberKitTests`; `.mise.toml` pins Tuist; a scoped `.gitignore`; SwiftFormat / SwiftLint config; GitHub Actions (`mise install → tuist generate → tuist build → tuist test`). The app launches to a blank window; one dummy test passes. **DoD:** CI green, window opens.

2. **`ProcessRunner`** (GrabberKit/Onboarding). An async wrapper over `Foundation.Process`: launch with argv + env, stream stdout / stderr as a line-split `AsyncStream<String>`, await the exit code, cancellation → SIGTERM. Pure, no app dependency. **Tests:** `echo`, `true`, `false`, a 3-line delayed emitter, a hang-then-cancel script. **DoD:** all process-control paths fixture-covered.

3. **`EnvironmentProbe`** (GrabberKit/Onboarding). Search the brew locations plus `$PATH` for `brew`, `yt-dlp`, `ffmpeg`; read and parse `--version` from each; return an `EnvironmentReport`. **Tests:** fixture version strings → parsed structs; a missing binary → `nil`; malformed → graceful. **DoD:** a correct report against fixtures, with no real brew or network.

4. **Data types** (GrabberKit/Download + Model). `DownloadRequest` (immutable: url, destFolder, kind, container?, outputTemplate); `DownloadJob` (`@Observable`: id, request, title?, state, progress?); `ErrorClass` (the full enum per §9, but Phase 1 only emits `.unknown`, `.networkDown`, `.depMissing`); the `Progress` struct; a minimal `Preferences` (dest, kind, height, codec, template, skin, palette; UserDefaults-backed). **Tests:** Codable round-trips; `Preferences` defaults. **DoD:** the types compile, encode / decode, and the defaults are correct.

5. **`YtDlpArguments`** (GrabberKit/Download). A pure `(DownloadRequest) -> [String]` — the Phase 1 subset: `-o`, `-P`, a format selector for kind / height / codec, `--newline --progress --progress-template …`, `--no-playlist`. Plus a redacted view (identical for now; the seam matters later). **Tests:** each request shape → an exact argv snapshot; the redacted view. **DoD:** snapshot tests pass for video, audio, height, codec, and a custom template.

6. **`ProgressParser`** (GrabberKit/Download). Parse `--progress-template` stdout lines → `ProgressEvent` or `.ignored`; parse stderr signatures → `ErrorClass` (Phase 1: a generic `ERROR:` → `.unknown`, a network error → `.networkDown`). **Tests:** checked-in fixture files of real yt-dlp output → the expected event sequence; malformed lines never crash. **DoD:** fixture-driven, covering start / mid / 100% / post-processing / error lines.

7. **Skin / palette system** (App/Theme). The `Skin` enum (`.aurora`, `.tapeDeck`) carrying font / radius / border / elevation / motif; the `Palette` enum (3 per skin) → a colour token struct; `SkinEnvironment` injecting the resolved values into the SwiftUI `Environment`; `MotifView` (the reel / orb, an `isActive` flag, honouring `accessibilityReduceMotion`). Phase 1 hardcodes Aurora / Mint & Iris but the plumbing is real. Built before any UI so the first screens read from the environment, not literals. **Tests:** `Skin.aurora.palettes.count == 3`; the token structs are non-nil for every skin × palette; `MotifView` is static under reduce-motion. **DoD:** the UI reads colours and fonts from the environment.

8. **`OnboardingInstaller` + `OnboardingView`** (GrabberKit + App). `OnboardingInstaller` (GrabberKit): a state machine over the steps — Homebrew present? → `brew install yt-dlp ffmpeg` via `ProcessRunner` (streamed) → re-probe → done; each step `.pending | .running(text) | .done | .failed(reason)`. The Homebrew-missing branch exposes the official install command string plus an "open in Terminal" intent; it never auto-runs the curl script. `OnboardingView` (App): the checklist UI (design-system §4.5), bound to the installer state, blocking Home while yt-dlp / ffmpeg are absent. **Tests (installer):** a fake `ProcessRunner` drives each step; a failure surfaces its reason; re-probe gates completion. **DoD:** with the dependencies absent, onboarding shows and installs; with them present, it is skipped.

9. **`MetadataProbe`** (GrabberKit/Download). `yt-dlp -J --no-warnings --no-playlist <url>` via `ProcessRunner` → parse JSON → `{ title, durationSeconds?, isPlaylist: false }`. Serialized (one at a time), no token bucket yet. A failure → a typed error (bad URL / unsupported / network). **Tests:** fixture `-J` blobs → parsed metadata; an error or non-zero exit → typed errors. **DoD:** a real URL → the title; a bad URL → a clean error.

10. **`DownloadEngine`** (GrabberKit/Download) — single job. An actor. `submit(DownloadRequest) -> DownloadJob`: probe (fill the title) → spawn one `yt-dlp` (`YtDlpArguments` via `ProcessRunner`) → feed lines to `ProgressParser` → update `job` on the main actor → exit 0 resolves `outputFiles` and `.completed`; non-zero → `.failed(class)`. No scheduler, queue, rate-state, or retry — a second `submit` while busy waits FIFO in-actor. Cancellation → SIGTERM + `.cancelled`. **Tests:** a fake `ProcessRunner` scripts a progress + exit sequence → assert the job timeline; non-zero → `.failed`; cancel → `.cancelled` plus the child killed. **DoD:** a headless test drives a full fake download; a real run lands an actual video.

11. **`HomeView` + `MainWindow` + `AppModel` + `LogWriter`** (App + GrabberKit/Logging). `MainWindow`: the brand row + a health strip (static "online" only) + nav (Home active; Preferences / Diagnostics present but empty) + the page switch; no banner. `AppModel` (`@Observable`): `deps`, `job: DownloadJob?` (single), `page`. `HomeView`: the first-run state (field + 3 step cards, no table, no runway) → paste → `MetadataProbe` → on resolve the field shows `✓ title`, the runway appears (all slots filled from defaults), Grab arms → Grab submits to `DownloadEngine`, the step cards vanish, a one-row list shows the job with a live bar + status → completion shows "saved" + Reveal. `LogWriter` (an actor): JSON Lines to `~/Library/Logs/MediaGrabber/app.log` + the `os.Logger` mirror; Phase 1 events — launch, probe done, job state changes, process launch / exit; redaction per §8.5. **Tests:** `AppModel` logic with a fake engine; `LogWriter` schema + redaction. **DoD:** *the phase is done* — launch → (onboarding if needed) → paste a real URL → Grab on defaults → watch the bar → the file is in `~/Downloads` → "saved" → Reveal opens Finder.

12. **Leaf docs + smoke.** `apps/media-grabber/README.md` (build steps plus the one-time Gatekeeper "Open Anyway"), `PRIVACY.md`, `ticket-backlog.md`. The Phase 1 manual smoke checklist: fresh-machine onboarding · happy-path video · happy-path audio · bad URL · cancel mid-download · quit mid-download (it is killed; no resume yet — a documented gap). **DoD:** the checklist passes on a real machine.

### 12.2 Phases 2–11 (intent — detailed when reached)

- **Phase 2 — Queue + scheduler.** Many jobs; `AdaptiveConcurrency` (a fixed cap first, the adaptive logic in Phase 4); the real Downloads table (columns, show / hide, drag-reorder, per-column sort + filter, filter chips); row actions; force-start (`⏫` stops the last-started running job, round-robin). The `ColumnConfig` model, not yet persisted.

- **Phase 3 — Persistence.** `Persistence` for `queue.json` + `columns.json` (debounced); on launch reload the queue and reset `.running` → `.queued` (the yt-dlp `.part` enables resume); graceful quit (confirm dialog → SIGTERM → persist → resume next launch).

- **Phase 4 — Resilience core.** `RateState` per host (`normal | cooldown | circuitOpen`); `Backoff` (exponential + full jitter, cap, `Retry-After`); the full `ErrorClass` classification driving the failure UI; the per-job auto-retry budget (`Preferences.maxAutoAttempts`); the cooldown row state + the docked warning banner; the circuit breaker → `queue.suspended`; `MetadataTokenBucket`; adaptive concurrency (streak up / throttle down); `NetworkMonitor` → `waitingForNetwork`. The always-on download flags (§7.5).

- **Phase 5 — YouTube hardening.** `player_client` rotation (`tv → ios → tv_embedded → mweb → web_safari`, `PlayerClientRotation.default`); `PotProviderProcess` (supervise the pipx `bgutil-pot` server on a free `127.0.0.1` port, health check, restart on crash, stop on quit) + `PotPluginInstaller`; the `--extractor-args` + `--plugin-dirs` wiring; the `bot-check shield` health chip + its `↻` refresh; the `sabrGated` / `formatsMissing` classes and their honest failure copy.

- **Phase 6 — Cookies.** `--cookies-from-browser`; Full Disk Access detection + the System Settings deep link (Safari); Firefox multi-profile enumeration + the picker; the Chrome app-bound-encryption fallback; `cookieReadFailed` (non-fatal); the "retry with cookies" (`🔑`) row action.

- **Phase 7 — Playlist.** `MetadataProbe` playlist mode (`--flat-playlist`, one call); the `PlaylistPickerView` modal (checklist, select all / none, filter, live count + size); the group-header + spine rendering in the table; the group actions (pause all / retry failed / cancel all); large-playlist drip.

- **Phase 8 — Add flows.** Clipboard auto-detect on app activation; Services / Share ("Download with …"); drag a URL onto the window or the Dock icon; the custom URL scheme (`Info.plist` `CFBundleURLTypes`). Every one routes into the same Home field.

- **Phase 9 — Preferences UI.** All 7 panes (design-system §4.6); the Skin + Palette pickers wired to `Preferences`; every remaining setting connected; `firefoxProfile`, `autoCheckUpdates`, and `maxAutoAttempts` surfaced.

- **Phase 10 — Diagnostics + integrity.** `IntegrityCheck` (ffprobe duration vs metadata → `incomplete`); the Diagnostics page (Run check → report card → Copy report / Copy diagnostic bundle); the `DiagnosticBundle` zip; the yt-dlp staleness banner + the daily check; `YtDlpUpdater`.

- **Phase 11 — Polish.** Success + chip-refresh-failure toasts; native macOS notifications for backgrounded failures; the first-run cards → table transition and the emptied-table state; a full keyboard-navigation and VoiceOver pass; a `prefers-reduced-motion` audit; the GitHub-release self-update check (§10.2).

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
