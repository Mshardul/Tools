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

## Phases 2–11 (intent — detailed when reached, from spec §12.2)

- **Phase 2 — Queue + scheduler.** Many jobs; fixed concurrency cap; the real
  Downloads table (columns, show/hide, drag-reorder, per-column sort + filter,
  filter chips); row actions; force-start (`⏫`, round-robin). `ColumnConfig`
  model, not yet persisted.
- **Phase 3 — Persistence.** `queue.json` + `columns.json` (debounced); on
  launch reload the queue and reset `.running` → `.queued` (yt-dlp `.part`
  enables resume); graceful quit (confirm → SIGTERM → persist → resume).
- **Phase 4 — Resilience core.** Per-host `RateState`
  (`normal | cooldown | circuitOpen`); `Backoff` (exponential + full jitter,
  cap, `Retry-After`); full `ErrorClass` classification + failure UI; per-job
  auto-retry budget (`Preferences.maxAutoAttempts`); cooldown row state + docked
  warning banner; circuit breaker → `queue.suspended`; `MetadataTokenBucket`;
  adaptive concurrency (streak up / throttle down); `NetworkMonitor` →
  `waitingForNetwork`; the always-on download flags (spec §7.5).
- **Phase 5 — YouTube hardening.** `player_client` rotation
  (`tv → ios → tv_embedded → mweb → web_safari`); `PotProviderProcess`
  (supervise the pipx `bgutil-pot` server on a free `127.0.0.1` port, health
  check, restart, stop on quit) + `PotPluginInstaller`; `--extractor-args` +
  `--plugin-dirs` wiring; the bot-check-shield health chip + `↻` refresh;
  `sabrGated` / `formatsMissing` classes and their failure copy.
- **Phase 6 — Cookies.** `--cookies-from-browser`; Full Disk Access detection +
  System Settings deep link (Safari); Firefox multi-profile enumeration +
  picker; Chrome app-bound-encryption fallback; `cookieReadFailed` (non-fatal);
  the "retry with cookies" (`🔑`) row action.
- **Phase 7 — Playlist.** `MetadataProbe` playlist mode (`--flat-playlist`);
  `PlaylistPickerView` modal (checklist, select all/none, filter, live count +
  size); group-header + spine rendering; group actions (pause all / retry
  failed / cancel all); large-playlist drip. Re-adds `DownloadJob`'s
  `playlistGroupID` / `playlistProgress`.
- **Phase 8 — Add flows.** Clipboard auto-detect on activation; Services / Share
  ("Download with …"); drag a URL onto the window or Dock icon; custom URL
  scheme (`CFBundleURLTypes`). All route into the same Home field.
- **Phase 9 — Preferences UI.** All 7 panes (design-system §4.6); Skin + Palette
  pickers wired to `Preferences`; every remaining setting connected;
  `firefoxProfile`, `autoCheckUpdates`, `maxAutoAttempts` surfaced.
- **Phase 10 — Diagnostics + integrity.** `IntegrityCheck` (ffprobe duration vs
  metadata → `incomplete`); Diagnostics page (Run check → report card → Copy
  report / Copy diagnostic bundle); `DiagnosticBundle` zip; yt-dlp staleness
  banner + daily check; `YtDlpUpdater`.
- **Phase 11 — Polish.** Success + chip-refresh-failure toasts; native
  notifications for backgrounded failures; the first-run-cards → table
  transition + emptied-table state; full keyboard-nav + VoiceOver pass;
  reduced-motion audit; GitHub-release self-update check (spec §10.2).
