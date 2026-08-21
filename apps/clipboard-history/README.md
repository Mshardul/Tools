# Clipboard history

**Backlog:** T-018 · `clipboard-history`

Local searchable clipboard history with pins. Text-first CLI for the Tools nursery (and a future launcher).

**Status:** active (CLI MVP)

## Use

```bash
# from repo root, with shared .venv
.venv/bin/python apps/clipboard-history/clipboard_history.py --help

# poll macOS pasteboard (pbpaste); Ctrl-C to stop
.venv/bin/python apps/clipboard-history/clipboard_history.py watch
.venv/bin/python apps/clipboard-history/clipboard_history.py watch --interval 0.5

# browse / search
.venv/bin/python apps/clipboard-history/clipboard_history.py list --limit 20
.venv/bin/python apps/clipboard-history/clipboard_history.py --json list
.venv/bin/python apps/clipboard-history/clipboard_history.py search "invoice"
.venv/bin/python apps/clipboard-history/clipboard_history.py get 42
.venv/bin/python apps/clipboard-history/clipboard_history.py copy 42   # pbcopy

# pins
.venv/bin/python apps/clipboard-history/clipboard_history.py pin 42
.venv/bin/python apps/clipboard-history/clipboard_history.py pins
.venv/bin/python apps/clipboard-history/clipboard_history.py unpin 42
```

Default store: `~/.local/share/tools/clipboard-history/history.db`  
Override with `--db PATH`. Consecutive identical clips are deduped; entries over ~200KB are skipped.

Importable API: `HistoryStore`, `watch_clipboard`, `default_db_path`, `main`.

## Platform

- **Store / list / search / pin** — pure Python + sqlite; works anywhere.
- **`watch` / `copy`** — default to `pbpaste` / `pbcopy` (Darwin). Tests inject readers/writers.

## Not for

- Full Paste.app / Alfred clipboard managers
- Image / OCR history (**yet** — see T-018-5)
- GUI (CLI only; nursery + future launcher)

## Tests

```bash
cd apps/clipboard-history && ../../.venv/bin/python -m unittest tests.test_clipboard_history -v
```
