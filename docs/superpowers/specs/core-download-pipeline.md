# Core download pipeline (Phase 1)

**Status:** built. Plan: `docs/superpowers/plans/2026-08-29-media-grabber-phase-1.md`.
Parent spec: `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1.

The load-bearing path everything else layers onto: onboarding → paste → probe →
download engine → saved file → Reveal.

---

## Phase 1 — "one file, start to finish"

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
