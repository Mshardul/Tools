# Ticket backlog — claude-usage

**Root id:** T-001  
**Publish:** github (this repo)  
**License:** MIT (repo root)

Local dashboard for Claude Code token usage from `~/.claude` files. No server, no Anthropic API. Not a billing console.

## Tickets

| id | title | status | notes |
|---|---|---|---|
| T-001-1 | Keep relative fetches for `usage.db` / `projects/` | done | Serve from this directory |
| T-001-2 | Tab layout from 2026-05-25 spec | idea | See `docs/superpowers/specs/2026-05-25-claude-usage-dashboard-design.md` |

## Open questions

- Whether to read `usage.db` only vs also scanning JSONL on every load.
