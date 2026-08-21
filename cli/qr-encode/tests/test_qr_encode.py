"""Unit tests for qr-encode."""

from __future__ import annotations

import io
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

# Allow importing the leaf module from sibling directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from qr_encode import ascii_qr, main, resolve_text  # noqa: E402

try:
    from PIL import Image  # noqa: F401

    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

# Half-block / full-block glyphs used by qrcode.print_ascii
QR_BLOCK_CHARS = ("█", "▀", "▄", "\u2588", "\u2580", "\u2584")


class AsciiQrTests(unittest.TestCase):
    def test_non_empty_contains_block_characters(self):
        out = ascii_qr("hello")
        self.assertTrue(out.strip(), "ASCII QR should be non-empty")
        self.assertTrue(
            any(ch in out for ch in QR_BLOCK_CHARS),
            f"expected QR block glyphs in output, got: {out!r:.120}",
        )

    def test_empty_text_raises(self):
        with self.assertRaises(ValueError) as ctx:
            ascii_qr("")
        self.assertIn("empty", str(ctx.exception).lower())

    def test_whitespace_only_raises(self):
        with self.assertRaises(ValueError):
            ascii_qr("   \n\t  ")


class ResolveTextTests(unittest.TestCase):
    def test_arg_text(self):
        self.assertEqual(resolve_text("hi", stdin=io.StringIO()), "hi")

    def test_dash_reads_stdin(self):
        self.assertEqual(resolve_text("-", stdin=io.StringIO("from-stdin")), "from-stdin")

    def test_none_reads_stdin(self):
        self.assertEqual(resolve_text(None, stdin=io.StringIO("piped")), "piped")

    def test_empty_stdin_raises(self):
        with self.assertRaises(ValueError):
            resolve_text("-", stdin=io.StringIO(""))


class MainCliTests(unittest.TestCase):
    def test_default_prints_ascii(self):
        buf = io.StringIO()
        err = io.StringIO()
        with redirect_stdout(buf), redirect_stderr(err):
            code = main(["hello"])
        self.assertEqual(code, 0)
        self.assertEqual(err.getvalue(), "")
        self.assertTrue(any(ch in buf.getvalue() for ch in QR_BLOCK_CHARS))

    def test_ascii_flag(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = main(["--ascii", "hi"])
        self.assertEqual(code, 0)
        self.assertTrue(buf.getvalue().strip())

    def test_empty_arg_errors(self):
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(err):
            code = main([""])
        self.assertEqual(code, 2)
        self.assertTrue(err.getvalue().startswith("qr-encode:"))

    def test_stdin_dash(self):
        buf = io.StringIO()
        with mock.patch("sys.stdin", io.StringIO("stdin-data")), redirect_stdout(buf):
            code = main(["-"])
        self.assertEqual(code, 0)
        self.assertTrue(any(ch in buf.getvalue() for ch in QR_BLOCK_CHARS))


@unittest.skipUnless(HAS_PILLOW, "pillow not installed")
class PngCliTests(unittest.TestCase):
    def test_write_png(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.png"
            err = io.StringIO()
            with redirect_stdout(io.StringIO()), redirect_stderr(err):
                code = main(["-o", str(path), "png-payload"])
            self.assertEqual(code, 0)
            self.assertEqual(err.getvalue(), "")
            self.assertTrue(path.is_file())
            self.assertGreater(path.stat().st_size, 0)
            # PNG magic
            self.assertEqual(path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")


if __name__ == "__main__":
    unittest.main()
