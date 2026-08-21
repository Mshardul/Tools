"""Unit tests for open-terminal-here."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from open_terminal_here import open_terminal_at, resolve_target


class ResolveTargetTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.folder = self.root / "dir"
        self.folder.mkdir()
        self.file = self.root / "file.txt"
        self.file.write_text("x", encoding="utf-8")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_directory_unchanged(self) -> None:
        self.assertEqual(resolve_target(self.folder), self.folder.resolve())

    def test_file_uses_parent(self) -> None:
        self.assertEqual(resolve_target(self.file), self.root.resolve())

    def test_missing_raises(self) -> None:
        with self.assertRaises(FileNotFoundError):
            resolve_target(self.root / "nope")


class OpenTerminalTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.folder = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_runs_open_a_terminal(self) -> None:
        with mock.patch("open_terminal_here.subprocess.run") as run:
            run.return_value = mock.Mock(returncode=0)
            open_terminal_at(self.folder, app="Terminal")
            run.assert_called_once()
            args = run.call_args[0][0]
            self.assertEqual(args[:3], ["open", "-a", "Terminal"])
            self.assertEqual(args[3], str(self.folder.resolve()))


if __name__ == "__main__":
    unittest.main()
