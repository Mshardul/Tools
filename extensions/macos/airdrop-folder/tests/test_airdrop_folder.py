"""Unit tests for airdrop_folder (subprocess mocked)."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from unittest import mock
from unittest.mock import MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from airdrop_folder import (  # noqa: E402
    AIRDROP_APP,
    applescript_quote,
    build_finder_select_script,
    build_open_airdrop_argv,
    main,
    resolve_paths,
    share_via_airdrop,
)


class ResolvePathsTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.file_a = self.root / "a.txt"
        self.file_b = self.root / "b.txt"
        self.folder = self.root / "dir"
        self.file_a.write_text("a", encoding="utf-8")
        self.file_b.write_text("b", encoding="utf-8")
        self.folder.mkdir()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_resolves_multiple_existing_paths(self) -> None:
        resolved = resolve_paths([str(self.file_a), str(self.folder)])
        self.assertEqual(resolved, [self.file_a.resolve(), self.folder.resolve()])

    def test_expands_user(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            marker = home / "marker.txt"
            marker.write_text("x", encoding="utf-8")
            with mock.patch.dict(os.environ, {"HOME": str(home)}):
                resolved = resolve_paths(["~/marker.txt"])
            self.assertEqual(resolved, [marker.resolve()])

    def test_missing_raises(self) -> None:
        with self.assertRaises(FileNotFoundError) as ctx:
            resolve_paths([str(self.root / "missing.txt")])
        self.assertIn("missing.txt", str(ctx.exception))

    def test_empty_list_raises(self) -> None:
        with self.assertRaises(ValueError):
            resolve_paths([])


class AppleScriptQuoteTests(unittest.TestCase):
    def test_escapes_quotes_and_backslashes(self) -> None:
        self.assertEqual(applescript_quote('a"b\\c'), 'a\\"b\\\\c')


class BuildArgvAndScriptTests(unittest.TestCase):
    def test_open_airdrop_argv(self) -> None:
        self.assertEqual(
            build_open_airdrop_argv(),
            ["open", AIRDROP_APP],
        )

    def test_finder_select_script_includes_paths(self) -> None:
        paths = [Path("/tmp/one.txt"), Path("/tmp/two dir/file.txt")]
        script = build_finder_select_script(paths)
        self.assertIn('tell application "Finder"', script)
        self.assertIn("/tmp/one.txt", script)
        self.assertIn("/tmp/two dir/file.txt", script)
        self.assertIn("POSIX file", script)
        self.assertIn("select", script)
        self.assertIn("reveal", script)


class ShareViaAirdropTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.file = Path(self._tmp.name) / "share-me.txt"
        self.file.write_text("x", encoding="utf-8")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_runs_osascript_then_open_airdrop(self) -> None:
        calls: list[list[str]] = []

        def fake_runner(argv, **_kwargs):
            calls.append(list(argv))
            return MagicMock(returncode=0, stdout="", stderr="")

        share_via_airdrop([self.file.resolve()], runner=fake_runner)
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0][0], "osascript")
        self.assertEqual(calls[0][1], "-e")
        self.assertIn(str(self.file.resolve()), calls[0][2])
        self.assertEqual(calls[1], ["open", AIRDROP_APP])

    def test_osascript_failure_raises(self) -> None:
        def fake_runner(argv, **_kwargs):
            if argv[0] == "osascript":
                return MagicMock(returncode=1, stdout="", stderr="script boom")
            return MagicMock(returncode=0, stdout="", stderr="")

        with self.assertRaises(RuntimeError) as ctx:
            share_via_airdrop([self.file.resolve()], runner=fake_runner)
        self.assertIn("script boom", str(ctx.exception))

    def test_open_failure_raises(self) -> None:
        def fake_runner(argv, **_kwargs):
            if argv[0] == "open":
                return MagicMock(returncode=1, stdout="", stderr="open boom")
            return MagicMock(returncode=0, stdout="", stderr="")

        with self.assertRaises(RuntimeError) as ctx:
            share_via_airdrop([self.file.resolve()], runner=fake_runner)
        self.assertIn("open boom", str(ctx.exception))


class MainCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.file = Path(self._tmp.name) / "cli.txt"
        self.file.write_text("x", encoding="utf-8")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_json_success_payload(self) -> None:
        buf = StringIO()
        with mock.patch("airdrop_folder.platform.system", return_value="Darwin"):
            with mock.patch("airdrop_folder.share_via_airdrop") as share:
                with redirect_stdout(buf):
                    code = main(["--json", str(self.file)])
        self.assertEqual(code, 0)
        share.assert_called_once()
        payload = json.loads(buf.getvalue())
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["paths"], [str(self.file.resolve())])

    def test_non_darwin_fails(self) -> None:
        err = StringIO()
        with mock.patch("airdrop_folder.platform.system", return_value="Linux"):
            with redirect_stderr(err):
                code = main([str(self.file)])
        self.assertEqual(code, 1)
        self.assertIn("airdrop-folder:", err.getvalue())
        self.assertIn("macOS only", err.getvalue())

    def test_missing_path_stderr(self) -> None:
        missing = self.file.parent / "nope.txt"
        err = StringIO()
        with mock.patch("airdrop_folder.platform.system", return_value="Darwin"):
            with redirect_stderr(err):
                code = main([str(missing)])
        self.assertEqual(code, 1)
        self.assertIn("airdrop-folder: not found:", err.getvalue())


if __name__ == "__main__":
    unittest.main()
