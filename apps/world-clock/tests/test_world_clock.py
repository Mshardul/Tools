"""Unit tests for world_clock."""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

from world_clock import (
    DEFAULT_ZONES,
    format_clock,
    load_config,
    main,
    resolve_zones,
)


class ResolveZonesTests(unittest.TestCase):
    def test_cli_zones_win(self):
        self.assertEqual(
            resolve_zones(["UTC", "Asia/Tokyo"], {"zones": ["Europe/London"]}),
            ["UTC", "Asia/Tokyo"],
        )

    def test_config_zones_when_no_cli(self):
        self.assertEqual(
            resolve_zones([], {"zones": ["UTC", "America/Los_Angeles"]}),
            ["UTC", "America/Los_Angeles"],
        )

    def test_defaults_when_empty(self):
        self.assertEqual(resolve_zones([], {}), list(DEFAULT_ZONES))
        self.assertEqual(
            DEFAULT_ZONES,
            ["UTC", "America/New_York", "Europe/London", "Asia/Kolkata"],
        )

    def test_cli_none_uses_config(self):
        self.assertEqual(
            resolve_zones(None, {"zones": ["UTC"]}),
            ["UTC"],
        )


class FormatClockTests(unittest.TestCase):
    def test_iso_local_times(self):
        now = datetime(2026, 8, 22, 12, 0, 0, tzinfo=timezone.utc)
        rows = format_clock(now, ["UTC", "America/New_York", "Asia/Kolkata"])
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0]["zone"], "UTC")
        self.assertEqual(rows[0]["time"], "2026-08-22T12:00:00+00:00")
        self.assertEqual(rows[1]["zone"], "America/New_York")
        # EDT in August: UTC-4
        self.assertEqual(rows[1]["time"], "2026-08-22T08:00:00-04:00")
        self.assertEqual(rows[2]["zone"], "Asia/Kolkata")
        self.assertEqual(rows[2]["time"], "2026-08-22T17:30:00+05:30")

    def test_custom_strftime(self):
        now = datetime(2026, 1, 15, 18, 30, 0, tzinfo=timezone.utc)
        rows = format_clock(now, ["UTC"], fmt="%H:%M %Z")
        self.assertEqual(rows[0]["time"], "18:30 UTC")

    def test_labels_in_output(self):
        now = datetime(2026, 1, 1, 0, 0, 0, tzinfo=timezone.utc)
        rows = format_clock(
            now,
            ["America/Los_Angeles"],
            labels={"America/Los_Angeles": "LA"},
        )
        self.assertEqual(rows[0]["label"], "LA")
        self.assertEqual(rows[0]["zone"], "America/Los_Angeles")

    def test_invalid_zone_raises(self):
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        with self.assertRaises(ValueError) as ctx:
            format_clock(now, ["Not/A_Zone"])
        self.assertIn("Not/A_Zone", str(ctx.exception))


class LoadConfigTests(unittest.TestCase):
    def test_missing_file(self):
        self.assertEqual(load_config(Path("/nonexistent/world-clock.yaml")), {})

    def test_flow_list_and_labels(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "world-clock.yaml"
            path.write_text(
                "zones: [UTC, America/Los_Angeles, Asia/Tokyo]\n"
                "labels:\n"
                "  America/Los_Angeles: LA\n"
                "  Asia/Tokyo: Tokyo\n",
                encoding="utf-8",
            )
            cfg = load_config(path)
            self.assertEqual(
                cfg["zones"],
                ["UTC", "America/Los_Angeles", "Asia/Tokyo"],
            )
            self.assertEqual(cfg["labels"]["America/Los_Angeles"], "LA")
            self.assertEqual(cfg["labels"]["Asia/Tokyo"], "Tokyo")

    def test_block_list(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "world-clock.yaml"
            path.write_text(
                "zones:\n"
                "  - UTC\n"
                "  - Europe/London\n",
                encoding="utf-8",
            )
            cfg = load_config(path)
            self.assertEqual(cfg["zones"], ["UTC", "Europe/London"])


class MainCliTests(unittest.TestCase):
    def test_json_output(self):
        now = datetime(2026, 8, 22, 12, 0, 0, tzinfo=timezone.utc)
        with mock.patch("world_clock._now_utc", return_value=now):
            with mock.patch("sys.stdout", new_callable=__import__("io").StringIO) as out:
                code = main(["--zone", "UTC", "--json"])
                self.assertEqual(code, 0)
                payload = json.loads(out.getvalue())
                self.assertEqual(payload[0]["zone"], "UTC")
                self.assertEqual(payload[0]["time"], "2026-08-22T12:00:00+00:00")

    def test_invalid_zone_stderr_prefix(self):
        with mock.patch("sys.stderr", new_callable=__import__("io").StringIO) as err:
            code = main(["--zone", "Nope/Nowhere"])
            self.assertNotEqual(code, 0)
            self.assertTrue(err.getvalue().startswith("world-clock:"))

    def test_config_env(self):
        now = datetime(2026, 1, 1, 0, 0, 0, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "cfg.yaml"
            path.write_text("zones: [UTC]\n", encoding="utf-8")
            env = {**os.environ, "TOOLS_WORLD_CLOCK_CONFIG": str(path)}
            with mock.patch.dict(os.environ, env, clear=True):
                with mock.patch("world_clock._now_utc", return_value=now):
                    with mock.patch(
                        "sys.stdout", new_callable=__import__("io").StringIO
                    ) as out:
                        code = main(["--json"])
                        self.assertEqual(code, 0)
                        payload = json.loads(out.getvalue())
                        self.assertEqual([r["zone"] for r in payload], ["UTC"])


if __name__ == "__main__":
    unittest.main()
