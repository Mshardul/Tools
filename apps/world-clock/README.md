# World clock

**Backlog:** T-047 · `world-clock`

CLI that prints the current time in a few IANA time zones (stdlib `zoneinfo`). Nursery shape is **CLI-first**; a menu-bar host can call this later via subprocess/`--json`.

Not for: calendar scheduling, world-map UIs, or NTP sync.

## Usage

```bash
python3 world_clock.py
python3 world_clock.py --zone UTC --zone Asia/Tokyo
python3 world_clock.py --format '%Y-%m-%d %H:%M %Z'
python3 world_clock.py --json
python3 world_clock.py --config ~/.config/tools/world-clock.yaml
```

Defaults (no `--zone` / empty config): `UTC`, `America/New_York`, `Europe/London`, `Asia/Kolkata`.

Config path: `~/.config/tools/world-clock.yaml`, or `TOOLS_WORLD_CLOCK_CONFIG`, or `--config`.

Example config:

```yaml
zones: [UTC, America/Los_Angeles, Asia/Tokyo]
labels:
  America/Los_Angeles: LA
  Asia/Tokyo: Tokyo
```

Invalid zone names exit non-zero with `world-clock:` on stderr.

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_world_clock -v
```

## Future

Menu-bar / launcher UI that refreshes these zones — out of scope for this leaf.
