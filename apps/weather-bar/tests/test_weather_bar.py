"""Unit tests for weather_bar (mocked HTTP; no live network)."""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock
from urllib.error import HTTPError, URLError

from weather_bar import (
    DEFAULT_CONFIG_PATH,
    ENV_CONFIG,
    fetch_current,
    format_status,
    geocode,
    http_get_json,
    load_config,
    main,
    resolve_location,
    weather_code_label,
)


class FakeResponse:
    def __init__(self, body: bytes, status: int = 200):
        self._body = body
        self.status = status

    def read(self) -> bytes:
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def make_urlopen(mapping: dict[str, bytes | Exception]):
    """Return a urlopen that matches URL prefixes to body bytes or raises."""

    def urlopen(url, timeout=None):  # noqa: ARG001
        url_s = str(url)
        for prefix, value in mapping.items():
            if url_s.startswith(prefix) or prefix in url_s:
                if isinstance(value, Exception):
                    raise value
                return FakeResponse(value)
        raise AssertionError(f"unexpected URL: {url_s}")

    return urlopen


GEOCODE_MUMBAI = json.dumps(
    {
        "results": [
            {
                "name": "Mumbai",
                "latitude": 19.07283,
                "longitude": 72.88261,
                "country": "India",
                "admin1": "Maharashtra",
            }
        ]
    }
).encode()

FORECAST_PARTLY = json.dumps(
    {
        "current": {
            "temperature_2m": 12.0,
            "weather_code": 2,
            "wind_speed_10m": 8.5,
        }
    }
).encode()


class WeatherCodeLabelTests(unittest.TestCase):
    def test_known_codes(self):
        self.assertEqual(weather_code_label(0), "Clear sky")
        self.assertEqual(weather_code_label(2), "Partly cloudy")
        self.assertEqual(weather_code_label(3), "Overcast")
        self.assertEqual(weather_code_label(61), "Rain")
        self.assertEqual(weather_code_label(95), "Thunderstorm")

    def test_unknown_code(self):
        self.assertEqual(weather_code_label(999), "Unknown")


class FormatStatusTests(unittest.TestCase):
    def test_compact_one_liner(self):
        line = format_status(
            temp_c=12.0,
            weathercode=2,
            location="Mumbai",
        )
        self.assertEqual(line, "12°C Partly cloudy · Mumbai")

    def test_rounds_temp(self):
        line = format_status(temp_c=12.6, weathercode=0, location="Berlin")
        self.assertEqual(line, "13°C Clear sky · Berlin")


class LoadConfigTests(unittest.TestCase):
    def test_missing_file(self):
        self.assertEqual(load_config(Path("/nonexistent/weather-bar.yaml")), {})

    def test_location_and_coords(self):
        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as fh:
            fh.write("location: Mumbai\nlat: 19.07\nlon: 72.88\n")
            path = Path(fh.name)
        try:
            cfg = load_config(path)
            self.assertEqual(cfg["location"], "Mumbai")
            self.assertEqual(cfg["lat"], "19.07")
            self.assertEqual(cfg["lon"], "72.88")
        finally:
            path.unlink(missing_ok=True)


class HttpGetJsonTests(unittest.TestCase):
    def test_parses_json(self):
        urlopen = make_urlopen({"https://example.test/": b'{"ok": true}'})
        data = http_get_json("https://example.test/x", urlopen=urlopen)
        self.assertEqual(data, {"ok": True})

    def test_http_error(self):
        err = HTTPError("https://x", 500, "err", hdrs=None, fp=None)
        urlopen = make_urlopen({"https://x": err})
        with self.assertRaises(URLError):
            http_get_json("https://x", urlopen=urlopen)


class GeocodeTests(unittest.TestCase):
    def test_geocode_returns_coords_and_name(self):
        urlopen = make_urlopen({"geocoding-api.open-meteo.com": GEOCODE_MUMBAI})
        lat, lon, name = geocode("Mumbai", urlopen=urlopen)
        self.assertAlmostEqual(lat, 19.07283)
        self.assertAlmostEqual(lon, 72.88261)
        self.assertEqual(name, "Mumbai")

    def test_geocode_not_found(self):
        body = json.dumps({"results": []}).encode()
        urlopen = make_urlopen({"geocoding-api.open-meteo.com": body})
        with self.assertRaises(ValueError) as ctx:
            geocode("Nowhereville", urlopen=urlopen)
        self.assertIn("location", str(ctx.exception).lower())


class FetchCurrentTests(unittest.TestCase):
    def test_fetch_current_fields(self):
        urlopen = make_urlopen({"api.open-meteo.com": FORECAST_PARTLY})
        data = fetch_current(19.07, 72.88, urlopen=urlopen)
        self.assertEqual(data["temp_c"], 12.0)
        self.assertEqual(data["weathercode"], 2)
        self.assertEqual(data["wind_kmh"], 8.5)


class ResolveLocationTests(unittest.TestCase):
    def test_cli_lat_lon(self):
        lat, lon, name = resolve_location(
            location=None,
            lat=19.0,
            lon=72.0,
            config={},
            urlopen=make_urlopen({}),
        )
        self.assertEqual((lat, lon, name), (19.0, 72.0, "19.0,72.0"))

    def test_cli_location_geocodes(self):
        urlopen = make_urlopen({"geocoding-api.open-meteo.com": GEOCODE_MUMBAI})
        lat, lon, name = resolve_location(
            location="Mumbai",
            lat=None,
            lon=None,
            config={},
            urlopen=urlopen,
        )
        self.assertEqual(name, "Mumbai")
        self.assertAlmostEqual(lat, 19.07283)

    def test_config_lat_lon(self):
        lat, lon, name = resolve_location(
            location=None,
            lat=None,
            lon=None,
            config={"lat": "1.5", "lon": "2.5", "location": "IgnoredWhenCoords"},
            urlopen=make_urlopen({}),
        )
        self.assertEqual((lat, lon), (1.5, 2.5))
        self.assertEqual(name, "IgnoredWhenCoords")

    def test_missing_raises(self):
        with self.assertRaises(ValueError) as ctx:
            resolve_location(
                location=None,
                lat=None,
                lon=None,
                config={},
                urlopen=make_urlopen({}),
            )
        self.assertIn("location", str(ctx.exception).lower())


class MainTests(unittest.TestCase):
    def test_main_human_with_lat_lon(self):
        urlopen = make_urlopen({"api.open-meteo.com": FORECAST_PARTLY})
        with mock.patch("weather_bar.urllib.request.urlopen", urlopen):
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                code = main(["--lat", "19.07", "--lon", "72.88", "--location", "Mumbai"])
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue().strip(), "12°C Partly cloudy · Mumbai")

    def test_main_json(self):
        urlopen = make_urlopen({"api.open-meteo.com": FORECAST_PARTLY})
        with mock.patch("weather_bar.urllib.request.urlopen", urlopen):
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                code = main(
                    ["--json", "--lat", "19.07", "--lon", "72.88", "--location", "Mumbai"]
                )
        self.assertEqual(code, 0)
        payload = json.loads(out.getvalue())
        self.assertEqual(payload["temp_c"], 12.0)
        self.assertEqual(payload["weathercode"], 2)
        self.assertEqual(payload["description"], "Partly cloudy")
        self.assertEqual(payload["location"], "Mumbai")
        self.assertEqual(payload["wind_kmh"], 8.5)

    def test_main_missing_location(self):
        with mock.patch.dict("os.environ", {ENV_CONFIG: "/nonexistent/no-config.yaml"}):
            with mock.patch("sys.stderr", new_callable=io.StringIO) as err:
                code = main([])
        self.assertNotEqual(code, 0)
        self.assertTrue(err.getvalue().startswith("weather-bar:"))

    def test_main_http_failure(self):
        def boom(url, timeout=None):  # noqa: ARG001
            raise URLError("network down")

        with mock.patch("weather_bar.urllib.request.urlopen", boom):
            with mock.patch("sys.stderr", new_callable=io.StringIO) as err:
                code = main(["--lat", "1", "--lon", "2"])
        self.assertNotEqual(code, 0)
        self.assertTrue(err.getvalue().startswith("weather-bar:"))

    def test_main_config_path(self):
        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as fh:
            fh.write("location: Mumbai\n")
            cfg = Path(fh.name)
        try:
            calls: list[str] = []

            def urlopen(url, timeout=None):  # noqa: ARG001
                url_s = str(url)
                calls.append(url_s)
                if "geocoding-api" in url_s:
                    return FakeResponse(GEOCODE_MUMBAI)
                if "api.open-meteo.com" in url_s:
                    return FakeResponse(FORECAST_PARTLY)
                raise AssertionError(url_s)

            with mock.patch("weather_bar.urllib.request.urlopen", urlopen):
                with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                    code = main(["--config", str(cfg)])
            self.assertEqual(code, 0)
            self.assertIn("Mumbai", out.getvalue())
            self.assertTrue(any("geocoding-api" in c for c in calls))
        finally:
            cfg.unlink(missing_ok=True)

    def test_default_config_constant(self):
        self.assertEqual(
            DEFAULT_CONFIG_PATH,
            Path.home() / ".config" / "tools" / "weather-bar.yaml",
        )


if __name__ == "__main__":
    unittest.main()
