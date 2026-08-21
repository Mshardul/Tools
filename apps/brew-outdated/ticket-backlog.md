# Ticket backlog — brew-outdated

**Root id:** T-092  
**Publish:** github  
**License:** MIT (repo root)

CLI report of outdated Homebrew packages (count + list; JSON/filters). Menu-bar later.

## Tickets

| id | title | status | notes |
|---|---|---|---|
| T-092-1 | CLI: parse brew outdated JSON + human/json output | done | `brew_outdated.py` |
| T-092-2 | Flags: --formulae-only / --casks-only; brew-missing errors | done | argparse + stderr prefix |
| T-092-3 | Unit tests (fixture JSON; no live brew) | done | `tests/test_brew_outdated.py` |
| T-092-4 | Menu-bar host UI | idea | call CLI/`--json` from a future macOS host |
