# MediaGrabber — leaf backlog

Work not in Phase 1. The repo-root `BACKLOG.md` is **not** touched by this app
until it reaches v1 (spec §14).

## Phase 1 follow-ups (surfaced during the build)

- **Bundle the Aurora typefaces.** Ship Sora / Inter / JetBrains Mono under
  `Sources/App/Resources/Fonts/**` and add `ATSApplicationFontsPath` to the
  Info.plist. `Skin`'s font accessors already resolve-or-fall-back; today they
  always fall back to the system face because the files aren't present.
- **Real onboarding canary.** `OnboardingInstaller`'s `testRun` step is
  auto-pass (`.done` when deps resolved). Give it a real `MetadataProbe` of a
  known-stable Creative-Commons URL and surface a genuine pass/fail.
- **Product-name decision (spec §14).** `MediaGrabber` / `app.mediagrabber.mac`
  are placeholders; pick the real name and do the find-and-replace.

## Phases 2–11 (intent — detailed when reached, from spec §12.1)

Boundaries are dependency cuts: a phase is picked when its inputs exist, and its
scope is drawn so nothing inside waits on a later phase. Shell-and-fill splits
are in spec §12.2.

- **Phase 2 — Queue foundation and window chrome.** Engine owns the queue:
  ordered job list + scheduler loop in `DownloadEngine`, `Sendable` `JobSnapshot`
  on an `AsyncStream`, `AppModel` consumes it into `@Observable` row VMs, intents
  (pause/cancel/force-start/reorder/remove) are `async` calls in. Scheduler
  starts a job when `running < Preferences.maxConcurrentDownloads`, written to
  take more conditions later. Downloads table (columns, show/hide, drag-reorder,
  per-column sort + filter, filter chips); `ColumnConfig`; full row-action bar
  (all buttons; no-engine actions capability-gated); force-start (`⏫`,
  round-robin). `Persistence` for `queue.json` + `columns.json` (debounced);
  launch reload + `.running` → `.queued`; graceful quit (confirm → SIGTERM →
  persist → resume). `MainWindow`: empty `WarningBanner` and `HealthStrip`
  shells. `ErrorClass` gains `incomplete`, `diskFull`, `permissionDenied`.
  `JobSnapshot` defined full-shape (incl. `attempt`, `cooldownUntil?`,
  `playerClientUsed?`, defaulted).
- **Phase 3 — Preferences screen.** 7-pane `PreferencesView` over the existing
  `Preferences` model. Downloads / Appearance / Logs & privacy panes filled;
  Network / Sign-in & cookies / Updates / Advanced are headers later phases add
  rows to.
- **Phase 4 — Retry and error classification.** Generic `ErrorClass` cases
  (`rateLimited`, `geoBlocked`, `private`, `unavailable`, `ageRestricted`,
  `cookieReadFailed`, `networkDown`, `depMissing`, `unknown`) + failure-reason
  sentences + row actions; retry / force-start buttons wired live; per-job
  auto-retry budget (`Preferences.maxAutoAttempts`, control → Phase 3 Downloads
  pane); `Backoff` (exp + full jitter, cap, `Retry-After`); `IntegrityCheck`
  (ffprobe duration vs metadata → `incomplete`); always-on flags (spec §7.5);
  `EnvironmentProbe` re-probe on launch → onboarding. `rateLimited` just backs
  off — no per-host state yet.
- **Phase 5 — Cookies.** `--cookies-from-browser`; Full Disk Access detection +
  System Settings deep link (Safari) + a Full-Disk-Access `OnboardingStepID`
  case; Firefox multi-profile enumeration + picker (Sign-in & cookies pane);
  Chrome app-bound-encryption fallback; `cookieReadFailed` (non-fatal); the
  "retry with cookies" (`🔑`) row action. Needs Phase 4's `ErrorClass` set +
  live action bar; not rate limiting.
- **Phase 6 — Rate limiting and circuit breaker.** Per-host `RateState`
  (`normal | cooldown | circuitOpen`); cooldown row state; `WarningBanner`
  `cooldown` / `circuitOpen` / `depMissing` cases; circuit breaker →
  `queue.suspended`; adaptive concurrency (more conditions on the Phase 2 loop);
  `NetworkMonitor` → `waitingForNetwork`; `HealthStrip` engine / online /
  cooldown chips. Smoke: force a 429.
- **Phase 7 — YouTube hardening.** `player_client` rotation
  (`tv → ios → tv_embedded → mweb → web_safari`); `PotProviderProcess`
  (supervise the pipx `bgutil-pot` server on a free `127.0.0.1` port, health
  check, restart, stop on quit) + `PotPluginInstaller`; `--extractor-args` +
  `--plugin-dirs` wiring; bot-check-shield `HealthStrip` chip + `↻`; YouTube
  `ErrorClass` cases (`botCheck`, `sabrGated`, `formatsMissing`,
  `potProviderDown`) + copy; `potProviderDown` `WarningBanner` case. Needs both
  Phase 4 and Phase 6.
- **Phase 8 — Playlist.** `MetadataProbe` playlist mode (`--flat-playlist`);
  `PlaylistPickerView` modal (checklist, select all/none, filter, live count +
  size); group-header + spine rendering; group actions (pause all / retry
  failed / cancel all); `MetadataTokenBucket` (built here) + large-playlist
  drip. Re-adds `DownloadJob`'s `playlistGroupID` / `playlistProgress`.
- **Phase 9 — Add flows.** Clipboard auto-detect on activation; Services / Share
  ("Download with …"); drag a URL onto the window or Dock icon; custom URL
  scheme (`CFBundleURLTypes`). All route into the same Home field. Needs only
  the Phase 1 Home field; scheduled here — nothing downstream.
- **Phase 10 — Diagnostics, staleness, updater.** Diagnostics page (Run check →
  report card → Copy report / Copy diagnostic bundle); `DiagnosticBundle` zip;
  yt-dlp staleness banner + daily check; `YtDlpUpdater`; Updates pane rows.
  Report card reflects Phase 4 / 6 / 7 state.
- **Phase 11 — Polish.** Success + chip-refresh-failure toasts; native
  notifications for backgrounded failures; the first-run-cards → table
  transition + emptied-table state; full keyboard-nav + VoiceOver +
  reduced-motion pass over every screen; GitHub-release self-update check (spec
  §10.2). Last — the a11y pass audits every earlier screen.
