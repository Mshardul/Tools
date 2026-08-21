# Ticket backlog — focus-toggle

**Root id:** T-050  
**Publish:** github  
**License:** MIT (repo root)

Toggle macOS Focus / Do Not Disturb via named Shortcuts.

## Tickets

| id | title | status | notes |
|---|---|---|---|
| T-050-1 | Config load + resolve shortcut names | done | `load_config`, `resolve_shortcut`, defaults |
| T-050-2 | Run `shortcuts run` for on/off/toggle | done | `build_shortcuts_argv`, `run_shortcut` |
| T-050-3 | `status` + `--json` (availability + names) | done | honest status, no fake Focus detection |
| T-050-4 | CLI (`argparse`, macOS check, stderr slug) | done | `focus_toggle.py` |
| T-050-5 | Unit tests (mock subprocess) | done | `tests/test_focus_toggle.py` |
| T-050-6 | README + this backlog | done | usage, install, Not for |
