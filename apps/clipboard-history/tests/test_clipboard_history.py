#!/usr/bin/env python3
"""Tests for clipboard-history store/search/pin (temp dirs; no live pasteboard)."""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock

from clipboard_history import (
    MAX_TEXT_BYTES,
    HistoryStore,
    default_db_path,
    main,
    watch_clipboard,
)


class DefaultPathTests(unittest.TestCase):
    def test_default_db_path_under_share_or_config(self):
        path = default_db_path()
        parts = path.parts
        self.assertTrue(
            "clipboard-history" in parts,
            f"expected clipboard-history in path: {path}",
        )
        self.assertEqual(path.name, "history.db")


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "history.db"
        self.store = HistoryStore(self.db)

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_add_and_get(self):
        eid = self.store.add("hello", ts=1_700_000_000.0)
        entry = self.store.get(eid)
        self.assertEqual(entry["id"], eid)
        self.assertEqual(entry["text"], "hello")
        self.assertEqual(entry["ts"], 1_700_000_000.0)
        self.assertFalse(entry["pinned"])

    def test_dedupe_consecutive_identical(self):
        a = self.store.add("same", ts=1.0)
        b = self.store.add("same", ts=2.0)
        self.assertEqual(a, b)
        self.assertEqual(len(self.store.list_entries()), 1)

    def test_allows_same_text_after_different(self):
        self.store.add("a", ts=1.0)
        self.store.add("b", ts=2.0)
        c = self.store.add("a", ts=3.0)
        entries = self.store.list_entries()
        self.assertEqual(len(entries), 3)
        self.assertEqual(self.store.get(c)["text"], "a")

    def test_skips_huge_blob(self):
        huge = "x" * (MAX_TEXT_BYTES + 1)
        eid = self.store.add(huge, ts=1.0)
        self.assertIsNone(eid)
        self.assertEqual(self.store.list_entries(), [])

    def test_accepts_at_max_bytes(self):
        text = "y" * MAX_TEXT_BYTES
        eid = self.store.add(text, ts=1.0)
        self.assertIsNotNone(eid)
        self.assertEqual(len(self.store.get(eid)["text"]), MAX_TEXT_BYTES)

    def test_list_recent_order_and_limit(self):
        self.store.add("one", ts=1.0)
        self.store.add("two", ts=2.0)
        self.store.add("three", ts=3.0)
        recent = self.store.list_entries(limit=2)
        self.assertEqual([e["text"] for e in recent], ["three", "two"])

    def test_search_substring(self):
        self.store.add("alpha beta", ts=1.0)
        self.store.add("gamma", ts=2.0)
        self.store.add("BETA gamma", ts=3.0)
        hits = self.store.search("beta")
        self.assertEqual([e["text"] for e in hits], ["BETA gamma", "alpha beta"])

    def test_pin_unpin_and_pins(self):
        a = self.store.add("pinned later", ts=1.0)
        b = self.store.add("also", ts=2.0)
        self.store.pin(a)
        pins = self.store.list_pins()
        self.assertEqual([e["id"] for e in pins], [a])
        self.assertTrue(self.store.get(a)["pinned"])
        self.assertFalse(self.store.get(b)["pinned"])
        self.store.unpin(a)
        self.assertEqual(self.store.list_pins(), [])
        self.assertFalse(self.store.get(a)["pinned"])

    def test_pin_unknown_raises(self):
        with self.assertRaises(KeyError):
            self.store.pin(999)

    def test_get_unknown_raises(self):
        with self.assertRaises(KeyError):
            self.store.get(999)


class WatchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "history.db"
        self.store = HistoryStore(self.db)

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_watch_polls_and_stores_with_injectable_reader(self):
        readings = iter(["first", "first", "second", "second"])
        sleeps: list[float] = []

        def read_fn() -> str:
            try:
                return next(readings)
            except StopIteration:
                raise KeyboardInterrupt

        def sleep_fn(seconds: float) -> None:
            sleeps.append(seconds)

        clock = MagicMock(side_effect=[10.0, 11.0, 12.0, 13.0])
        with self.assertRaises(KeyboardInterrupt):
            watch_clipboard(
                self.store,
                interval=0.5,
                read_fn=read_fn,
                sleep_fn=sleep_fn,
                clock=clock,
            )
        texts = [e["text"] for e in self.store.list_entries()]
        self.assertEqual(texts, ["second", "first"])
        self.assertTrue(sleeps)  # slept between polls


class CliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "history.db"

    def tearDown(self):
        self.tmp.cleanup()

    def _seed(self) -> int:
        store = HistoryStore(self.db)
        eid = store.add("hello world", ts=100.0)
        store.close()
        return eid

    def test_list_json(self):
        self._seed()
        out = io.StringIO()
        err = io.StringIO()
        code = main(
            ["--db", str(self.db), "--json", "list", "--limit", "5"],
            out=out,
            err=err,
        )
        self.assertEqual(code, 0)
        data = json.loads(out.getvalue())
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]["text"], "hello world")

    def test_search_and_get(self):
        eid = self._seed()
        out = io.StringIO()
        code = main(
            ["--db", str(self.db), "search", "hello"],
            out=out,
            err=io.StringIO(),
        )
        self.assertEqual(code, 0)
        self.assertIn("hello world", out.getvalue())

        out2 = io.StringIO()
        code = main(
            ["--db", str(self.db), "get", str(eid)],
            out=out2,
            err=io.StringIO(),
        )
        self.assertEqual(code, 0)
        self.assertEqual(out2.getvalue(), "hello world")

    def test_pin_flow(self):
        eid = self._seed()
        err = io.StringIO()
        self.assertEqual(
            main(["--db", str(self.db), "pin", str(eid)], out=io.StringIO(), err=err),
            0,
        )
        out = io.StringIO()
        self.assertEqual(
            main(["--db", str(self.db), "--json", "pins"], out=out, err=io.StringIO()),
            0,
        )
        data = json.loads(out.getvalue())
        self.assertEqual(data[0]["id"], eid)
        self.assertEqual(
            main(
                ["--db", str(self.db), "unpin", str(eid)],
                out=io.StringIO(),
                err=io.StringIO(),
            ),
            0,
        )

    def test_get_missing_stderr_prefix(self):
        err = io.StringIO()
        code = main(
            ["--db", str(self.db), "get", "42"],
            out=io.StringIO(),
            err=err,
        )
        self.assertEqual(code, 1)
        self.assertTrue(err.getvalue().startswith("clipboard-history:"))

    def test_copy_uses_injectable_write(self):
        eid = self._seed()
        copied: list[str] = []

        def write_fn(text: str) -> None:
            copied.append(text)

        code = main(
            ["--db", str(self.db), "copy", str(eid)],
            out=io.StringIO(),
            err=io.StringIO(),
            clipboard_write_fn=write_fn,
        )
        self.assertEqual(code, 0)
        self.assertEqual(copied, ["hello world"])


if __name__ == "__main__":
    unittest.main()
