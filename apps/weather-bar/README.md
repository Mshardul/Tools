# Weather bar

**Backlog:** T-094 · `weather-bar`

CLI that prints current local weather as a compact one-liner for a status bar / launcher. Uses the free [Open-Meteo](https://open-meteo.com/) geocoding + forecast APIs (no API key). Nursery shape is **CLI-first**; a menu-bar host can call this later via subprocess/`--json`.

Not for: multi-day forecasts, maps, or forcing a native menu-bar UI in this leaf.

## Usage

```bash
python3 weather_bar.py --location Mumbai
python3 weather_bar.py --lat 19.07 --lon 72.88 --location Mumbai
python3 weather_bar.py --json --location Berlin
python3 weather_bar.py --config ~/my-weather.yaml
```

Default output example: `12°C Partly cloudy · Mumbai`

- `--location`: city / place name (geocoded via Open-Meteo)
- `--lat` / `--lon`: skip geocoding (must be used together)
- `--json`: `temp_c`, `weathercode`, `description`, `location`, `wind_kmh`, `lat`, `lon`
- `--config`: YAML path (default `~/.config/tools/weather-bar.yaml` or `$TOOLS_WEATHER_BAR_CONFIG`)

### Config

```yaml
location: Mumbai
# or:
# lat: 19.07
# lon: 72.88
```

Errors are prefixed with `weather-bar:` on stderr.

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_weather_bar -v
```

HTTP is injected / mocked; unit tests do not hit the network.

## Future

Menu-bar / launcher UI that polls this CLI — out of scope for this leaf (see ticket backlog).
