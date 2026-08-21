"""Unit tests for battery_eta (fixtures + mocked subprocess; no live pmset)."""

from __future__ import annotations

import io
import json
import unittest
from unittest import mock

from battery_eta import format_status, main, parse_pmset_batt, fetch_pmset_batt

PMSET_AC_CHARGED = """\
Now drawing from 'AC Power'
 -InternalBattery-0 (id=12345678)\t100%; charged; 0:00 remaining present: true
"""

PMSET_DISCHARGING = """\
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=12345678)\t45%; discharging; 3:45 remaining present: true
"""

PMSET_CHARGING = """\
Now drawing from 'AC Power'
 -InternalBattery-0 (id=87654321)\t80%; charging; 1:23 remaining present: true
"""

PMSET_FINISHING = """\
Now drawing from 'AC Power'
 -InternalBattery-0 (id=111)\t95%; finishing charge; present: true
"""

PMSET_NO_ESTIMATE = """\
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=222)\t12%; discharging; (no estimate) present: true
"""

PMSET_AC_ONLY = """\
Now drawing from 'AC Power'
"""


class ParsePmsetBattTests(unittest.TestCase):
    def test_ac_charged(self):
        p = parse_pmset_batt(PMSET_AC_CHARGED)
        self.assertEqual(p["source"], "AC Power")
        self.assertEqual(p["percent"], 100)
        self.assertEqual(p["status"], "charged")
        self.assertEqual(p["eta"], "0:00")
        self.assertTrue(p["present"])

    def test_discharging_with_remaining(self):
        p = parse_pmset_batt(PMSET_DISCHARGING)
        self.assertEqual(p["source"], "Battery Power")
        self.assertEqual(p["percent"], 45)
        self.assertEqual(p["status"], "discharging")
        self.assertEqual(p["eta"], "3:45")
        self.assertTrue(p["present"])

    def test_charging_with_time(self):
        p = parse_pmset_batt(PMSET_CHARGING)
        self.assertEqual(p["source"], "AC Power")
        self.assertEqual(p["percent"], 80)
        self.assertEqual(p["status"], "charging")
        self.assertEqual(p["eta"], "1:23")
        self.assertTrue(p["present"])

    def test_finishing_charge_no_eta(self):
        p = parse_pmset_batt(PMSET_FINISHING)
        self.assertEqual(p["status"], "finishing charge")
        self.assertEqual(p["percent"], 95)
        self.assertIsNone(p["eta"])
        self.assertTrue(p["present"])

    def test_no_estimate(self):
        p = parse_pmset_batt(PMSET_NO_ESTIMATE)
        self.assertEqual(p["status"], "discharging")
        self.assertEqual(p["percent"], 12)
        self.assertIsNone(p["eta"])

    def test_ac_only_no_battery_line(self):
        p = parse_pmset_batt(PMSET_AC_ONLY)
        self.assertEqual(p["source"], "AC Power")
        self.assertIsNone(p["percent"])
        self.assertIsNone(p["status"])
        self.assertIsNone(p["eta"])
        self.assertIsNone(p["present"])

    def test_present_false(self):
        text = (
            "Now drawing from 'Battery Power'\n"
            " -InternalBattery-0\t50%; discharging; 2:00 remaining present: false\n"
        )
        p = parse_pmset_batt(text)
        self.assertFalse(p["present"])


class FormatStatusTests(unittest.TestCase):
    def test_charged(self):
        line = format_status(parse_pmset_batt(PMSET_AC_CHARGED))
        self.assertEqual(line, "100% charged (AC Power)")

    def test_discharging_eta(self):
        line = format_status(parse_pmset_batt(PMSET_DISCHARGING))
        self.assertEqual(line, "45% discharging, 3:45 remaining (Battery Power)")

    def test_charging_eta(self):
        line = format_status(parse_pmset_batt(PMSET_CHARGING))
        self.assertEqual(line, "80% charging, 1:23 until full (AC Power)")

    def test_finishing(self):
        line = format_status(parse_pmset_batt(PMSET_FINISHING))
        self.assertEqual(line, "95% finishing charge (AC Power)")

    def test_no_estimate(self):
        line = format_status(parse_pmset_batt(PMSET_NO_ESTIMATE))
        self.assertEqual(line, "12% discharging (Battery Power)")


class FetchAndMainTests(unittest.TestCase):
    def test_fetch_calls_pmset(self):
        completed = mock.Mock()
        completed.stdout = PMSET_DISCHARGING
        completed.returncode = 0
        with mock.patch("battery_eta.subprocess.run", return_value=completed) as run:
            text = fetch_pmset_batt()
            run.assert_called_once()
            args = run.call_args[0][0]
            self.assertEqual(args, ["pmset", "-g", "batt"])
            self.assertEqual(text, PMSET_DISCHARGING)

    def test_main_human(self):
        with mock.patch("battery_eta.fetch_pmset_batt", return_value=PMSET_DISCHARGING):
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                code = main([])
                self.assertEqual(code, 0)
                self.assertEqual(
                    out.getvalue().strip(),
                    "45% discharging, 3:45 remaining (Battery Power)",
                )

    def test_main_json(self):
        with mock.patch("battery_eta.fetch_pmset_batt", return_value=PMSET_CHARGING):
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                code = main(["--json"])
                self.assertEqual(code, 0)
                payload = json.loads(out.getvalue())
                self.assertEqual(payload["percent"], 80)
                self.assertEqual(payload["status"], "charging")
                self.assertEqual(payload["eta"], "1:23")

    def test_main_raw(self):
        with mock.patch("battery_eta.fetch_pmset_batt", return_value=PMSET_AC_CHARGED):
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                code = main(["--raw"])
                self.assertEqual(code, 0)
                self.assertEqual(out.getvalue(), PMSET_AC_CHARGED)

    def test_main_pmset_error(self):
        with mock.patch(
            "battery_eta.fetch_pmset_batt",
            side_effect=OSError("pmset missing"),
        ):
            with mock.patch("sys.stderr", new_callable=io.StringIO) as err:
                code = main([])
                self.assertNotEqual(code, 0)
                self.assertTrue(err.getvalue().startswith("battery-eta:"))


if __name__ == "__main__":
    unittest.main()
