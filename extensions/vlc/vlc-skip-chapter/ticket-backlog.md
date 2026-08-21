# Ticket backlog — vlc-skip-chapter

**Root id:** T-005  
**Publish:** github  
**License:** MIT (repo root)

Auto-skip MKV chapters named Intro or Credits (standalone; no T-003 dependency).

## Tickets

| id | title | status | notes |
|---|---|---|---|
| T-005-1 | Pure `should_skip_chapter` + defaults | done | `vlc_skip_chapter.py` |
| T-005-2 | CLI: `check` / `install` (+ `--json`, `--dry-run`) | done | stderr prefix `vlc-skip-chapter:` |
| T-005-3 | Lua extension `skip_chapter.lua` | done | VLC extensions dir install |
| T-005-4 | Unit tests (match + install path mock) | done | `tests/test_vlc_skip_chapter.py` |
| T-005-5 | README: install / activate / not-for | done | macOS paths documented |
