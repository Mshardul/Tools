# Privacy

MediaGrabber keeps everything on your machine. There is **no telemetry and no
network egress from the logging subsystem — ever.** The only network traffic the
app makes is `yt-dlp` fetching the video you asked for.

## Logs

Written to `~/Library/Logs/MediaGrabber/`:

- `app.log` — structured JSON Lines, one event per line (app launch, probe
  results, job state changes, `yt-dlp` process launch/exit). Rotated at 5 files
  × 5 MB.
- Mirrored to the macOS unified log (`log show --predicate 'subsystem ==
  "app.mediagrabber.mac"'`).

### Logged in the clear

Needed for debugging a failed download:

- Video / playlist URLs.
- Video / playlist titles.
- The destination folder, written as `~/…`.

### Always redacted

Applied in the log-line builder, before anything is written:

- **Cookie contents.**
- **Proxy credentials** — the host is kept, the `user:password@` is removed
  (`http://u:p@host` → `http://host`).
- Any `--username` / `--password` values.
- **Absolute home paths** — `/Users/<name>/…` is rewritten to `~/…`.

## Sharing a diagnostic bundle

Not available in Phase 1. When it lands, it will re-run redaction at zip time
and list exactly what the archive contains before saving. Logs never leave your
machine unless you explicitly create and share such a bundle.
