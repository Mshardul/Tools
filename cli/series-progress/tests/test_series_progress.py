"""Unit tests for series-progress."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from series_progress import (
    SIDE_CAR,
    VIDEO_SUFFIXES,
    list_episodes,
    load_progress,
    mark_done,
    next_episode,
    save_progress,
)


class SeriesProgressTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        for name in ("a.mkv", "b.mkv", "c.mp4", "readme.txt", "cover.jpg"):
            (self.root / name).write_bytes(b"x")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_list_episodes_sorted_video_only(self) -> None:
        eps = list_episodes(self.root)
        self.assertEqual(eps, ["a.mkv", "b.mkv", "c.mp4"])
        self.assertTrue(all(Path(e).suffix.lower() in VIDEO_SUFFIXES for e in eps))

    def test_load_missing_returns_none(self) -> None:
        self.assertIsNone(load_progress(self.root))

    def test_save_and_load(self) -> None:
        save_progress(self.root, "b.mkv")
        self.assertEqual(load_progress(self.root), "b.mkv")
        data = json.loads((self.root / SIDE_CAR).read_text(encoding="utf-8"))
        self.assertEqual(data["current"], "b.mkv")

    def test_next_from_unset_is_first(self) -> None:
        self.assertEqual(next_episode(self.root), "a.mkv")

    def test_next_after_current(self) -> None:
        save_progress(self.root, "a.mkv")
        self.assertEqual(next_episode(self.root), "b.mkv")

    def test_next_at_end_is_none(self) -> None:
        save_progress(self.root, "c.mp4")
        self.assertIsNone(next_episode(self.root))

    def test_mark_done_advances(self) -> None:
        save_progress(self.root, "a.mkv")
        advanced = mark_done(self.root)
        self.assertEqual(advanced, "b.mkv")
        self.assertEqual(load_progress(self.root), "b.mkv")

    def test_mark_done_at_end(self) -> None:
        save_progress(self.root, "c.mp4")
        self.assertIsNone(mark_done(self.root))
        self.assertEqual(load_progress(self.root), "c.mp4")


if __name__ == "__main__":
    unittest.main()
