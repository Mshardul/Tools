# Ticket backlog — clipboard-history

**Root id:** T-018  
**Publish:** github  
**License:** MIT (repo root)

Local searchable clipboard history with pins. Image OCR is deferred.

## Tickets

| id | title | status | notes |
|---|---|---|---|
| T-018-1 | SQLite store: add / list / get / size skip / consecutive dedupe | done | `HistoryStore` + temp-dir tests |
| T-018-2 | Search (substring) + pin / unpin / pins | done | case-insensitive LIKE |
| T-018-3 | CLI: watch / list / search / get / copy / pins + `--json` | done | `argparse` subcommands; stderr `clipboard-history:` |
| T-018-4 | Unit tests (injectable pasteboard; no live pbpaste) | done | `tests/test_clipboard_history.py` |
| T-018-5 | Image clipboard + OCR into searchable text | todo | stretch; not in MVP |
