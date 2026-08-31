#!/usr/bin/env python3
"""Unit tests for claude-session-archive (temp dirs; no real ~/.claude)."""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from claude_session_archive import (
    default_root,
    discover_sessions,
    export_session,
    list_sessions,
    main,
    search_sessions,
    session_summary,
)


def _write_jsonl(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [json.dumps(r, ensure_ascii=False) for r in records]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


class DefaultRootTests(unittest.TestCase):
    def test_default_root_ends_with_claude_projects(self):
        root = default_root()
        self.assertEqual(root.name, "projects")
        self.assertEqual(root.parent.name, ".claude")


class DiscoverSessionsTests(unittest.TestCase):
    def test_finds_jsonl_recursively(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            a = root / "proj-a" / "sess-1.jsonl"
            b = root / "proj-b" / "nested" / "sess-2.jsonl"
            _write_jsonl(a, [{"type": "user", "message": {"content": "hi"}}])
            _write_jsonl(b, [{"type": "user", "message": {"content": "yo"}}])
            (root / "proj-a" / "notes.txt").write_text("ignore", encoding="utf-8")
            found = discover_sessions(root)
            names = {p.name for p in found}
            self.assertEqual(names, {"sess-1.jsonl", "sess-2.jsonl"})

    def test_empty_root(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(discover_sessions(tmp), [])

    def test_missing_root_raises(self):
        with self.assertRaises(FileNotFoundError):
            discover_sessions("/no/such/claude/projects/dir")


class SessionSummaryTests(unittest.TestCase):
    def test_prefers_ai_title(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "s.jsonl"
            _write_jsonl(
                path,
                [
                    {
                        "type": "user",
                        "message": {"content": "first user prompt about widgets"},
                    },
                    {"type": "ai-title", "aiTitle": "Widget refactor plan"},
                ],
            )
            self.assertEqual(session_summary(path), "Widget refactor plan")

    def test_falls_back_to_first_user_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "s.jsonl"
            _write_jsonl(
                path,
                [
                    {"type": "queue-operation", "operation": "enqueue"},
                    {
                        "type": "user",
                        "message": {
                            "content": [{"type": "text", "text": "Please fix the flaky test"}]
                        },
                    },
                ],
            )
            self.assertIn("flaky test", session_summary(path))

    def test_unparseable_returns_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "s.jsonl"
            path.write_text("not-json\n{bad}\n", encoding="utf-8")
            self.assertEqual(session_summary(path), "")


class ListSessionsTests(unittest.TestCase):
    def test_list_includes_path_mtime_size_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "p" / "one.jsonl"
            _write_jsonl(
                path,
                [{"type": "ai-title", "aiTitle": "Alpha session"}],
            )
            rows = list_sessions(root)
            self.assertEqual(len(rows), 1)
            row = rows[0]
            self.assertEqual(Path(row["path"]), path.resolve())
            self.assertIn("mtime", row)
            self.assertGreater(row["size"], 0)
            self.assertEqual(row["summary"], "Alpha session")


class SearchSessionsTests(unittest.TestCase):
    def test_case_insensitive_substring(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            hit = root / "a" / "hit.jsonl"
            miss = root / "b" / "miss.jsonl"
            _write_jsonl(
                hit,
                [
                    {
                        "type": "user",
                        "message": {"content": "Discuss UNIQUE_TOKEN_XYZ later"},
                    }
                ],
            )
            _write_jsonl(
                miss,
                [{"type": "user", "message": {"content": "nothing relevant here"}}],
            )
            results = search_sessions(root, "unique_token_xyz")
            self.assertEqual(len(results), 1)
            self.assertEqual(Path(results[0]["path"]), hit.resolve())
            self.assertIn("UNIQUE_TOKEN_XYZ", results[0]["snippet"])

    def test_no_matches(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "p" / "s.jsonl"
            _write_jsonl(path, [{"type": "user", "message": {"content": "hello"}}])
            self.assertEqual(search_sessions(root, "zzzz-absent"), [])


class ExportSessionTests(unittest.TestCase):
    def test_export_jsonl_copies_content(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "src.jsonl"
            out = Path(tmp) / "out" / "copy.jsonl"
            body = '{"type":"user","message":{"content":"export me"}}\n'
            src.write_text(body, encoding="utf-8")
            export_session(src, out, fmt="jsonl")
            self.assertEqual(out.read_text(encoding="utf-8"), body)

    def test_export_markdown_includes_summary_and_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "src.jsonl"
            out = Path(tmp) / "out.md"
            _write_jsonl(
                src,
                [
                    {"type": "ai-title", "aiTitle": "Export Demo"},
                    {
                        "type": "user",
                        "message": {"content": "Hello from user"},
                    },
                    {
                        "type": "assistant",
                        "message": {"content": [{"type": "text", "text": "Hello from assistant"}]},
                    },
                ],
            )
            export_session(src, out, fmt="markdown")
            text = out.read_text(encoding="utf-8")
            self.assertIn("Export Demo", text)
            self.assertIn("Hello from user", text)
            self.assertIn("Hello from assistant", text)

    def test_export_missing_source_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(FileNotFoundError):
                export_session(Path(tmp) / "nope.jsonl", Path(tmp) / "out.jsonl")


class MainCliTests(unittest.TestCase):
    def test_help_exits_zero(self):
        buf = io.StringIO()
        err = io.StringIO()
        with redirect_stdout(buf), redirect_stderr(err):
            with self.assertRaises(SystemExit) as cm:
                main(["-h"])
        self.assertEqual(cm.exception.code, 0)
        self.assertIn("list", buf.getvalue().lower() + err.getvalue().lower())

    def test_list_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "p" / "s.jsonl"
            _write_jsonl(path, [{"type": "ai-title", "aiTitle": "CLI List"}])
            out = io.StringIO()
            with redirect_stdout(out):
                code = main(["--root", str(root), "--json", "list"])
            self.assertEqual(code, 0)
            data = json.loads(out.getvalue())
            self.assertEqual(len(data), 1)
            self.assertEqual(data[0]["summary"], "CLI List")

    def test_search_and_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src = root / "p" / "s.jsonl"
            _write_jsonl(
                src,
                [
                    {
                        "type": "user",
                        "message": {"content": "needle FINDME in session"},
                    }
                ],
            )
            out = io.StringIO()
            with redirect_stdout(out):
                code = main(["--root", str(root), "search", "findme"])
            self.assertEqual(code, 0)
            self.assertIn(str(src.resolve()), out.getvalue())

            dest = Path(tmp) / "exported.jsonl"
            out2 = io.StringIO()
            with redirect_stdout(out2):
                code = main(["export", str(src), "-o", str(dest)])
            self.assertEqual(code, 0)
            self.assertTrue(dest.is_file())
            self.assertIn(str(dest.resolve()), out2.getvalue())

    def test_error_prefix_on_stderr(self):
        err = io.StringIO()
        with redirect_stderr(err):
            code = main(["--root", "/no/such/root/xyz", "list"])
        self.assertNotEqual(code, 0)
        self.assertTrue(err.getvalue().startswith("claude-session-archive:"))


if __name__ == "__main__":
    unittest.main()
