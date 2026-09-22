# MediaGrabber — leaf backlog

Work not in Phase 1. The repo-root `BACKLOG.md` is **not** touched by this app
until it reaches v1 (spec §14).

**No orphan deferrals.** Every item lives in a numbered phase below. Never a
floating "Phase N follow-ups / deferrals" bucket.

## Documentation

- **Job / rate-limit state-flow diagram.** *(done — `docs/state-flow.md`)*
  Three mermaid state diagrams (job lifecycle, per-host `RateState`,
  `ShieldStatus`) with a full transition table + trigger + `file:line` for
  each, the auto-retry budget, the `availableActions`-vs-`cancel` mismatch on
  `.cooldown` / `.waitingForNetwork`,   and a §4 "parked capabilities" table (each row names its owning phase).
  Revisit whenever a phase adds a state.

- **HLD / LLD architecture doc.** *(done — `docs/architecture.md`)* Both HLD
  and LLD, current (shipped-through-Phase-9) scope only — no future-phase
  sketching. Component map + request path + snapshot/event path + persistence
  path + config path (HLD); ownership graph + actor boundary + async seams +
  event-stream mechanics + key value types + process rules (LLD). 5 mermaid
  diagrams (flowchart, 2× sequence, flowchart, classDiagram), all verified to
  render via `mermaid-cli`. Cross-references `docs/state-flow.md` rather than
  repeating the state machines.

## Phases 2–14 (intent — detailed when reached, from spec §12.1)

Boundaries are dependency cuts: a phase is picked when its inputs exist, and its
scope is drawn so nothing inside waits on a later phase. Shell-and-fill splits
are in spec §12.2.

- **Phase 2 — Queue foundation and window chrome.** *(shipped)* Engine owns the
  queue; Downloads table with columns, sort, filter chips, and row actions;
  `Persistence` for queue/history/columns; graceful quit; `MainWindow` chrome
  shells. Column header drag-reorder UI, multi-select, and resizable widths
  park in **Phase 12**. Progress / Speed / ETA stay separate columns (no merge).
- **Phase 3 — Preferences screen.** 7-pane `PreferencesView` over the existing
  `Preferences` model. Downloads / Appearance / Logs & privacy panes filled;
  Network / Sign-in & cookies / Updates / Advanced are headers later phases add
  rows to. **Appearance pane:** replace native SwiftUI `Menu` dropdowns on the
  Home runway (and prefs controls) with skinned popover pickers that match the
  active palette.
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
- **Phase 6 — Rate limiting and circuit breaker.** *(shipped)* Per-host
  `RateState` (`normal | cooldown | circuitOpen`); cooldown row state;
  `WarningBanner` `circuitOpen` / `networkDown` cases; circuit breaker;
  adaptive concurrency; `NetworkMonitor` → `waitingForNetwork`; `HealthStrip`
  online / cooldown chips. Smoke: force a 429. Per-host adaptive concurrency
  parks in **Phase 13**.
- **Phase 7 — YouTube hardening.** *(shipped)* Engine-owned shield process +
  plugin dirs; `player_client` rotation; `engine.preview` shares YouTube identity
  with Grab; probe format lists; runway Language slot + quality rungs this probe
  offers; Downloads **Audio language** policy; YouTube `ErrorClass` emit + copy;
  VPN hint; shield chip + `↻`; `potProviderDown` banner. Spec:
  `docs/superpowers/specs/archived/2026-09-07-media-grabber-phase-7.md`.
  Refresh engine `shieldStatus` after shield crash auto-recovery parks in
  **Phase 11** (engine-freshness / HealthStrip chip work).
- **Phase 8 — Playlist.** *(shipped)* YouTube watch = one video; `PL` playlist
  page = one `--flat-playlist` dump, picker (checklist, filter, duration footer,
  duplicate warnings), then N jobs sharing `playlistGroupID`. Group header +
  spine + group actions; `MetadataTokenBucket`; per-request probe cancel. Spec:
  `docs/superpowers/specs/archived/2026-09-08-media-grabber-phase-8.md`.
- **Phase 9 — Add flows.** *(shipped)* Clipboard (activation + frontmost poll,
  prefs-gated, self-write ignore, dedupe); drag window/Dock; Services;
  `mediagrabber://open?url=` scheme → `IncomingLinkController` + Home. Idle
  silent / busy confirm; scheme-failure notice. `LinkExtractor` pure first-http(s).
  Spec + plan: `docs/superpowers/specs/archived/2026-09-10-media-grabber-phase-9.md`,
  `docs/superpowers/plans/archived/2026-09-10-media-grabber-phase-9.md`. Share
  Extension is a sibling stub, not this phase.
- **Phase 10 — Share Extension.** *(shipped)* New `ShareExtension` appex
  target, scheme-only handoff (no App Group), one share action reusing the
  Phase 9 `mediagrabber://open` path. Spec + plan:
  `docs/superpowers/specs/archived/2026-09-11-media-grabber-phase-10-share-extension.md`,
  `docs/superpowers/plans/archived/2026-09-11-media-grabber-phase-10-share-extension.md`.
  App icon + Share Extension first-enable nudge park in **Phase 13**.
- **Phase 11 — Diagnostics, About, updates + Home manager chrome.** *(shipped)* Diagnostics
  moves into Preferences (System group) rather than top-level nav; report card,
  Copy report, and Share diagnostic bundle (system share sheet, not a plain
  clipboard copy) built here, plus the **real canary probe** shared with
  Onboarding's `testRun` (closes the Phase 1 auto-pass gap — one canary
  concept, not two). yt-dlp version pinning: a declared minimum-known-good
  version, checked on every launch (local compare, no network), with a `↻`
  action (uniform busy state across every actionable chip) that reinstalls to
  the declared minimum — never an unconditional upgrade. About replaces
  Diagnostics as the third top-level nav item (About + Developer tabs); every
  version and action button (MediaGrabber, yt-dlp, ffmpeg) lives there, with a
  button verb tracking certainty (nothing shown / "Check for updates" /
  "Update"); the MediaGrabber GitHub-release self-update check (spec §10.2)
  is built here rather than Phase 13, since About's rows need real backing
  logic in the phase that builds them. Preferences → Updates is filled with
  settings only (two auto-check toggles), no version numbers or actions.
  Report card reflects Phase 4 / 6 / 7 state. Also: refresh engine
  `shieldStatus` after shield crash auto-recovery so chip/banner track live
  provider status.

  **Home manager chrome (locked 2026-09-12, absorbed here — Option A):** status
  left rail (`All` / `Downloading` / `Done` / `Inactive` with badge on Inactive) — replaces top filter chips (do not keep both). **Status**
  column stays in Columns but **hidden by default** (rail is everyday filter).
  Status labels are 1:1 with the 9 `JobState`s (plain-language only; no
  invented display statuses such as `retrying` or host-`cooling down` on a
  `.queued` job). Backoff / host rate / attempt / failure reason → **Remark**
  (hover + keyboard focus; optional Columns-menu column; a11y not hover-only).
  Playlist groups: show the group if any child matches the selected rail
  status. **Onboarding Install primacy** — primary CTA is Install now;
  brew/pipx command + Copy / Open in Terminal are secondary. Phase 11 plan
  rewrites parent §5.3 / §5.4 + design-system + Home/onboarding mockups to
  match before implement. Site friendly host names if not already shipped.
  *(First-run empty Home copy/layout redesign and Aurora body face stay
  Phase 13.)*

  **Status model (locked 2026-09-12):** Keep the nine `JobState` cases. Row
  status = those nine, 1:1 (aliases OK: `running`→Downloading, `completed`→Saved).
  Rail = filters only (many-to-one), not a second status vocabulary. Detail
  that is not the job’s own state lives in Remark / HealthStrip — never as a
  rewritten Status string.

  **Rail mapping (locked 2026-09-12):** Downloading = probing, running, queued,
  paused, waitingForNetwork, cooldown. Done = completed only. **Inactive**
  (rail label only; row status stays Failed vs Cancelled) = failed, cancelled.
  All = everything. From failed/cancelled: Restart (not Resume); cookie-restart
  only when the failure class offers it. **Actions (locked 2026-09-12):**
  Remove = delete persistence entry (+ parts + job log); Cancel = keep as
  `cancelled` (on cooldown: clear job deferral only, host rate unchanged);
  Restart always `attempt = 0`; no Restart on Saved; Log on cooldown +
  waitingForNetwork; Force start on queued only when not immediately
  schedulable; UI strings Force start / Restart / Restart with sign-in;
  depMissing = queueHalt + blocking dialog (not mass Pause); playlist group:
  Pause all (running), Restart failed (failed+cancelled), Cancel all (includes
  cooldown + waitingForNetwork), keep expand/collapse. Contract:
  `docs/job-status-and-actions.md`. Plan:
  `docs/superpowers/plans/2026-09-12-media-grabber-phase-11.md`.
- **Phase 12 — Downloads table chrome.** Column header drag-reorder UI (wire
  existing `ColumnConfig.moveColumn` + persistence); resizable column widths
  (drag handles + persist in `ColumnConfig`); multi-select row actions (plan
  **reverses** parent §5.4 “no row selection” and ships selection + batch
  actions in this phase). **Queue-row drag-reorder parks in Phase 14**
  (locked 2026-09-22 — column chrome + multi-select is enough this phase;
  row reorder needs engine order semantics and fights active sort).
  **Progress, Speed, and ETA stay separate columns** (locked 2026-09-12 — no
  merged transfer column). Builds on Phase 11’s manager Home (rail; Status
  hidden by default) — do not reintroduce filter chips. Multi-select batch
  verbs match row / playlist group eligibility
  (`job-status-and-actions.md` §8); Force start only when exactly one eligible
  row is selected. **Batch chrome (locked 2026-09-22):** when selection is
  non-empty, a bar above the table (`N selected` + eligible batch verbs)
  appears; empty selection hides it. Not a floating footer. **Per-row Actions
  stay visible while a selection is active** (locked 2026-09-22) — batch bar
  is additive; a row action still targets only that row. **Header select-all
  (locked 2026-09-22):** selects every currently visible row (after rail +
  column filters); does not select collapsed-away playlist children.
  **Selection vs rail/filters (locked 2026-09-22):** on rail or column-filter
  change, keep selected job IDs that remain visible; drop the rest (no
  “remember off-screen” batch). Empty residual → hide batch bar.
  **Resize (locked 2026-09-22):** every data column except Actions + the
  checkbox column; min-width clamp; double-click divider auto-fits that
  column to widest visible cell (one-shot). Widths persist in `ColumnConfig`.
  **Multi-select input (locked 2026-09-22):** checkboxes + ⌘-click row toggle
  + Shift-click range (visible-row order).
  **Table substrate (locked 2026-09-22):** AppKit owns the **entire** Downloads
  table surface (headers, rows, selection, column resize/reorder, scroll);
  SwiftUI owns Home chrome outside that rect (rail, batch bar, Columns menu,
  dialogs, rest of app). Cells/headers are **AppKit-drawn** with shared design
  tokens — not default `NSHostingView` per cell. Not a pure SwiftUI `Table`;
  not forever-extending today’s LazyVStack. Phase 14 row-reorder uses this
  same grid.
- **Phase 13 — Polish.** Success + chip-refresh-failure toasts; native
  notifications for backgrounded failures; the first-run-cards → table
  transition + emptied-table state; full keyboard-nav + VoiceOver +
  reduced-motion pass over every screen (last — audits every earlier screen).
  **Bundle Aurora typefaces** (Sora / Inter / JetBrains Mono under
  `Sources/App/Resources/Fonts/**` + `ATSApplicationFontsPath`; then apply any
  Aurora body-face swap decided in this phase). **Product-name decision
  (spec §14)** — pick the real name and find-and-replace
  `MediaGrabber` / `app.mediagrabber.mac`. **App icon** (`.icns` / `.xcassets`).
  **Share Extension first-enable hint** — evaluate a first-run nudge (macOS
  disables Share Extensions until enabled once). **Debug menu** — review
  whether a `DebugFlags` Debug menu is warranted. **Home banner → footer** —
  fixed footer; info/warning content moves into HealthStrip chips. **Per-host
  adaptive concurrency** — cap trio per `RateHost`; `Scheduler.nextDownloads`
  per-host slot accounting (additive on Phase 6 seams). *Hint (UI review
  2026-09-12):* first-run empty Home — redesign kicker / headline / step-card
  copy and composition. *Hint (UI review 2026-09-12):* Aurora body face —
  replace Inter with a more distinctive grotesk (with font bundling above).
  *Hint (from Phase 12):* live column-width readout while resizing.
- **Phase 14 — Post-v1 maturity.** Playlist-group aggregate state (engine);
  real metadata-probe token bucket + visibility; POT/shield rotation;
  always-on-cookies model; remote `player_client` order JSON; per-site helpers
  beyond YouTube; **queue-row drag-reorder** (parked from Phase 12); optional
  UX extras (subtitles/embed, menu bar, schedules, stats, bandwidth graphs,
  per-skin light/dark, compact breakpoint); evaluate `.shieldDown` halt +
  `.userReset` soft transition (ship or drop in plan); Sparkle/notarization/
  bundled deps only if Developer ID exists. Full stub in parent §12.1.

