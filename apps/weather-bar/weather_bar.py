#!/usr/bin/env python3
"""CLI-first local weather one-liner via Open-Meteo (no API key)."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable

SLUG = "weather-bar"
DEFAULT_CONFIG_PATH = Path.home() / ".config" / "tools" / "weather-bar.yaml"
ENV_CONFIG = "TOOLS_WEATHER_BAR_CONFIG"

GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

UrlOpen = Callable[..., Any]

# WMO weather interpretation codes (Open-Meteo / WMO)
_WEATHER_LABELS: dict[int, str] = {
    0: "Clear sky",
    1: "Mainly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Fog",
    48: "Depositing rime fog",
    51: "Light drizzle",
    53: "Drizzle",
    55: "Dense drizzle",
    56: "Light freezing drizzle",
    57: "Freezing drizzle",
    61: "Rain",
    63: "Moderate rain",
    65: "Heavy rain",
    66: "Light freezing rain",
    67: "Freezing rain",
    71: "Snow",
    73: "Moderate snow",
    75: "Heavy snow",
    77: "Snow grains",
    80: "Rain showers",
    81: "Moderate rain showers",
    82: "Violent rain showers",
    85: "Snow showers",
    86: "Heavy snow showers",
    95: "Thunderstorm",
    96: "Thunderstorm with hail",
    99: "Thunderstorm with heavy hail",
}


def weather_code_label(code: int) -> str:
    """Map a WMO weather code to a short English label."""
    return _WEATHER_LABELS.get(int(code), "Unknown")


def load_config(path: Path) -> dict[str, str]:
    """Load a flat key: value YAML subset (stdlib only; no PyYAML)."""
    if not path.is_file():
        return {}
    data: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or ":" not in line:
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip("\"'")
    return data


def config_path_from_env() -> Path:
    override = os.environ.get(ENV_CONFIG)
    if override:
        return Path(override).expanduser()
    return DEFAULT_CONFIG_PATH


def http_get_json(
    url: str,
    *,
    urlopen: UrlOpen | None = None,
    timeout: float = 15.0,
) -> dict[str, Any]:
    """GET URL and parse JSON. Inject urlopen for tests."""
    opener = urlopen if urlopen is not None else urllib.request.urlopen
    try:
        with opener(url, timeout=timeout) as resp:
            body = resp.read()
    except urllib.error.HTTPError as exc:
        raise urllib.error.URLError(f"HTTP {exc.code} for {url}") from exc
    except urllib.error.URLError:
        raise
    except OSError as exc:
        raise urllib.error.URLError(str(exc)) from exc
    try:
        data = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise urllib.error.URLError(f"invalid JSON from {url}") from exc
    if not isinstance(data, dict):
        raise urllib.error.URLError(f"unexpected JSON shape from {url}")
    return data


def geocode(
    name: str,
    *,
    urlopen: UrlOpen | None = None,
) -> tuple[float, float, str]:
    """Resolve a place name via Open-Meteo geocoding API."""
    query = urllib.parse.urlencode({"name": name, "count": 1})
    url = f"{GEOCODE_URL}?{query}"
    data = http_get_json(url, urlopen=urlopen)
    results = data.get("results") or []
    if not results:
        raise ValueError(f"location not found: {name!r}")
    first = results[0]
    lat = float(first["latitude"])
    lon = float(first["longitude"])
    label = str(first.get("name") or name)
    return lat, lon, label


def fetch_current(
    lat: float,
    lon: float,
    *,
    urlopen: UrlOpen | None = None,
) -> dict[str, Any]:
    """Fetch current conditions from Open-Meteo forecast API."""
    query = urllib.parse.urlencode(
        {
            "latitude": lat,
            "longitude": lon,
            "current": "temperature_2m,weather_code,wind_speed_10m",
        }
    )
    url = f"{FORECAST_URL}?{query}"
    data = http_get_json(url, urlopen=urlopen)
    current = data.get("current")
    if not isinstance(current, dict):
        raise urllib.error.URLError("forecast response missing current block")
    try:
        temp_c = float(current["temperature_2m"])
        weathercode = int(current["weather_code"])
        wind_kmh = float(current.get("wind_speed_10m", 0.0))
    except (KeyError, TypeError, ValueError) as exc:
        raise urllib.error.URLError("forecast response missing fields") from exc
    return {
        "temp_c": temp_c,
        "weathercode": weathercode,
        "wind_kmh": wind_kmh,
        "description": weather_code_label(weathercode),
    }


def format_status(*, temp_c: float, weathercode: int, location: str) -> str:
    """Compact one-liner for status bar / launcher."""
    temp = int(round(temp_c))
    label = weather_code_label(weathercode)
    return f"{temp}°C {label} · {location}"


def resolve_location(
    *,
    location: str | None,
    lat: float | None,
    lon: float | None,
    config: dict[str, str],
    urlopen: UrlOpen | None = None,
) -> tuple[float, float, str]:
    """
    Resolve coordinates and display name.

    Priority: CLI lat/lon > CLI location > config lat/lon > config location.
    """
    if lat is not None and lon is not None:
        name = (location or config.get("location") or f"{lat},{lon}").strip()
        return float(lat), float(lon), name

    if location and location.strip():
        return geocode(location.strip(), urlopen=urlopen)

    cfg_lat = config.get("lat")
    cfg_lon = config.get("lon")
    if cfg_lat is not None and cfg_lon is not None and str(cfg_lat).strip() and str(cfg_lon).strip():
        name = (config.get("location") or f"{cfg_lat},{cfg_lon}").strip()
        return float(cfg_lat), float(cfg_lon), name

    cfg_loc = (config.get("location") or "").strip()
    if cfg_loc:
        return geocode(cfg_loc, urlopen=urlopen)

    raise ValueError(
        "missing location (pass --location, --lat/--lon, or set config location/lat/lon)"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Print current weather as a compact one-liner (Open-Meteo)."
    )
    parser.add_argument(
        "--location",
        default=None,
        help="place name to geocode (overrides config location when set)",
    )
    parser.add_argument("--lat", type=float, default=None, help="latitude (skip geocode)")
    parser.add_argument("--lon", type=float, default=None, help="longitude (skip geocode)")
    parser.add_argument(
        "--json",
        action="store_true",
        help="print JSON: temp_c, weathercode, description, location, wind_kmh",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=None,
        help=f"YAML config path (default: {DEFAULT_CONFIG_PATH} or ${ENV_CONFIG})",
    )
    args = parser.parse_args(argv)

    if (args.lat is None) ^ (args.lon is None):
        print(f"{SLUG}: --lat and --lon must be used together", file=sys.stderr)
        return 2

    cfg_path = args.config.expanduser() if args.config else config_path_from_env()
    try:
        config = load_config(cfg_path)
        lat, lon, name = resolve_location(
            location=args.location,
            lat=args.lat,
            lon=args.lon,
            config=config,
        )
        current = fetch_current(lat, lon)
    except ValueError as exc:
        print(f"{SLUG}: {exc}", file=sys.stderr)
        return 2
    except urllib.error.URLError as exc:
        reason = getattr(exc, "reason", None) or str(exc)
        print(f"{SLUG}: {reason}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"{SLUG}: {exc}", file=sys.stderr)
        return 1

    if args.json:
        payload = {
            "temp_c": current["temp_c"],
            "weathercode": current["weathercode"],
            "description": current["description"],
            "location": name,
            "wind_kmh": current["wind_kmh"],
            "lat": lat,
            "lon": lon,
        }
        print(json.dumps(payload))
    else:
        print(
            format_status(
                temp_c=current["temp_c"],
                weathercode=current["weathercode"],
                location=name,
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
