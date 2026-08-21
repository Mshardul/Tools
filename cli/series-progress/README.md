# Series folder progress

**Backlog:** T-008 · `series-progress`

Sidecar (`.series-progress`) for which episode to resume in a folder. Stdlib only.

```bash
# from repo root
.venv/bin/python cli/series-progress/series_progress.py ~/Shows/Foo
.venv/bin/python cli/series-progress/series_progress.py ~/Shows/Foo --set S01E03.mkv
.venv/bin/python cli/series-progress/series_progress.py ~/Shows/Foo --next
.venv/bin/python cli/series-progress/series_progress.py ~/Shows/Foo --mark-done
.venv/bin/python cli/series-progress/series_progress.py ~/Shows/Foo --list
.venv/bin/python cli/series-progress/series_progress.py ~/Shows/Foo --json
```

Default (no flags): print the resume target (saved current, else first video file).  
Video suffixes: `.mkv` `.mp4` `.avi` `.m4v` `.mov` `.wmv` `.webm` `.ts` `.m2ts`.

**Not for:** scraping remote episode databases, or controlling VLC directly.
