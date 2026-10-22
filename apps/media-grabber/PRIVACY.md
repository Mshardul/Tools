# Privacy

MediaGrabber keeps your data on your Mac. There is **no telemetry, no account, and no analytics**, and the logging system never sends anything over the network.

## What the app connects to

The app only talks to the network for the things listed here.

- **Sites you download from.** `yt-dlp` fetches the video or audio you asked for, directly from the site.
- **Link lookups.** When you paste a link, or the app picks one up from your clipboard, `yt-dlp` asks that site for the title and available formats.
- **Setup check.** The first-run check and Diagnostics → Run check read a public test video on archive.org to confirm downloading works.
- **Update check.** If "Check for app updates automatically" is on, the app asks GitHub for the latest release when it starts. About → Check for updates does the same when you press it. GitHub sees your network address like any web request. Turn the automatic check off in Preferences → Updates.
- **Installing tools.** First-run setup and the downloader's Update button use Homebrew to install `yt-dlp`, `ffmpeg` and Node. The bot-check helper is downloaded from GitHub and built with npm.
- **Bot-check helper.** It runs on your Mac and answers only on `127.0.0.1`. It contacts YouTube while preparing its token.

Nothing else is sent anywhere.

## Browser sign-in

Using a browser's sign-in is opt-in (Preferences → Sign-in & cookies). When you pick a browser, `yt-dlp` reads its cookies on your Mac and sends them to the site you are downloading from, the same way the browser would. MediaGrabber stores only which browser you chose. Cookie contents are never written to the logs.

## Clipboard detection

When "Clipboard detection" is on (the default), the app reads text you copy while it is in front and looks for a web link. If it finds one, it looks that link up as described above. The clipboard text itself is not stored.

## What is stored on your Mac

- Your preferences.
- The download list and history (`queue.json`, `history.json`) in `~/Library/Application Support/MediaGrabber/`: links, titles and folders.
- Logs in `~/Library/Logs/MediaGrabber/`:
  - `app.log` — structured JSON Lines, one event per line (app launch, probe results, job state changes, duplicate-submit prompts, quit). Rotated at 5 files × 5 MB.
  - `jobs/<job-id>.log` — the raw `yt-dlp` output for one download. One file per job; deleted when the job row is removed.
  - Also mirrored to the macOS unified log (`log show --predicate 'subsystem == "app.mediagrabber.mac"'`).

### Logged in the clear

Needed for debugging a failed download:

- Video and playlist links.
- Video and playlist titles.
- The destination folder, written as `~/…`.

### Always redacted

Applied in the log-line builder, before anything is written:

- **Cookie contents.**
- **Proxy credentials** — the host is kept, the `user:password@` is removed (`http://u:p@host` → `http://host`).
- Any `--username` / `--password` values.
- **Absolute home paths** — `/Users/<name>/…` is rewritten to `~/…`.

## Sharing a diagnostic bundle

Diagnostics → Share diagnostic bundle creates a zip of the last 200 lines of `app.log`, the log of your most recent download, and the Diagnostics report. It is only created when you press the button, and it goes where you send it from the system share sheet. Home folder paths are rewritten to `~/` in the bundle. Logs include the links and titles listed above, so share the bundle only with people you trust.
