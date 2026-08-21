"""Unit tests for vlc_skip_chapter (pure logic + install path, mocked FS)."""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

from vlc_skip_chapter import (
    DEFAULT_PATTERNS,
    default_vlc_extensions_dir,
    install_lua_extension,
    main,
    should_skip_chapter,
)


class ShouldSkipChapterTests(unittest.TestCase):
    def test_defaults_include_expected_patterns(self):
        self.assertEqual(
            DEFAULT_PATTERNS,
            ["intro", "credits", "opening", "ending", "outro"],
        )

    def test_exact_match_case_insensitive(self):
        self.assertTrue(should_skip_chapter("Intro"))
        self.assertTrue(should_skip_chapter("CREDITS"))
        self.assertTrue(should_skip_chapter("opening"))
        self.assertTrue(should_skip_chapter("Ending"))
        self.assertTrue(should_skip_chapter("Outro"))

    def test_keep_normal_chapter_names(self):
        self.assertFalse(should_skip_chapter("Chapter 01"))
        self.assertFalse(should_skip_chapter("Scene 3"))
        self.assertFalse(should_skip_chapter("Part A"))
        self.assertFalse(should_skip_chapter("Introduction"))  # not whole word / variant

    def test_whole_word_match(self):
        self.assertTrue(should_skip_chapter("Opening Credits"))
        self.assertTrue(should_skip_chapter("The Intro"))
        self.assertTrue(should_skip_chapter("Episode Ending Theme"))

    def test_startswith_common_variants(self):
        self.assertTrue(should_skip_chapter("Intro - Episode 1"))
        self.assertTrue(should_skip_chapter("Credits_01"))
        self.assertTrue(should_skip_chapter("Opening: Main"))
        self.assertTrue(should_skip_chapter("Outro.mkv"))
        self.assertTrue(should_skip_chapter("Ending (HD)"))

    def test_custom_patterns(self):
        self.assertTrue(should_skip_chapter("Preview", patterns=["preview"]))
        self.assertFalse(should_skip_chapter("Intro", patterns=["preview"]))

    def test_empty_name_is_keep(self):
        self.assertFalse(should_skip_chapter(""))
        self.assertFalse(should_skip_chapter("   "))

    def test_substring_without_word_boundary_kept(self):
        self.assertFalse(should_skip_chapter("Winterintroduction"))
        self.assertFalse(should_skip_chapter("myintro"))


class DefaultVlcExtensionsDirTests(unittest.TestCase):
    def test_macos_path_under_home(self):
        with mock.patch.object(Path, "home", return_value=Path("/Users/test")):
            got = default_vlc_extensions_dir()
        self.assertEqual(
            got,
            Path(
                "/Users/test/Library/Application Support/"
                "org.videolan.vlc/lua/extensions"
            ),
        )


class InstallLuaExtensionTests(unittest.TestCase):
    def test_dry_run_returns_destination_without_writing(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp) / "extensions"
            src = Path(tmp) / "skip_chapter.lua"
            src.write_text("-- lua\n", encoding="utf-8")
            dest = install_lua_extension(
                source=src, dest_dir=dest_dir, dry_run=True
            )
            self.assertEqual(dest, dest_dir / "skip_chapter.lua")
            self.assertFalse(dest.exists())
            self.assertFalse(dest_dir.exists())

    def test_copies_file_and_creates_dirs(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp) / "org.videolan.vlc" / "lua" / "extensions"
            src = Path(tmp) / "skip_chapter.lua"
            src.write_text("-- skip\n", encoding="utf-8")
            dest = install_lua_extension(
                source=src, dest_dir=dest_dir, dry_run=False
            )
            self.assertTrue(dest.is_file())
            self.assertEqual(dest.read_text(encoding="utf-8"), "-- skip\n")


class MainCheckCliTests(unittest.TestCase):
    def _run(self, argv: list[str]) -> tuple[int, str, str]:
        out = io.StringIO()
        err = io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_check_skip_exit_0(self):
        code, out, err = self._run(["check", "Intro"])
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), "skip")
        self.assertEqual(err, "")

    def test_check_keep_exit_1(self):
        code, out, err = self._run(["check", "Chapter 01"])
        self.assertEqual(code, 1)
        self.assertEqual(out.strip(), "keep")
        self.assertEqual(err, "")

    def test_check_json(self):
        code, out, _ = self._run(["check", "Credits", "--json"])
        self.assertEqual(code, 0)
        payload = json.loads(out)
        self.assertEqual(payload["name"], "Credits")
        self.assertEqual(payload["decision"], "skip")
        self.assertEqual(payload["patterns"], DEFAULT_PATTERNS)

    def test_check_custom_pattern(self):
        code, out, _ = self._run(
            ["check", "Preview", "--pattern", "preview", "--json"]
        )
        self.assertEqual(code, 0)
        payload = json.loads(out)
        self.assertEqual(payload["decision"], "skip")
        self.assertEqual(payload["patterns"], ["preview"])

    def test_install_dry_run_prints_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            dest_dir = (
                home
                / "Library"
                / "Application Support"
                / "org.videolan.vlc"
                / "lua"
                / "extensions"
            )
            with mock.patch(
                "vlc_skip_chapter.default_vlc_extensions_dir",
                return_value=dest_dir,
            ):
                code, out, err = self._run(["install", "--dry-run"])
            self.assertEqual(code, 0)
            self.assertIn(str(dest_dir / "skip_chapter.lua"), out)
            self.assertEqual(err, "")
            self.assertFalse((dest_dir / "skip_chapter.lua").exists())


if __name__ == "__main__":
    unittest.main()
