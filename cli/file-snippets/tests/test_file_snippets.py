"""Unit tests for file_snippets."""

from __future__ import annotations

import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

from file_snippets import (
    list_snippet_names,
    load_config,
    main,
    read_snippet,
    resolve_snippets_dir,
)


class LoadConfigTests(unittest.TestCase):
    def test_reads_snippets_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "file-snippets.yaml"
            path.write_text('snippets_dir: "/tmp/my-snips"\n', encoding="utf-8")
            self.assertEqual(load_config(path), {"snippets_dir": "/tmp/my-snips"})

    def test_missing_file_empty(self):
        self.assertEqual(load_config(Path("/nonexistent/file-snippets.yaml")), {})


class ResolveSnippetsDirTests(unittest.TestCase):
    def test_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "missing.yaml"
            self.assertEqual(
                resolve_snippets_dir(cli_dir=None, env={}, config_path=cfg),
                Path("snippets"),
            )

    def test_config_over_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "cfg.yaml"
            cfg.write_text("snippets_dir: ~/from-config\n", encoding="utf-8")
            got = resolve_snippets_dir(cli_dir=None, env={}, config_path=cfg)
            self.assertEqual(got, Path("~/from-config").expanduser())

    def test_env_over_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "cfg.yaml"
            cfg.write_text("snippets_dir: /from-config\n", encoding="utf-8")
            got = resolve_snippets_dir(
                cli_dir=None,
                env={"TOOLS_FILE_SNIPPETS_DIR": "/from-env"},
                config_path=cfg,
            )
            self.assertEqual(got, Path("/from-env"))

    def test_cli_over_env(self):
        got = resolve_snippets_dir(
            cli_dir="/from-cli",
            env={"TOOLS_FILE_SNIPPETS_DIR": "/from-env"},
            config_path=Path("/nonexistent.yaml"),
        )
        self.assertEqual(got, Path("/from-cli"))


class ListSnippetNamesTests(unittest.TestCase):
    def test_lists_stems_sorted(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "zebra.txt").write_text("z", encoding="utf-8")
            (root / "alpha.md").write_text("a", encoding="utf-8")
            (root / "mid.sh").write_text("m", encoding="utf-8")
            self.assertEqual(list_snippet_names(root), ["alpha", "mid", "zebra"])

    def test_ignores_hidden_and_dirs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "keep.txt").write_text("k", encoding="utf-8")
            (root / ".secret").write_text("x", encoding="utf-8")
            (root / "subdir").mkdir()
            (root / "subdir" / "nested.txt").write_text("n", encoding="utf-8")
            self.assertEqual(list_snippet_names(root), ["keep"])

    def test_missing_dir(self):
        with self.assertRaises(FileNotFoundError):
            list_snippet_names(Path("/nonexistent/snippets-dir-xyz"))


class ReadSnippetTests(unittest.TestCase):
    def test_reads_contents(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "hello.txt").write_text("hi there\n", encoding="utf-8")
            self.assertEqual(read_snippet(root, "hello"), "hi there\n")

    def test_unknown_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.txt").write_text("a", encoding="utf-8")
            with self.assertRaises(FileNotFoundError):
                read_snippet(root, "missing")

    def test_missing_dir(self):
        with self.assertRaises(FileNotFoundError):
            read_snippet(Path("/nonexistent/snippets-dir-xyz"), "x")


class MainCliTests(unittest.TestCase):
    def _run(self, argv: list[str], *, env: dict[str, str] | None = None):
        out = io.StringIO()
        err = io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            if env is None:
                code = main(argv)
            else:
                with mock.patch.dict(os.environ, env, clear=False):
                    code = main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_list(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "b.txt").write_text("b", encoding="utf-8")
            (root / "a.txt").write_text("a", encoding="utf-8")
            code, out, err = self._run(["--dir", str(root), "list"])
            self.assertEqual(code, 0)
            self.assertEqual(out, "a\nb\n")
            self.assertEqual(err, "")

    def test_list_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "one.txt").write_text("1", encoding="utf-8")
            code, out, err = self._run(["--dir", str(root), "list", "--json"])
            self.assertEqual(code, 0)
            self.assertEqual(json.loads(out), ["one"])
            self.assertEqual(err, "")

    def test_show(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "greet.txt").write_text("hello\n", encoding="utf-8")
            code, out, err = self._run(["--dir", str(root), "show", "greet"])
            self.assertEqual(code, 0)
            self.assertEqual(out, "hello\n")
            self.assertEqual(err, "")

    def test_show_clipboard(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "x.txt").write_text("clip me", encoding="utf-8")
            with mock.patch("file_snippets.subprocess.run") as run:
                run.return_value = mock.Mock(returncode=0)
                code, out, err = self._run(["--dir", str(root), "show", "x", "-c"])
            self.assertEqual(code, 0)
            self.assertEqual(out, "clip me")
            self.assertEqual(err, "")
            run.assert_called_once()
            args, kwargs = run.call_args
            self.assertEqual(args[0], ["pbcopy"])
            self.assertEqual(kwargs.get("input"), b"clip me")

    def test_missing_dir_exit_2(self):
        code, out, err = self._run(["--dir", "/nonexistent/snippets-xyz", "list"])
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("file-snippets:", err)

    def test_unknown_name_exit_2(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, out, err = self._run(["--dir", tmp, "show", "nope"])
            self.assertEqual(code, 2)
            self.assertEqual(out, "")
            self.assertIn("file-snippets:", err)
            self.assertIn("nope", err)


if __name__ == "__main__":
    unittest.main()
