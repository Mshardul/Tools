# Battery ETA

**Backlog:** T-048 · `battery-eta`

CLI that reads macOS `pmset -g batt` and prints battery percent, charging state, and remaining / until-full ETA when available. Nursery shape is **CLI-first**; a menu-bar host can call this later via subprocess/`--json`.

Not for: Windows/Linux power APIs, detailed power-history charts, or forcing sleep/wake.

## Usage

```bash
python3 battery_eta.py
python3 battery_eta.py --json
python3 battery_eta.py --raw
```

- Default: one human line, e.g. `45% discharging, 3:45 remaining (Battery Power)`
- `--json`: parsed fields (`source`, `percent`, `status`, `eta`, `present`)
- `--raw`: verbatim `pmset -g batt` stdout

Errors are prefixed with `battery-eta:` on stderr.

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_battery_eta -v
```

Parser and formatting are covered with fixture strings; `subprocess` is mocked (no live `pmset` in unit tests).

## Future

Menu-bar / launcher UI that polls this CLI — out of scope for this leaf.
