"""Unit tests for vlc_file_memory (path keying, store, install/uninstall)."""

from __future__ import annotations

import hashlib
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

from vlc_file_memory import (
    default_store_path,
    default_vlc_extensions_dir,
    get_entry,
    hash_path,
    install_lua_extension,
    load_store,
    main,
    normalize_media_path,
    save_store,
    set_entry,
    uninstall_lua_extension,
)


class NormalizeMediaPathTests(unittest.TestCase):
    def test_plain_path_unchanged_shape(self):
        self.assertEqual(
            normalize_media_path("/Movies/show.mkv"),
            "/Movies/show.mkv",
        )

    def test_file_uri_decoded(self):
        self.assertEqual(
            normalize_media_path("file:///Movies/My%20Show.mkv"),
            "/Movies/My Show.mkv",
        )

    def test_file_uri_with_localhost(self):
        self.assertEqual(
            normalize_media_path("file://localhost/tmp/a.mp4"),
            "/tmp/a.mp4",
        )

    def test_strips_trailing_slash_on_file(self):
        # Trailing slash on a file-like URI still normalizes to path without extra slash noise
        self.assertEqual(
            normalize_media_path("file:///Movies/show.mkv/"),
            "/Movies/show.mkv",
        )

    def test_empty_raises(self):
        with self.assertRaises(ValueError):
            normalize_media_path("")
        with self.assertRaises(ValueError):
            normalize_media_path("   ")


class HashPathTests(unittest.TestCase):
    def test_stable_sha256_of_normalized_path(self):
        uri = "file:///Movies/My%20Show.mkv"
        expected = hashlib.sha256(b"/Movies/My Show.mkv").hexdigest()
        self.assertEqual(hash_path(uri), expected)

    def test_same_file_different_forms_same_hash(self):
        a = hash_path("/Movies/show.mkv")
        b = hash_path("file:///Movies/show.mkv")
        self.assertEqual(a, b)


class StoreReadWriteTests(unittest.TestCase):
    def test_load_missing_returns_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "missing.json"
            self.assertEqual(load_store(path), {})

    def test_save_and_load_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "store.json"
            data = {
                "abc": {
                    "path": "/Movies/a.mkv",
                    "audio_track": 1,
                    "spu_track": 2,
                    "audio_delay": 0.1,
                    "subtitle_delay": -0.05,
                }
            }
            save_store(path, data)
            self.assertEqual(load_store(path), data)

    def test_set_and_get_entry_by_path(self):
        store: dict = {}
        key = set_entry(
            store,
            "file:///Movies/a.mkv",
            audio_track=1,
            spu_track=-1,
            audio_delay=0.0,
            subtitle_delay=0.25,
        )
        self.assertEqual(key, "/Movies/a.mkv")
        entry = get_entry(store, "/Movies/a.mkv")
        self.assertIsNotNone(entry)
        assert entry is not None
        self.assertEqual(entry["audio_track"], 1)
        self.assertEqual(entry["spu_track"], -1)
        self.assertEqual(entry["audio_delay"], 0.0)
        self.assertEqual(entry["subtitle_delay"], 0.25)
        self.assertEqual(entry["path"], "/Movies/a.mkv")
        self.assertIn("/Movies/a.mkv", store)

    def test_get_entry_missing_returns_none(self):
        self.assertIsNone(get_entry({}, "/nope.mkv"))

    def test_save_creates_parent_dirs(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "nested" / "dir" / "store.json"
            save_store(path, {"k": {"path": "/x"}})
            self.assertTrue(path.is_file())


class DefaultPathsTests(unittest.TestCase):
    def test_macos_extensions_dir(self):
        with mock.patch.object(Path, "home", return_value=Path("/Users/test")):
            got = default_vlc_extensions_dir()
        self.assertEqual(
            got,
            Path(
                "/Users/test/Library/Application Support/"
                "org.videolan.vlc/lua/extensions"
            ),
        )

    def test_default_store_beside_extensions(self):
        with mock.patch.object(Path, "home", return_value=Path("/Users/test")):
            got = default_store_path()
        self.assertEqual(
            got,
            Path(
                "/Users/test/Library/Application Support/"
                "org.videolan.vlc/lua/extensions/file_memory_store.json"
            ),
        )


class InstallUninstallTests(unittest.TestCase):
    def test_install_dry_run_no_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp) / "extensions"
            src = Path(tmp) / "file_memory.lua"
            src.write_text("-- lua\n", encoding="utf-8")
            dest = install_lua_extension(
                source=src, dest_dir=dest_dir, dry_run=True
            )
            self.assertEqual(dest, dest_dir / "file_memory.lua")
            self.assertFalse(dest.exists())

    def test_install_copies_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp) / "lua" / "extensions"
            src = Path(tmp) / "file_memory.lua"
            src.write_text("-- mem\n", encoding="utf-8")
            dest = install_lua_extension(
                source=src, dest_dir=dest_dir, dry_run=False
            )
            self.assertTrue(dest.is_file())
            self.assertEqual(dest.read_text(encoding="utf-8"), "-- mem\n")

    def test_uninstall_removes_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp) / "extensions"
            dest_dir.mkdir(parents=True)
            target = dest_dir / "file_memory.lua"
            target.write_text("-- x\n", encoding="utf-8")
            removed = uninstall_lua_extension(dest_dir=dest_dir, dry_run=False)
            self.assertEqual(removed, target)
            self.assertFalse(target.exists())

    def test_uninstall_dry_run_keeps_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp) / "extensions"
            dest_dir.mkdir(parents=True)
            target = dest_dir / "file_memory.lua"
            target.write_text("-- x\n", encoding="utf-8")
            removed = uninstall_lua_extension(dest_dir=dest_dir, dry_run=True)
            self.assertEqual(removed, target)
            self.assertTrue(target.exists())

    def test_uninstall_missing_is_ok(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp) / "extensions"
            removed = uninstall_lua_extension(dest_dir=dest_dir, dry_run=False)
            self.assertEqual(removed, dest_dir / "file_memory.lua")


class MainCliTests(unittest.TestCase):
    def _run(self, argv: list[str]) -> tuple[int, str, str]:
        out = io.StringIO()
        err = io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_hash_prints_digest(self):
        code, out, err = self._run(["hash", "/Movies/a.mkv"])
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), hash_path("/Movies/a.mkv"))
        self.assertEqual(err, "")

    def test_install_dry_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp) / "extensions"
            with mock.patch(
                "vlc_file_memory.default_vlc_extensions_dir",
                return_value=dest_dir,
            ):
                code, out, err = self._run(["install", "--dry-run"])
            self.assertEqual(code, 0)
            self.assertIn(str(dest_dir / "file_memory.lua"), out)
            self.assertEqual(err, "")

    def test_uninstall_dry_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp) / "extensions"
            with mock.patch(
                "vlc_file_memory.default_vlc_extensions_dir",
                return_value=dest_dir,
            ):
                code, out, err = self._run(["uninstall", "--dry-run"])
            self.assertEqual(code, 0)
            self.assertIn(str(dest_dir / "file_memory.lua"), out)
            self.assertEqual(err, "")

    def test_stderr_prefix_on_error(self):
        with mock.patch(
            "vlc_file_memory.install_lua_extension",
            side_effect=OSError("boom"),
        ):
            code, out, err = self._run(["install"])
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertTrue(err.startswith("vlc-file-memory:"))
        self.assertIn("boom", err)


if __name__ == "__main__":
    unittest.main()
