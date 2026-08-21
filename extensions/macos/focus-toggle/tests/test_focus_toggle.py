"""Unit tests for focus_toggle (subprocess mocked)."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from focus_toggle import (  # noqa: E402
    build_shortcuts_argv,
    load_config,
    resolve_shortcut,
    status_payload,
)


class LoadConfigTests(unittest.TestCase):
    def test_missing_file_returns_empty(self):
        self.assertEqual(load_config(Path("/nonexistent/focus-toggle.yaml")), {})

    def test_loads_flat_yaml(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "focus-toggle.yaml"
            path.write_text(
                "shortcut_on: My Focus On\n"
                "shortcut_off: 'My Focus Off'\n"
                '# comment\n'
                "shortcut_toggle: Toggle Focus\n",
                encoding="utf-8",
            )
            cfg = load_config(path)
            self.assertEqual(cfg["shortcut_on"], "My Focus On")
            self.assertEqual(cfg["shortcut_off"], "My Focus Off")
            self.assertEqual(cfg["shortcut_toggle"], "Toggle Focus")


class ResolveShortcutTests(unittest.TestCase):
    def test_defaults_by_mode(self):
        self.assertEqual(resolve_shortcut("on", {}), "Focus On")
        self.assertEqual(resolve_shortcut("off", {}), "Focus Off")
        self.assertEqual(resolve_shortcut("toggle", {}), "Toggle Focus")

    def test_config_overrides_defaults(self):
        cfg = {
            "shortcut_on": "DND On",
            "shortcut_off": "DND Off",
            "shortcut_toggle": "DND Toggle",
        }
        self.assertEqual(resolve_shortcut("on", cfg), "DND On")
        self.assertEqual(resolve_shortcut("off", cfg), "DND Off")
        self.assertEqual(resolve_shortcut("toggle", cfg), "DND Toggle")

    def test_cli_shortcut_overrides_all(self):
        cfg = {"shortcut_on": "DND On"}
        self.assertEqual(
            resolve_shortcut("on", cfg, cli_shortcut="Custom"),
            "Custom",
        )
        self.assertEqual(
            resolve_shortcut("toggle", {}, cli_shortcut="Custom"),
            "Custom",
        )

    def test_unknown_mode_raises(self):
        with self.assertRaises(ValueError):
            resolve_shortcut("nope", {})


class BuildShortcutsArgvTests(unittest.TestCase):
    def test_argv(self):
        self.assertEqual(
            build_shortcuts_argv("Toggle Focus"),
            ["shortcuts", "run", "Toggle Focus"],
        )


class StatusPayloadTests(unittest.TestCase):
    def test_status_includes_names_and_availability(self):
        with patch("focus_toggle.shutil.which", return_value="/usr/bin/shortcuts"):
            payload = status_payload({})
        self.assertTrue(payload["shortcuts_available"])
        self.assertEqual(payload["shortcut_on"], "Focus On")
        self.assertEqual(payload["shortcut_off"], "Focus Off")
        self.assertEqual(payload["shortcut_toggle"], "Toggle Focus")

    def test_status_unavailable(self):
        with patch("focus_toggle.shutil.which", return_value=None):
            payload = status_payload({})
        self.assertFalse(payload["shortcuts_available"])


class RunShortcutTests(unittest.TestCase):
    def test_run_shortcut_invokes_subprocess(self):
        from focus_toggle import run_shortcut

        with patch("focus_toggle.subprocess.run") as run:
            run.return_value = MagicMock(returncode=0, stdout="", stderr="")
            run_shortcut("Toggle Focus")
            run.assert_called_once()
            args = run.call_args[0][0]
            self.assertEqual(args, ["shortcuts", "run", "Toggle Focus"])


if __name__ == "__main__":
    unittest.main()
