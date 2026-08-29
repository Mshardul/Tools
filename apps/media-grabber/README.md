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

## Build from source

```bash
brew install mise
cd apps/media-grabber
mise install                      # pins tuist / swiftformat / swiftlint
mise exec -- tuist generate       # writes MediaGrabber.xcworkspace (gitignored)
```

Open `MediaGrabber.xcworkspace` and run the `MediaGrabber` scheme, or from the
command line:

```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace \
  -destination 'platform=macOS' test        # full unit suite
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber \
  -destination 'platform=macOS' build
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
- **Logs:** `~/Library/Logs/MediaGrabber/` — local only, never uploaded. See
  [PRIVACY.md](PRIVACY.md) for exactly what they contain.

## Phase 1 scope and known gaps

Phase 1 is one URL in, one file out. Not yet built:

- **No queue** — one download at a time.
- **No persistence / resume** — quitting mid-download loses the job; the partial
  `.part` file is left on disk.
- **No retry / backoff / rate-limit handling**, no cookies, no playlists, no
  clipboard/share/drag add-flows. Preferences and Diagnostics panes are present
  but empty.
- **The Aurora typefaces (Sora / Inter / JetBrains Mono) aren't bundled** — the
  UI falls back to system faces. Tracked in
  [ticket-backlog.md](ticket-backlog.md).

## License

MIT.
