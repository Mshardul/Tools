"""Unit tests for send_to_downloader queue CLI."""

from __future__ import annotations

import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from send_to_downloader import (  # noqa: E402
    DEFAULT_QUEUE_PATH,
    add_entry,
    drain_queue,
    list_entries,
    load_config,
    main,
    resolve_queue_path,
    validate_url,
)


class ValidateUrlTests(unittest.TestCase):
    def test_accepts_https(self):
        self.assertEqual(
            validate_url("https://youtu.be/abc123"),
            "https://youtu.be/abc123",
        )

    def test_accepts_http(self):
        self.assertEqual(
            validate_url("http://example.com/v"),
            "http://example.com/v",
        )

    def test_strips_whitespace(self):
        self.assertEqual(
            validate_url("  https://example.com/x  "),
            "https://example.com/x",
        )

    def test_rejects_ftp(self):
        with self.assertRaises(ValueError):
            validate_url("ftp://files.example/a")

    def test_rejects_empty(self):
        with self.assertRaises(ValueError):
            validate_url("")

    def test_rejects_relative(self):
        with self.assertRaises(ValueError):
            validate_url("/not/a/url")


class QueuePathTests(unittest.TestCase):
    def test_default_queue_path(self):
        self.assertEqual(
            DEFAULT_QUEUE_PATH,
            Path.home() / ".config" / "tools" / "send-to-downloader" / "queue.jsonl",
        )

    def test_cli_queue_wins(self):
        with tempfile.TemporaryDirectory() as tmp:
            q = Path(tmp) / "q.jsonl"
            cfg = Path(tmp) / "cfg.yaml"
            cfg.write_text(f"queue: {tmp}/from-config.jsonl\n", encoding="utf-8")
            path = resolve_queue_path(cli_queue=q, cli_config=cfg)
            self.assertEqual(path, q.expanduser())

    def test_config_queue_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            q = Path(tmp) / "from-config.jsonl"
            cfg = Path(tmp) / "cfg.yaml"
            cfg.write_text(f"queue: {q}\n", encoding="utf-8")
            path = resolve_queue_path(cli_config=cfg)
            self.assertEqual(path, q)

    def test_env_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            q = Path(tmp) / "env-queue.jsonl"
            cfg = Path(tmp) / "env.yaml"
            cfg.write_text(f"queue: {q}\n", encoding="utf-8")
            env = {**os.environ, "TOOLS_SEND_TO_DOWNLOADER_CONFIG": str(cfg)}
            with patch.dict(os.environ, env, clear=True):
                path = resolve_queue_path()
            self.assertEqual(path, q)


class LoadConfigTests(unittest.TestCase):
    def test_missing_returns_empty(self):
        self.assertEqual(load_config(Path("/nonexistent/send-to-downloader.yaml")), {})

    def test_parses_queue_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "c.yaml"
            path.write_text("queue: /tmp/q.jsonl\n", encoding="utf-8")
            self.assertEqual(load_config(path)["queue"], "/tmp/q.jsonl")


class AddListDrainTests(unittest.TestCase):
    def test_add_appends_jsonl(self):
        with tempfile.TemporaryDirectory() as tmp:
            queue = Path(tmp) / "queue.jsonl"
            entry = add_entry(
                queue,
                "https://youtu.be/one",
                title="One",
                ts="2026-01-01T00:00:00+00:00",
            )
            self.assertEqual(entry["url"], "https://youtu.be/one")
            self.assertEqual(entry["title"], "One")
            self.assertEqual(entry["ts"], "2026-01-01T00:00:00+00:00")
            lines = queue.read_text(encoding="utf-8").strip().splitlines()
            self.assertEqual(len(lines), 1)
            self.assertEqual(json.loads(lines[0])["url"], "https://youtu.be/one")

    def test_add_without_title(self):
        with tempfile.TemporaryDirectory() as tmp:
            queue = Path(tmp) / "queue.jsonl"
            entry = add_entry(queue, "https://example.com/a", ts="t1")
            self.assertNotIn("title", entry)
            self.assertEqual(list_entries(queue)[0]["url"], "https://example.com/a")

    def test_list_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            queue = Path(tmp) / "missing.jsonl"
            self.assertEqual(list_entries(queue), [])

    def test_list_pending(self):
        with tempfile.TemporaryDirectory() as tmp:
            queue = Path(tmp) / "queue.jsonl"
            add_entry(queue, "https://a.example/1", ts="t1")
            add_entry(queue, "https://b.example/2", title="B", ts="t2")
            entries = list_entries(queue)
            self.assertEqual(len(entries), 2)
            self.assertEqual(entries[1]["title"], "B")

    def test_drain_clears(self):
        with tempfile.TemporaryDirectory() as tmp:
            queue = Path(tmp) / "queue.jsonl"
            add_entry(queue, "https://a.example/1", ts="t1")
            add_entry(queue, "https://b.example/2", ts="t2")
            drained = drain_queue(queue, keep=False)
            self.assertEqual(
                [e["url"] for e in drained],
                [
                    "https://a.example/1",
                    "https://b.example/2",
                ],
            )
            self.assertEqual(list_entries(queue), [])
            self.assertTrue(queue.is_file())
            self.assertEqual(queue.read_text(encoding="utf-8"), "")

    def test_drain_keep(self):
        with tempfile.TemporaryDirectory() as tmp:
            queue = Path(tmp) / "queue.jsonl"
            add_entry(queue, "https://a.example/1", ts="t1")
            drained = drain_queue(queue, keep=True)
            self.assertEqual(len(drained), 1)
            self.assertEqual(len(list_entries(queue)), 1)

    def test_add_rejects_bad_url(self):
        with tempfile.TemporaryDirectory() as tmp:
            queue = Path(tmp) / "queue.jsonl"
            with self.assertRaises(ValueError):
                add_entry(queue, "not-a-url")


class MainCliTests(unittest.TestCase):
    def test_help_exits_zero(self):
        buf = io.StringIO()
        with patch("sys.stdout", buf):
            with self.assertRaises(SystemExit) as ctx:
                main(["-h"])
        self.assertEqual(ctx.exception.code, 0)
        self.assertIn("add", buf.getvalue())

    def test_add_list_drain_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmp:
            queue = Path(tmp) / "q.jsonl"
            out = io.StringIO()
            err = io.StringIO()
            with patch("sys.stdout", out), patch("sys.stderr", err):
                code = main(
                    [
                        "--queue",
                        str(queue),
                        "add",
                        "https://youtu.be/xyz",
                        "--title",
                        "Clip",
                    ]
                )
            self.assertEqual(code, 0)
            self.assertIn("https://youtu.be/xyz", out.getvalue())

            out = io.StringIO()
            with patch("sys.stdout", out):
                code = main(["--queue", str(queue), "list"])
            self.assertEqual(code, 0)
            self.assertIn("https://youtu.be/xyz", out.getvalue())

            out = io.StringIO()
            with patch("sys.stdout", out):
                code = main(["--queue", str(queue), "drain"])
            self.assertEqual(code, 0)
            self.assertIn("https://youtu.be/xyz", out.getvalue())
            self.assertEqual(list_entries(queue), [])

    def test_add_invalid_url_stderr_prefix(self):
        with tempfile.TemporaryDirectory() as tmp:
            queue = Path(tmp) / "q.jsonl"
            err = io.StringIO()
            with patch("sys.stderr", err):
                code = main(["--queue", str(queue), "add", "ftp://bad"])
            self.assertEqual(code, 1)
            self.assertTrue(err.getvalue().startswith("send-to-downloader:"))

    def test_list_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            queue = Path(tmp) / "q.jsonl"
            add_entry(queue, "https://example.com/z", ts="t1")
            out = io.StringIO()
            with patch("sys.stdout", out):
                code = main(["--queue", str(queue), "--json", "list"])
            self.assertEqual(code, 0)
            data = json.loads(out.getvalue())
            self.assertEqual(data[0]["url"], "https://example.com/z")


if __name__ == "__main__":
    unittest.main()
