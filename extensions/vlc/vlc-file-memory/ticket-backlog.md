# Ticket backlog — vlc-file-memory

**Root id:** T-003  
**Publish:** github  
**License:** MIT (repo root)

Remember audio, subtitle, and delay per file in VLC.

## Tickets

| id | title | status | notes |
|---|---|---|---|
| T-003-1 | Path normalize + `hash_path` | done | `vlc_file_memory.py` |
| T-003-2 | JSON store read/write + get/set entry | done | keyed by normalized path |
| T-003-3 | CLI: `install` / `uninstall` / `hash` | done | stderr prefix `vlc-file-memory:` |
| T-003-4 | Lua extension `file_memory.lua` | done | restore on input; save on meta/deactivate |
| T-003-5 | Unit tests (path, store, install paths) | done | `tests/test_vlc_file_memory.py` |
| T-003-6 | README: install / activate / store / not-for | done | macOS paths documented |
