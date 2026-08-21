#!/usr/bin/env python3
"""Tests for floating-note file helpers (no display required)."""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from floating_note import default_path, load_text, save_text


class DefaultPathTests(unittest.TestCase):
    def test_default_path_under_local_share(self):
        with patch.dict(os.environ, {"HOME": "/tmp/fake-home"}, clear=False):
            # Path.home() reads HOME on Unix
            path = default_path()
        self.assertTrue(str(path).endswith("floating-note.txt"))
        self.assertIn(".local", str(path))
        self.assertIn("share", str(path))
        self.assertIn("tools", str(path))


class LoadSaveTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "note.txt"

    def tearDown(self):
        self.tmp.cleanup()

    def test_load_missing_returns_empty(self):
        self.assertEqual(load_text(self.path), "")

    def test_save_creates_parent_dirs(self):
        nested = Path(self.tmp.name) / "a" / "b" / "note.txt"
        save_text(nested, "hello")
        self.assertEqual(nested.read_text(encoding="utf-8"), "hello")

    def test_roundtrip(self):
        save_text(self.path, "scratch pad\nline 2")
        self.assertEqual(load_text(self.path), "scratch pad\nline 2")

    def test_save_overwrites(self):
        save_text(self.path, "old")
        save_text(self.path, "new")
        self.assertEqual(load_text(self.path), "new")


if __name__ == "__main__":
    unittest.main()
