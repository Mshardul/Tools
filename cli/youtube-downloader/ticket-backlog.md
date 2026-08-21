# Ticket backlog — youtube-downloader

**Root id:** T-002  
**Publish:** github (this repo)  
**License:** MIT (repo root)

CLI wrapper around yt-dlp: concurrent downloads, formats, subtitles, config.ini. Not a GUI or hosted service. Only for content you have the right to copy.

## Tickets

| id | title | status | notes |
|---|---|---|---|
| T-002-1 | Document real entrypoint (`main.py`) vs stale `src/` path in readme | idea | Readme still mentions `src/youtube_downloader/main.py` |
| T-002-2 | Companion Chrome “send URL here” | idea | Tracked as T-006; do not build inside this leaf |

## Open questions

- Cookie / 403 handling stays yt-dlp’s problem unless we add an explicit, documented flag.
