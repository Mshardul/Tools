# Pomodoro

**Backlog:** T-093 · `pomodoro`

CLI-first 25/5 focus timer. Writes a state file so `status` can report remaining time. Completes with a macOS notification via `osascript` (same escape pattern as `cli/notify`).

A menu-bar UI is a future enhancement; this leaf ships the timer logic and CLI first.

Not for: calendar scheduling or multi-project task tracking.

## Usage

```bash
python3 pomodoro.py work                  # 25 min focus
python3 pomodoro.py break                 # 5 min break
python3 pomodoro.py work --work-min 50
python3 pomodoro.py break --break-min 10
python3 pomodoro.py status
python3 pomodoro.py status --json
python3 pomodoro.py reset
python3 pomodoro.py work --seconds 3 --no-notify   # smoke / short run
```

### Options

| Flag | Meaning |
|---|---|
| `--work-min N` | Work length in minutes (default 25) |
| `--break-min N` | Break length in minutes (default 5) |
| `--seconds N` | Override duration in seconds (smoke tests) |
| `--no-notify` | Skip notification on complete |
| `--json` | JSON for `status` |
| `--state-file PATH` | Override state path |

State file default: `~/.config/tools/pomodoro-state.json`

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_pomodoro -v
```
