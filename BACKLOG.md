# Backlog

Inventory of tools in this nursery. MIT unless a leaf says otherwise. GitHub (this repo) is the default free download path; VideoLAN / Chrome Web Store / Mac App Store only when `publish` says so.

**Status:** `idea` → `next` → `building` → `active` → `published` → `graduated` / `dropped`

**Priority:** P1 now · P2 soon · P3 later · P4 someday · P5 icebox. At most two P1 rows.

**Effort:** low (hours) · medium (days) · high (might graduate).

**Depends:** other `id`s, or `—`.

## Leaf rules

1. **One directory per mini-tool** at `bucket/slug/` (e.g. `cli/uuid-gen/`). Create the directory when the row is added — not only at `building`. Include at least a stub `README.md`. Add `ticket-backlog.md` when status is `building` or later.
2. **Combine tiny conversions.** If the job is only “turn A into B” among a small set of related types (number bases, data formats, color models, encode/decode), ship **one** leaf with flags or prompts for source and target (or mode). Do **not** create a separate tool per direction or per pair.
3. **Do not** merge unrelated jobs into a mega-utils binary (uuid + trash + weather stays separate leaves).
4. **No alias leaves.** If the job is a thin wrap of `git`, `gh`, `curl`, `dig`, `diff`, `wc`, `open`, `say`, `date`, `diskutil`, or a one-line shell snippet you already have — do not add a row. Prefer an alias, or mark `dropped`.

Nested tickets use `{id}-1`, `{id}-2`.

| id | name | slug | bucket | status | priority | effort | publish | depends | summary |
|---|---|---|---|---|---|---|---|---|---|
| T-001 | Claude Usage | claude-usage | apps | active | P3 | medium | github | — | Local dashboard for Claude Code token usage |
| T-002 | YouTube Downloader | youtube-downloader | cli | active | P3 | high | github | — | Multi-threaded yt-dlp downloader with config |
| T-003 | VLC per-file memory | vlc-file-memory | ext/vlc | active | P2 | medium | github | — | Remember audio, subtitle, and delay per file |
| T-004 | SRT shifter | srt-shifter | cli | active | P2 | low | github | — | Shift SRT/VTT timings by milliseconds and save |
| T-005 | VLC skip chapter by name | vlc-skip-chapter | ext/vlc | active | P3 | low | github | T-003 | Auto-skip MKV chapters named Intro or Credits |
| T-006 | Send tab to downloader | send-to-downloader | ext/chrome | active | P2 | medium | github | T-002 | Right-click or toolbar sends the tab URL to the CLI |
| T-007 | Claude session archive | claude-session-archive | apps | active | P3 | medium | github | T-001 | Search and export local Claude Code JSONL sessions |
| T-008 | Series folder progress | series-progress | cli | active | P4 | medium | github | — | Sidecar file for which episode to resume in a folder |
| T-009 | ID generator | id-gen | cli | active | P2 | low | github | — | Generate ids; choose type (uuid, nanoid, …) |
| T-010 | Base64 encode/decode | base64-tool | cli | active | P2 | low | github | — | Encode or decode Base64 (mode select) |
| T-011 | JWT decode | jwt-decode | cli | active | P2 | low | github | — | Decode JWT header and payload without verifying |
| T-012 | Unix timestamp | unix-timestamp | cli | active | P2 | low | github | — | Convert between unix time and human-readable dates |
| T-013 | File hasher | file-hash | cli | active | P2 | low | github | — | SHA-256 (and friends) of a file or string |
| T-014 | JSON format | json-format | cli | active | P2 | low | github | — | Pretty-print or minify JSON from stdin or a file |
| T-015 | File snippets | file-snippets | cli | active | P2 | low | github | — | List/copy snippets from a git-friendly snippets folder |
| T-016 | Emoji to clipboard | emoji-copy | cli | dropped | P3 | low | github | — | OS emoji picker covers this; not worth a leaf |
| T-019 | Global snippet expand | snippet-expand | ext/macos | idea | P5 | high | github | T-015 | Expand file snippets by keyword in any app |
| T-022 | URL encode/decode | url-encode | cli | active | P2 | low | github | — | Percent-encode or decode a string (mode select) |
| T-023 | HTML entities | html-entities | cli | active | P2 | low | github | — | Encode or decode HTML entities (mode select) |
| T-024 | Case transform | case-transform | cli | active | P2 | low | github | — | camel / snake / kebab / Pascal (target case select) |
| T-025 | Lorem ipsum | lorem | cli | dropped | P3 | low | github | — | Toy generator; not worth a leaf |
| T-026 | Password generator | password-gen | cli | active | P2 | low | github | — | Random password with length and charset |
| T-027 | Color convert | color-convert | cli | active | P2 | low | github | — | Convert hex ↔ rgb ↔ hsl (source/target select) |
| T-028 | QR encode | qr-encode | cli | active | P3 | low | github | — | Encode text as a QR PNG or terminal art |
| T-029 | Text diff | text-diff | cli | dropped | P3 | low | github | — | Alias of diff; not worth a leaf |
| T-030 | Line sort | line-sort | cli | active | P2 | low | github | — | Sort, unique, or reverse lines from stdin |
| T-031 | Slugify | slugify | cli | active | P2 | low | github | — | Turn a title into a kebab-case slug |
| T-032 | Nano ID generator | nanoid-gen | cli | dropped | P3 | low | github | T-009 | Merged into id-gen (T-009) |
| T-033 | Cron explain | cron-explain | cli | active | P3 | low | github | — | Explain a cron expression in plain English |
| T-034 | Data format convert | data-convert | cli | active | P2 | low | github | — | Convert among json, yaml, toml, csv, env (from/to) |
| T-035 | YAML ↔ JSON | yaml-json | cli | dropped | P2 | low | github | T-034 | Merged into data-convert (T-034) |
| T-036 | Phone format | phone-format | cli | dropped | P3 | low | github | — | Toy formatter; not worth a leaf |
| T-037 | Port tool | port-tool | cli | active | P1 | low | github | — | Who owns a port, or kill the process (mode select) |
| T-038 | Who on port | port-who | cli | dropped | P2 | low | github | T-037 | Merged into port-tool (T-037) |
| T-039 | IP show | ip-show | cli | dropped | P3 | low | github | — | Alias of ifconfig/curl; not worth a leaf |
| T-040 | Local IP | local-ip | cli | dropped | P3 | low | github | T-039 | Parent ip-show (T-039) dropped as alias-tier |
| T-041 | DNS lookup | dns-lookup | cli | dropped | P3 | low | github | — | Alias of dig/host; not worth a leaf |
| T-042 | HTTP status | http-status | cli | dropped | P3 | low | github | — | Alias of curl -I; not worth a leaf |
| T-043 | Clipboard CLI | pb | cli | active | P2 | low | github | — | Read or write the system clipboard from the CLI |
| T-044 | Open GitHub remote | gh-open | cli | dropped | P3 | low | github | — | Alias of gh browse; not worth a leaf |
| T-045 | Git root | git-root | cli | dropped | P3 | low | github | — | Alias of git rev-parse --show-toplevel; not worth a leaf |
| T-046 | Trash | trash | cli | active | P1 | low | github | — | Move files to Trash instead of rm |
| T-049 | Mic mute toggle | mic-mute | ext/macos | active | P4 | medium | github | — | Global microphone mute with indicator |
| T-050 | Focus toggle | focus-toggle | ext/macos | active | P4 | medium | github | — | Toggle macOS Focus / Do Not Disturb |
| T-051 | Desktop icons toggle | desktop-icons | ext/macos | dropped | P4 | low | github | — | defaults write one-liner; not worth a leaf |
| T-052 | Empty Trash | empty-trash | ext/macos | dropped | P4 | low | github | — | OS Trash UI covers this; not worth a leaf |
| T-053 | Eject volumes | eject-all | ext/macos | dropped | P4 | low | github | — | Alias of diskutil; not worth a leaf |
| T-054 | Image tool | image-tool | cli | active | P3 | medium | github | — | Resize, compress, or convert images (mode + formats) |
| T-055 | Image compress | image-compress | cli | dropped | P3 | medium | github | T-054 | Merged into image-tool (T-054) |
| T-056 | Image convert | image-convert | cli | dropped | P3 | low | github | T-054 | Merged into image-tool (T-054) |
| T-057 | Strip EXIF | strip-exif | cli | active | P2 | low | github | — | Remove EXIF/GPS metadata from images |
| T-058 | Image base64 | image-base64 | cli | dropped | P3 | low | github | — | Thin wrap of base64 + file read; not worth a leaf |
| T-059 | File size | file-size | cli | active | P2 | low | github | — | Human-readable size of a path |
| T-060 | Dir disk usage | dir-du | cli | active | P2 | low | github | — | Disk usage summary for a folder |
| T-061 | Big files | big-files | cli | active | P2 | low | github | — | Largest N files under a path |
| T-062 | Line endings | line-endings | cli | active | P2 | low | github | — | Convert CRLF ↔ LF for a file |
| T-063 | Strip BOM | strip-bom | cli | dropped | P3 | low | github | — | One-liner; not worth a leaf |
| T-064 | Word count | word-count | cli | dropped | P3 | low | github | — | Alias of wc; not worth a leaf |
| T-065 | Reading time | reading-time | cli | dropped | P3 | low | github | — | Trivial estimate; not worth a leaf |
| T-066 | CSV ↔ JSON | csv-json | cli | dropped | P2 | low | github | T-034 | Merged into data-convert (T-034) |
| T-067 | TOML ↔ JSON | toml-json | cli | dropped | P2 | low | github | T-034 | Merged into data-convert (T-034) |
| T-068 | XML format | xml-format | cli | active | P3 | low | github | — | Pretty-print XML |
| T-069 | JSON query | json-query | cli | active | P2 | medium | github | — | Tiny path query on JSON (jq-lite) |
| T-070 | Regex test | regex-test | cli | active | P2 | low | github | — | Test a regex against a string |
| T-071 | Shell escape | shell-escape | cli | active | P2 | low | github | — | Escape a string for safe shell use |
| T-072 | Git branch age | git-branch-age | cli | dropped | P3 | low | github | — | Thin git for-each-ref wrap; not worth a leaf |
| T-073 | Git large files | git-large-files | cli | active | P4 | medium | github | — | Warn about large blobs in git history |
| T-074 | Gitignore check | gitignore-check | cli | dropped | P3 | low | github | — | Alias of git check-ignore; not worth a leaf |
| T-075 | SSL expiry | ssl-expiry | cli | active | P2 | low | github | — | Days until TLS cert expires for a host |
| T-076 | Secret scan | secret-scan | cli | active | P2 | medium | github | — | Scan a file or dir for likely API keys |
| T-077 | User-agent parse | user-agent-parse | cli | dropped | P3 | low | github | — | Niche one-shot parse; not worth a leaf |
| T-078 | MIME of | mime-of | cli | dropped | P3 | low | github | — | Alias of file --mime-type; not worth a leaf |
| T-079 | Notify | notify | cli | active | P2 | low | github | — | Post a macOS notification from the CLI |
| T-080 | Say clipboard | say-clip | cli | dropped | P3 | low | github | — | Alias of say + clipboard; not worth a leaf |
| T-081 | Timezone convert | timezone-convert | cli | active | P2 | low | github | — | Convert a time across timezones |
| T-082 | Week number | week-number | cli | dropped | P3 | low | github | — | Alias of date; not worth a leaf |
| T-083 | Countdown | countdown | cli | dropped | P3 | low | github | — | Trivial date math; not worth a leaf |
| T-084 | Timer | timer | cli | dropped | P3 | low | github | — | Terminal sleep toy; not worth a leaf |
| T-085 | Unit convert | unit-convert | cli | dropped | P3 | low | github | — | Commodity converter; not worth a leaf |
| T-086 | Percent | percent | cli | dropped | P3 | low | github | — | Trivial arithmetic; not worth a leaf |
| T-087 | Random int | random-int | cli | dropped | P3 | low | github | — | Alias of shuf/$RANDOM; not worth a leaf |
| T-088 | Quarantine clear | quarantine-clear | ext/macos | active | P2 | low | github | — | Clear Gatekeeper quarantine on a file |
| T-089 | Open Terminal here | open-terminal-here | ext/macos | active | P3 | medium | github | — | Finder Quick Action: Terminal at folder |
| T-090 | Reveal in Finder | reveal-in-finder | cli | dropped | P3 | low | github | — | Alias of open -R; not worth a leaf |
| T-091 | AirDrop files | airdrop-folder | ext/macos | active | P4 | medium | github | — | Open AirDrop sharing for selected files |
| T-095 | Number base convert | number-base | cli | active | P2 | low | github | — | Convert among binary, octal, decimal, hex (from/to) |

Dropped / skipped on purpose: copy-as-Markdown extensions, ClearURLs, OneTab, generic skip-intro-by-seconds UIs, a second Claude cost dashboard, a single mega “utils” binary, Spotify/Notion/Slack bots, a full jq clone, one tool per conversion direction (e.g. separate decimal→binary and binary→hex), and alias-tier wraps of existing CLI/OS tools (gh browse, dig, curl -I, git rev-parse, open -R, wc, say, date, diskutil, etc.).

Menu-bar / hotkey / palette mini-tools are out of scope for this repo and are not tracked here.
