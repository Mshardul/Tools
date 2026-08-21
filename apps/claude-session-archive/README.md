# Claude session archive

**Backlog:** T-007 · `claude-session-archive`

Search and export local Claude Code JSONL sessions under `~/.claude/projects/**/*.jsonl` (same data family as `apps/claude-usage`).

Not for: Anthropic Console / cloud chat history, usage billing dashboards, or editing live Claude Code state. Read-only archive helpers only.

## Usage

```bash
cd apps/claude-session-archive

# List sessions (path, mtime, size, summary/title when parseable)
python3 claude_session_archive.py list
python3 claude_session_archive.py --json list

# Case-insensitive substring search across session JSONL text
python3 claude_session_archive.py search "flaky test"
python3 claude_session_archive.py --json search "UNIQUE_TOKEN"

# Export a session (jsonl copy, or markdown when -o ends in .md)
python3 claude_session_archive.py export /path/to/session.jsonl -o ~/Desktop/session.jsonl
python3 claude_session_archive.py export /path/to/session.jsonl -o ~/Desktop/session.md --format markdown

# Override projects root (tests / alternate trees)
python3 claude_session_archive.py --root /tmp/fake-projects list
```

Default root: `~/.claude/projects`. Errors go to stderr prefixed with `claude-session-archive:`.

### Summary extraction

Prefer `type: ai-title` / `aiTitle` when present; otherwise the first user message text (string or text parts). Truncated for list display.

### `--json`

Structured stdout for a future macOS launcher:

- `list` → array of `{path, mtime, size, summary}`
- `search` → array of `{path, snippet}`
- `export` → `{source, output, format}`

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_claude_session_archive -v
```

## Files

```
apps/claude-session-archive/
├── claude_session_archive.py
├── tests/test_claude_session_archive.py
├── ticket-backlog.md
└── README.md
```
