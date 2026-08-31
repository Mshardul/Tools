"""Unit tests for mic_mute (subprocess mocked)."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from mic_mute import (  # noqa: E402
    decide_toggle,
    load_state,
    parse_volume_settings,
    save_state,
)


class ParseVolumeSettingsTests(unittest.TestCase):
    def test_parses_standard_output(self):
        text = "output volume:50, input volume:75, alert volume:100, output muted:false"
        result = parse_volume_settings(text)
        self.assertEqual(result["output_volume"], 50)
        self.assertEqual(result["input_volume"], 75)
        self.assertEqual(result["alert_volume"], 100)
        self.assertFalse(result["output_muted"])

    def test_parses_muted_true(self):
        text = "output volume:0, input volume:0, alert volume:50, output muted:true"
        result = parse_volume_settings(text)
        self.assertEqual(result["input_volume"], 0)
        self.assertTrue(result["output_muted"])

    def test_invalid_raises(self):
        with self.assertRaises(ValueError):
            parse_volume_settings("not volume settings")


class DecideToggleTests(unittest.TestCase):
    def test_zero_means_unmute(self):
        self.assertEqual(decide_toggle(0), "unmute")

    def test_nonzero_means_mute(self):
        self.assertEqual(decide_toggle(50), "mute")
        self.assertEqual(decide_toggle(1), "mute")


class StateTests(unittest.TestCase):
    def test_load_missing_returns_empty(self):
        self.assertEqual(load_state(Path("/nonexistent/mic-mute.yaml")), {})

    def test_save_and_load_last_volume(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "mic-mute.yaml"
            save_state(path, last_input_volume=42)
            self.assertEqual(load_state(path)["last_input_volume"], 42)

    def test_load_parses_int(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "mic-mute.yaml"
            path.write_text("last_input_volume: 80\n", encoding="utf-8")
            self.assertEqual(load_state(path)["last_input_volume"], 80)


class OsascriptHelpersTests(unittest.TestCase):
    def test_get_input_volume_uses_osascript(self):
        from mic_mute import get_volume_settings

        text = "output volume:50, input volume:33, alert volume:100, output muted:false"
        with patch("mic_mute.subprocess.run") as run:
            run.return_value = MagicMock(returncode=0, stdout=text, stderr="")
            settings = get_volume_settings()
            self.assertEqual(settings["input_volume"], 33)
            args = run.call_args[0][0]
            self.assertEqual(args[0], "osascript")
            self.assertIn("get volume settings", args[-1])

    def test_set_input_volume(self):
        from mic_mute import set_input_volume

        with patch("mic_mute.subprocess.run") as run:
            run.return_value = MagicMock(returncode=0, stdout="", stderr="")
            set_input_volume(0)
            args = run.call_args[0][0]
            self.assertEqual(args[0], "osascript")
            self.assertIn("set volume input volume 0", args[-1])


if __name__ == "__main__":
    unittest.main()
