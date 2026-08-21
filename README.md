# Tools

A collection of small personal tools. Each leaf directory is an independent project. Tools that outgrow this repo move to their own.

| Tool | Bucket | Status | What it does |
|---|---|---|---|
| [claude-usage](apps/claude-usage/) | apps | active | Browser dashboard for Claude Code token usage |
| [youtube-downloader](cli/youtube-downloader/) | cli | active | Multi-threaded YouTube downloader built on `yt-dlp` |

Empty buckets: [`extensions/chrome/`](extensions/chrome/), [`extensions/vlc/`](extensions/vlc/). Add a catalog row when a tool lands there.

Older one-off scripts live in [`archive/`](archive/). They are kept for reference, not as the supported versions.

## Adding a tool

1. Pick a bucket: `apps/`, `cli/`, `extensions/chrome/`, `extensions/vlc/`.
2. Create a `kebab-case` directory with its own `README.md` (what it is, how to run, one “not for” line) and its own deps file if it has dependencies.
3. Do not commit secrets or machine-specific paths.
4. Add a row to the table above (`active`).

## Layout

```
apps/                 # small web or desktop apps
cli/                  # command-line tools
extensions/chrome/
extensions/vlc/
archive/              # superseded one-offs
docs/                 # collection-level design notes
```

Design notes: [`docs/superpowers/`](docs/superpowers/).
