# Ticket backlog — airdrop-folder

**Root id:** T-091  
**Publish:** github  
**License:** MIT (repo root)

Open AirDrop sharing for selected files/folders (Finder Quick Action helper).

## Tickets

| id | title | status | notes |
|---|---|---|---|
| T-091-1 | Resolve/validate one or more paths | done | `resolve_paths`, expanduser, missing → error |
| T-091-2 | Build Finder select script + open AirDrop argv | done | `applescript_quote`, `build_finder_select_script`, `build_open_airdrop_argv` |
| T-091-3 | Share via injectable runner | done | `share_via_airdrop` (osascript then `open` AirDrop.app) |
| T-091-4 | CLI (`argparse`, Darwin check, stderr slug, `--json`) | done | `airdrop_folder.py` |
| T-091-5 | Unit tests (mock runner / no GUI) | done | `tests/test_airdrop_folder.py` |
| T-091-6 | README + Quick Action notes + this backlog | done | Automator optional setup |
