# Tools

A collection of small open-source tools (MIT). Each leaf directory is an independent project. Tools that outgrow this repo move to their own.

## Python environment

Use one shared virtualenv at the **repo root** (never per-leaf `.venv`):

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Run tools with that interpreter, e.g. `.venv/bin/python cli/data-convert/data_convert.py …`, or `source .venv/bin/activate` first. Most leaves are stdlib-only; optional pins live in leaf `requirements.txt` files and are aggregated in the root `requirements.txt`.

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
| [data-convert](cli/data-convert/) | cli | active | Convert among json / yaml / toml / csv / env |
| [file-size](cli/file-size/) | cli | active | Human-readable size of a path |
| [dir-du](cli/dir-du/) | cli | active | Disk usage summary for a folder |
| [big-files](cli/big-files/) | cli | active | Largest N files under a path |
| [strip-exif](cli/strip-exif/) | cli | active | Remove EXIF/GPS metadata from JPEG/PNG |
| [ssl-expiry](cli/ssl-expiry/) | cli | active | Days until TLS cert expires for a host |
| [quarantine-clear](extensions/macos/quarantine-clear/) | ext/macos | active | Clear Gatekeeper quarantine xattr |
| [file-snippets](cli/file-snippets/) | cli | active | List/show snippets from a folder |
| [json-query](cli/json-query/) | cli | active | Tiny path query on JSON (jq-lite) |
| [secret-scan](cli/secret-scan/) | cli | active | Scan files for likely API keys |
| [srt-shifter](cli/srt-shifter/) | cli | active | Shift SRT/VTT timings by milliseconds |
| [cron-explain](cli/cron-explain/) | cli | active | Explain a cron expression in English |
| [xml-format](cli/xml-format/) | cli | active | Pretty-print or minify XML |
| [qr-encode](cli/qr-encode/) | cli | active | Encode text as QR (ASCII or PNG) |
| [image-tool](cli/image-tool/) | cli | active | Resize, compress, or convert images |
| [git-large-files](cli/git-large-files/) | cli | active | Large blobs in git history |
| [series-progress](cli/series-progress/) | cli | active | Sidecar: which episode to resume |
| [open-terminal-here](extensions/macos/open-terminal-here/) | ext/macos | active | Open Terminal at a folder |
| [floating-note](apps/floating-note/) | apps | active | Always-on-top scratchpad (tkinter) |
| [world-clock](apps/world-clock/) | apps | active | Current time in a few IANA zones (CLI-first) |
| [battery-eta](apps/battery-eta/) | apps | active | Battery percent / charge / ETA from pmset |
| [pomodoro](apps/pomodoro/) | apps | active | CLI 25/5 focus timer with notification |
| [focus-toggle](extensions/macos/focus-toggle/) | ext/macos | active | Focus on/off/toggle via Shortcuts |
| [mic-mute](extensions/macos/mic-mute/) | ext/macos | active | Mute/unmute mic input volume |
| [vlc-skip-chapter](extensions/vlc/vlc-skip-chapter/) | ext/vlc | active | Skip Intro/Credits chapters in VLC |

Planned work lives in [`BACKLOG.md`](BACKLOG.md). Empty bucket: [`extensions/chrome/`](extensions/chrome/) (stub only until `send-to-downloader` lands).

Older one-off scripts live in [`archive/`](archive/). They are kept for reference, not as the supported versions.

## Adding a tool

1. Add a row in `BACKLOG.md`. Create `bucket/slug/` immediately with a stub `README.md`.
2. When status is `building`, add `ticket-backlog.md` and implement in that directory.
3. Tiny related conversions share **one** leaf with source/target (or mode) options — see Backlog leaf rules.
4. Do not commit secrets or machine-specific paths.
5. When a leaf needs a Python pin, add `bucket/slug/requirements.txt` and include it from the root `requirements.txt`; install only into the repo-root `.venv`.
6. When `active`, ensure the catalog table above links to the leaf. Default publish path is this GitHub repo, free.

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
