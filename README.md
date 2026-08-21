# Tools

A collection of small open-source tools (MIT). Each leaf directory is an independent project. Tools that outgrow this repo move to their own.

| Tool | Bucket | Status | What it does |
|---|---|---|---|
| [claude-usage](apps/claude-usage/) | apps | active | Browser dashboard for Claude Code token usage |
| [youtube-downloader](cli/youtube-downloader/) | cli | active | Multi-threaded YouTube downloader built on `yt-dlp` |
| [id-gen](cli/id-gen/) | cli | active | Generate uuid / nanoid |
| [password-gen](cli/password-gen/) | cli | active | Random passwords |
| [port-tool](cli/port-tool/) | cli | active | Who owns a TCP port, or kill it |
| [pb](cli/pb/) | cli | active | Read/write macOS clipboard |
| [trash](cli/trash/) | cli | active | Move paths to Trash (default: `~/.Trash`) |
| [notify](cli/notify/) | cli | active | macOS notification from the CLI |
| [base64-tool](cli/base64-tool/) | cli | active | Encode or decode Base64 |
| [jwt-decode](cli/jwt-decode/) | cli | active | Decode JWT header/payload (no verify) |
| [unix-timestamp](cli/unix-timestamp/) | cli | active | Unix time ↔ ISO-8601 UTC |
| [url-encode](cli/url-encode/) | cli | active | Percent-encode or decode strings |
| [json-format](cli/json-format/) | cli | active | Pretty-print or minify JSON |
| [case-transform](cli/case-transform/) | cli | active | camel / snake / kebab / Pascal |
| [slugify](cli/slugify/) | cli | active | Title → kebab-case slug |
| [file-hash](cli/file-hash/) | cli | active | Hash a file or string (SHA-256…) |
| [line-sort](cli/line-sort/) | cli | active | Sort, unique, or reverse lines |
| [shell-escape](cli/shell-escape/) | cli | active | Escape a string for safe shell use |
| [regex-test](cli/regex-test/) | cli | active | Test a regex against a string |
| [html-entities](cli/html-entities/) | cli | active | Encode or decode HTML entities |
| [color-convert](cli/color-convert/) | cli | active | Convert hex ↔ rgb ↔ hsl |
| [number-base](cli/number-base/) | cli | active | Convert among bin / oct / dec / hex |
| [timezone-convert](cli/timezone-convert/) | cli | active | Convert a time across timezones |
| [line-endings](cli/line-endings/) | cli | active | Convert CRLF ↔ LF |

Planned work lives in [`BACKLOG.md`](BACKLOG.md). Empty buckets: [`extensions/chrome/`](extensions/chrome/), [`extensions/vlc/`](extensions/vlc/), [`extensions/macos/`](extensions/macos/). Add a catalog row when a tool lands there.

Older one-off scripts live in [`archive/`](archive/). They are kept for reference, not as the supported versions.

## Adding a tool

1. Add a row in `BACKLOG.md`. Create `bucket/slug/` immediately with a stub `README.md`.
2. When status is `building`, add `ticket-backlog.md` and implement in that directory.
3. Tiny related conversions share **one** leaf with source/target (or mode) options — see Backlog leaf rules.
4. Do not commit secrets or machine-specific paths.
5. When `active`, ensure the catalog table above links to the leaf. Default publish path is this GitHub repo, free.

## Layout

```
apps/                 # small web or desktop apps
cli/                  # command-line tools
extensions/chrome/
extensions/vlc/
extensions/macos/     # Finder, Share, Shortcuts; full Mac apps may live under apps/
archive/              # superseded one-offs
docs/                 # collection-level design notes
BACKLOG.md            # inventory of current and planned tools
```

Design notes: [`docs/superpowers/`](docs/superpowers/). License: [`LICENSE`](LICENSE).

Reusable agent prompt for implementing backlog leaves: [`.prompts/build-mini-tool.md`](.prompts/build-mini-tool.md).
