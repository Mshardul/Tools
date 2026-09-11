# MediaGrabber

A small macOS app that takes one pasted video URL, resolves its title, and
downloads the file with a live progress bar — then shows "Saved" with a
Reveal-in-Finder action. It shells out to [`yt-dlp`](https://github.com/yt-dlp/yt-dlp)
(one child process per download) and uses `ffmpeg` for muxing. Neither tool is
bundled; the app installs both through Homebrew on first run if they are
missing.

> **Working name.** `MediaGrabber` / bundle ID `app.mediagrabber.mac` are
> placeholders. The final product name is deferred; renaming later is a
> mechanical find-and-replace.

## Requirements

- macOS 14.0 or later.
- [Homebrew](https://brew.sh). The app runs `brew install yt-dlp ffmpeg` for you
  on first launch if the tools aren't already on `PATH`; if Homebrew itself is
  missing, onboarding shows the one-line install command to paste into Terminal.

## Run locally

```bash
brew install mise
cd apps/media-grabber
mise install
make
```

`make` (same as `make run`) rebuilds from current sources, kills any running
MediaGrabber, and opens the new build. Running it again replaces the previous
instance instead of launching a second copy.

Tests and the Xcode workspace:

```bash
mise exec -- tuist generate --no-open
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' test
```

Lint:

```bash
mise exec -- swiftformat --lint .
mise exec -- swiftlint lint --strict
```

## Running a downloaded build (Gatekeeper)

Builds are ad-hoc signed (no paid Apple Developer account), so a copy you
downloaded is quarantined. One-time unblock, either:

- **System Settings → Privacy & Security →** scroll to the blocked-app notice →
  **Open Anyway**, then confirm on the next launch; or
- `xattr -dr com.apple.quarantine /Applications/MediaGrabber.app`

A build you compiled yourself is not quarantined and needs neither step.

## Where things land

- **Downloads:** `~/Downloads` by default, changeable per-download in the
  runway or as a default in Preferences → Downloads.
- **Logs:** `~/Library/Logs/MediaGrabber/` — local only, never uploaded.
  - `app.log` — app-wide events (launch, probes, duplicate prompts, quit).
  - `jobs/<job-id>.log` — one raw `yt-dlp` transcript per download.
  See [PRIVACY.md](PRIVACY.md) for exactly what they contain.
- **Persisted state:** `queue.json`, `history.json`, and `columns.json` under
  `~/Library/Application Support/MediaGrabber/` — relaunch restores the queue.

## What the app does today

A multi-download queue with a live table (pause / resume / cancel / remove /
force-start per row), rate limiting and a circuit breaker per host, retry with
error-class-aware messaging, cookie-based sign-in for gated videos, a
bot-check shield for YouTube, playlist paste → picker → grouped rows, and
add-flow ingress (clipboard, drag, Services, a `mediagrabber://` URL scheme) —
every entry point lands in the same Home field. Graceful quit confirms when a
download is active, flushes persistence, then shuts down child processes.

For how it fits together: [`docs/architecture.md`](docs/architecture.md)
(component map, request/event/persistence paths) and
[`docs/state-flow.md`](docs/state-flow.md) (every job, rate-limit, and shield
state with its triggers).

Debug flags: `-MGForceOnboarding`, `-MGResetState`, `-MGConcurrencyCap N`.

Not yet built: Diagnostics page content, column header drag-reorder
(`ColumnConfig.moveColumn` exists; no UI), multi-select row actions, a Share
Extension. See [ticket-backlog.md](ticket-backlog.md).

## Known gaps

- **The Aurora typefaces (Sora / Inter / JetBrains Mono) aren't bundled** — the
  UI falls back to system faces. Tracked in
  [ticket-backlog.md](ticket-backlog.md).

## License

MIT.
