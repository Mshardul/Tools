#!/usr/bin/env python3
"""Tests for pomodoro timer (pure logic; no real waits)."""

from __future__ import annotations

import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock

from pomodoro import (
    DEFAULT_BREAK_MIN,
    DEFAULT_WORK_MIN,
    clear_state,
    phase_seconds,
    read_state,
    remaining_seconds,
    run_timer,
    write_state,
)


class PhaseSecondsTests(unittest.TestCase):
    def test_work_default_minutes(self):
        self.assertEqual(
            phase_seconds("work", DEFAULT_WORK_MIN, DEFAULT_BREAK_MIN, None),
            25 * 60,
        )

    def test_break_default_minutes(self):
        self.assertEqual(
            phase_seconds("break", DEFAULT_WORK_MIN, DEFAULT_BREAK_MIN, None),
            5 * 60,
        )

    def test_custom_work_min(self):
        self.assertEqual(phase_seconds("work", 10, 3, None), 600)

    def test_seconds_override(self):
        self.assertEqual(phase_seconds("work", 25, 5, 12), 12)

    def test_unknown_phase(self):
        with self.assertRaises(ValueError):
            phase_seconds("idle", 25, 5, None)


class StateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "pomodoro-state.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_write_and_read_roundtrip(self):
        write_state(self.path, phase="work", end_ts=1_700_000_000.0)
        state = read_state(self.path)
        self.assertEqual(state["phase"], "work")
        self.assertEqual(state["end_ts"], 1_700_000_000.0)

    def test_read_missing_returns_none(self):
        self.assertIsNone(read_state(self.path))

    def test_clear_state(self):
        write_state(self.path, phase="break", end_ts=100.0)
        clear_state(self.path)
        self.assertIsNone(read_state(self.path))
        self.assertFalse(self.path.exists())

    def test_remaining_positive(self):
        state = {"phase": "work", "end_ts": 200.0}
        self.assertEqual(remaining_seconds(state, now=150.0), 50.0)

    def test_remaining_clamped_at_zero(self):
        state = {"phase": "work", "end_ts": 100.0}
        self.assertEqual(remaining_seconds(state, now=150.0), 0.0)


class RunTimerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "pomodoro-state.json"
        self.sleeps: list[float] = []
        self.notifies: list[tuple[str, str]] = []
        self.out = io.StringIO()

    def tearDown(self):
        self.tmp.cleanup()

    def _sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)

    def _notify(self, title: str, message: str) -> None:
        self.notifies.append((title, message))

    def test_run_timer_sleeps_and_notifies(self):
        clock = MagicMock(return_value=1000.0)
        run_timer(
            "work",
            duration_sec=3,
            state_path=self.path,
            sleep_fn=self._sleep,
            notify_fn=self._notify,
            clock=clock,
            do_notify=True,
            out=self.out,
        )
        self.assertEqual(sum(self.sleeps), 3)
        self.assertEqual(self.notifies, [("Pomodoro", "work done")])
        self.assertIsNone(read_state(self.path))

    def test_run_timer_no_notify(self):
        clock = MagicMock(return_value=1000.0)
        run_timer(
            "break",
            duration_sec=1,
            state_path=self.path,
            sleep_fn=self._sleep,
            notify_fn=self._notify,
            clock=clock,
            do_notify=False,
            out=self.out,
        )
        self.assertEqual(self.notifies, [])

    def test_run_timer_writes_state_during_run(self):
        seen: dict = {}

        def sleep_and_capture(_sec: float) -> None:
            seen["during"] = read_state(self.path)

        clock = MagicMock(return_value=1000.0)
        run_timer(
            "work",
            duration_sec=2,
            state_path=self.path,
            sleep_fn=sleep_and_capture,
            notify_fn=self._notify,
            clock=clock,
            do_notify=False,
            out=self.out,
        )
        self.assertIsNotNone(seen.get("during"))
        self.assertEqual(seen["during"]["phase"], "work")
        self.assertEqual(seen["during"]["end_ts"], 1002.0)


class AppleScriptEscapeTests(unittest.TestCase):
    def test_escape_quotes_and_backslashes(self):
        from pomodoro import apple_script_escape

        self.assertEqual(apple_script_escape('a"b\\c'), 'a\\"b\\\\c')


if __name__ == "__main__":
    unittest.main()
