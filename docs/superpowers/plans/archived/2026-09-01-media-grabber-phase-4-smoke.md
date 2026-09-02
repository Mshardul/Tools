# Phase 4 Manual Smoke Checklist

> Run on a real machine after `xcodebuild ... test` is green and lint is clean.
> `make` from `apps/media-grabber/` builds, kills any running instance, and launches the new build.

- [ ] **Classified non-recoverable failure.** Grab a private or removed video URL.
  The row shows the plain-English sentence (e.g. `Failed — This video is private.`),
  the Retry (↻) button is disabled, and Show Log (📄) opens the raw per-job log
  in the default text editor.

- [ ] **Network drop → auto-retry → budget stop → manual resume.**
  Start a download, disconnect the network mid-transfer. Within ~45 s the row
  shows `Retrying — attempt 1 of N` (no position badge, no ticking countdown).
  It retries on the backoff schedule; on repeated failure it stops at
  `maxAutoRetries` with the Retry button enabled. Reconnect, press Retry — with a
  `.part` on disk it resumes (yt-dlp continues the partial file).

- [ ] **Normal completion → integrity + real resolution.**
  Grab a video the site serves at a lower height than requested. On completion
  the Quality/Format cell shows `1080p → 720p` (request → actual). The integrity
  check passes silently — no failure, no notice.

- [ ] **Truncated download → `incomplete` → auto-retry.**
  Force a truncation: kill the connection near the end, or launch with a tiny
  `MG_YTDLP_SOCKET_TIMEOUT`. The job fails `The download kept ending early` and
  auto-retries on the backoff schedule.

- [ ] **Backoff tuning path.** Relaunch with `MG_BACKOFF_LADDER=2,4,6` in the
  environment. Trigger a retryable failure — the retry waits shorten to ~2/4/6 s,
  proving `EngineTuning.resolved()` is wired.

- [ ] **ffprobe absent → integrity degrades, downloads unaffected.**
  Rename `ffprobe` away (`mv /opt/homebrew/bin/ffprobe /opt/homebrew/bin/ffprobe.bak`).
  Downloads still complete, the Quality cell shows the request value, and no
  integrity failures occur. Restore it afterwards.

- [ ] **Show Log on an evicted log.** For a job whose `JobLog` file was evicted
  by the 200-cap (or delete it manually), press Show Log — the
  "The log for this download is no longer available." notice appears.
