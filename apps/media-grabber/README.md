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

- **Downloads:** `~/Downloads` by default (change it per-download in the runway,
  or set a default in Preferences once that pane lands).
- **Logs:** `~/Library/Logs/MediaGrabber/` — local only, never uploaded.
  - `app.log` — app-wide events (launch, probes, duplicate prompts, quit).
  - `jobs/<job-id>.log` — one raw `yt-dlp` transcript per download.
  See [PRIVACY.md](PRIVACY.md) for exactly what they contain.

## Phase 2 (shipped)

Phase 2 added a multi-download queue with persistence:

- **Queue + table** — paste URLs, watch several jobs run under
  `Preferences.maxConcurrentDownloads`, pause/resume/cancel/remove/force-start
  from the row action bar.
- **Persistence** — `queue.json`, `history.json`, and `columns.json` under
  `~/Library/Application Support/MediaGrabber/`; relaunch restores the queue.
- **Graceful quit** — confirm when a download is active or the queue is halted,
  flush persistence, then shut down child processes.
- **Debug flags** — `-MGForceOnboarding`, `-MGResetState`, `-MGConcurrencyCap N`.

Not yet built:

- **Column header drag-reorder** — `ColumnConfig.moveColumn` exists; UI deferred.
- **Multi-select row actions**, playlists, cookies, retry/backoff, Preferences
  panes (beyond the model), Diagnostics content. See
  [ticket-backlog.md](ticket-backlog.md).

**Next:** Phase 3 — Preferences screen (7-pane UI).

## Phase 1 gaps (resolved in Phase 2)

- ~~No queue~~ — now multi-download with scheduler.
- ~~No persistence / resume~~ — queue + history persist; `.part` files resume.

Still open from Phase 1:

- **The Aurora typefaces (Sora / Inter / JetBrains Mono) aren't bundled** — the
  UI falls back to system faces. Tracked in
  [ticket-backlog.md](ticket-backlog.md).

## License

MIT.
