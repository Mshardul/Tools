"""Unit tests for brew_outdated (fixture JSON; no live brew required)."""

from __future__ import annotations

import io
import json
import unittest
from unittest import mock

from brew_outdated import (
    fetch_brew_outdated_json,
    filter_report,
    format_human,
    main,
    parse_brew_outdated,
)

SAMPLE_JSON = json.dumps(
    {
        "formulae": [
            {
                "name": "git",
                "installed_versions": ["2.39.0"],
                "current_version": "2.40.0",
                "pinned": False,
                "pinned_version": None,
            },
            {
                "name": "wget",
                "installed_versions": ["1.21.3"],
                "current_version": "1.21.4",
                "pinned": False,
                "pinned_version": None,
            },
        ],
        "casks": [
            {
                "name": "firefox",
                "installed_versions": ["110.0"],
                "current_version": "111.0",
            }
        ],
    }
)

EMPTY_JSON = json.dumps({"formulae": [], "casks": []})


class ParseBrewOutdatedTests(unittest.TestCase):
    def test_parse_formulae_and_casks(self):
        report = parse_brew_outdated(SAMPLE_JSON)
        self.assertEqual(report["formulae"], ["git", "wget"])
        self.assertEqual(report["casks"], ["firefox"])
        self.assertEqual(report["count"], 3)

    def test_parse_empty(self):
        report = parse_brew_outdated(EMPTY_JSON)
        self.assertEqual(report["formulae"], [])
        self.assertEqual(report["casks"], [])
        self.assertEqual(report["count"], 0)

    def test_parse_missing_keys(self):
        report = parse_brew_outdated("{}")
        self.assertEqual(report["formulae"], [])
        self.assertEqual(report["casks"], [])
        self.assertEqual(report["count"], 0)

    def test_parse_uses_name_field(self):
        text = json.dumps(
            {
                "formulae": [{"name": "openssl@3", "current_version": "3.1.0"}],
                "casks": [{"name": "visual-studio-code"}],
            }
        )
        report = parse_brew_outdated(text)
        self.assertEqual(report["formulae"], ["openssl@3"])
        self.assertEqual(report["casks"], ["visual-studio-code"])
        self.assertEqual(report["count"], 2)


class FilterReportTests(unittest.TestCase):
    def setUp(self):
        self.report = parse_brew_outdated(SAMPLE_JSON)

    def test_formulae_only(self):
        filtered = filter_report(self.report, formulae_only=True, casks_only=False)
        self.assertEqual(filtered["formulae"], ["git", "wget"])
        self.assertEqual(filtered["casks"], [])
        self.assertEqual(filtered["count"], 2)

    def test_casks_only(self):
        filtered = filter_report(self.report, formulae_only=False, casks_only=True)
        self.assertEqual(filtered["formulae"], [])
        self.assertEqual(filtered["casks"], ["firefox"])
        self.assertEqual(filtered["count"], 1)

    def test_neither_keeps_all(self):
        filtered = filter_report(self.report, formulae_only=False, casks_only=False)
        self.assertEqual(filtered, self.report)


class FormatHumanTests(unittest.TestCase):
    def test_with_packages(self):
        report = parse_brew_outdated(SAMPLE_JSON)
        text = format_human(report)
        self.assertIn("3 outdated", text)
        self.assertIn("git", text)
        self.assertIn("wget", text)
        self.assertIn("firefox", text)

    def test_empty(self):
        report = parse_brew_outdated(EMPTY_JSON)
        self.assertEqual(format_human(report), "0 outdated")


class FetchAndMainTests(unittest.TestCase):
    def test_fetch_calls_brew_outdated_json_v2(self):
        completed = mock.Mock()
        completed.stdout = SAMPLE_JSON
        completed.returncode = 0
        with mock.patch("brew_outdated.subprocess.run", return_value=completed) as run:
            text = fetch_brew_outdated_json()
            run.assert_called_once()
            args = run.call_args[0][0]
            self.assertEqual(args, ["brew", "outdated", "--json=v2"])
            self.assertEqual(text, SAMPLE_JSON)

    def test_fetch_accepts_injected_json(self):
        text = fetch_brew_outdated_json(json_text=SAMPLE_JSON)
        self.assertEqual(text, SAMPLE_JSON)

    def test_main_human_default(self):
        with mock.patch(
            "brew_outdated.fetch_brew_outdated_json", return_value=SAMPLE_JSON
        ):
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                code = main([])
                self.assertEqual(code, 0)
                body = out.getvalue()
                self.assertIn("3 outdated", body)
                self.assertIn("git", body)
                self.assertIn("firefox", body)

    def test_main_json(self):
        with mock.patch(
            "brew_outdated.fetch_brew_outdated_json", return_value=SAMPLE_JSON
        ):
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                code = main(["--json"])
                self.assertEqual(code, 0)
                payload = json.loads(out.getvalue())
                self.assertEqual(payload["count"], 3)
                self.assertEqual(payload["formulae"], ["git", "wget"])
                self.assertEqual(payload["casks"], ["firefox"])

    def test_main_formulae_only(self):
        with mock.patch(
            "brew_outdated.fetch_brew_outdated_json", return_value=SAMPLE_JSON
        ):
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                code = main(["--formulae-only", "--json"])
                self.assertEqual(code, 0)
                payload = json.loads(out.getvalue())
                self.assertEqual(payload["count"], 2)
                self.assertEqual(payload["formulae"], ["git", "wget"])
                self.assertEqual(payload["casks"], [])

    def test_main_casks_only(self):
        with mock.patch(
            "brew_outdated.fetch_brew_outdated_json", return_value=SAMPLE_JSON
        ):
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                code = main(["--casks-only", "--json"])
                self.assertEqual(code, 0)
                payload = json.loads(out.getvalue())
                self.assertEqual(payload["count"], 1)
                self.assertEqual(payload["casks"], ["firefox"])
                self.assertEqual(payload["formulae"], [])

    def test_main_brew_missing(self):
        with mock.patch(
            "brew_outdated.fetch_brew_outdated_json",
            side_effect=FileNotFoundError(2, "No such file or directory", "brew"),
        ):
            with mock.patch("sys.stderr", new_callable=io.StringIO) as err:
                code = main([])
                self.assertEqual(code, 1)
                self.assertTrue(err.getvalue().startswith("brew-outdated:"))
                self.assertIn("brew", err.getvalue().lower())

    def test_main_mutual_exclusive_filters(self):
        with mock.patch("sys.stderr", new_callable=io.StringIO) as err:
            code = main(["--formulae-only", "--casks-only"])
            self.assertNotEqual(code, 0)
            self.assertTrue(err.getvalue().startswith("brew-outdated:"))


if __name__ == "__main__":
    unittest.main()
