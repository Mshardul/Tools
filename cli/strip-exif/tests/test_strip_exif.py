"""Unit tests for strip-exif (stdlib only)."""

from __future__ import annotations

import io
import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock

from strip_exif import main, strip_file, strip_image, strip_jpeg, strip_png


def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + chunk_type
        + data
        + struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
    )


def _minimal_png_with_text() -> bytes:
    """1x1 grayscale PNG with a tEXt metadata chunk."""
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = _png_chunk(
        b"IHDR",
        struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0),
    )
    text = _png_chunk(b"tEXt", b"Comment\x00secret metadata")
    # raw filter byte 0 + one gray sample
    idat = _png_chunk(b"IDAT", zlib.compress(b"\x00\xff"))
    iend = _png_chunk(b"IEND", b"")
    return signature + ihdr + text + idat + iend


def _minimal_jpeg_with_app1() -> bytes:
    """Minimal JPEG: SOI, APP1, SOS (empty scan), EOI."""
    app1_payload = b"Exif\x00\x00" + b"FAKE" * 4
    app1_len = len(app1_payload) + 2
    app1 = b"\xff\xe1" + struct.pack(">H", app1_len) + app1_payload
    # SOS: Ls=8, Ns=0 is invalid for real decoders but fine for marker parsing
    sos = b"\xff\xda" + struct.pack(">H", 6) + b"\x00\x00\x00\x00"
    return b"\xff\xd8" + app1 + sos + b"\xff\xd9"


def _minimal_jpeg_with_app0_and_app1() -> bytes:
    jfif = b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
    app0 = b"\xff\xe0" + struct.pack(">H", len(jfif) + 2) + jfif
    app1_payload = b"Exif\x00\x00GPS"
    app1 = b"\xff\xe1" + struct.pack(">H", len(app1_payload) + 2) + app1_payload
    sos = b"\xff\xda" + struct.pack(">H", 6) + b"\x00\x00\x00\x00"
    return b"\xff\xd8" + app0 + app1 + sos + b"\xff\xd9"


class StripJpegTests(unittest.TestCase):
    def test_strips_app1(self):
        raw = _minimal_jpeg_with_app1()
        self.assertIn(b"\xff\xe1", raw)
        out = strip_jpeg(raw)
        self.assertTrue(out.startswith(b"\xff\xd8"))
        self.assertTrue(out.endswith(b"\xff\xd9"))
        self.assertNotIn(b"\xff\xe1", out)
        self.assertIn(b"\xff\xda", out)

    def test_keeps_app0_jfif(self):
        raw = _minimal_jpeg_with_app0_and_app1()
        out = strip_jpeg(raw)
        self.assertIn(b"\xff\xe0", out)
        self.assertIn(b"JFIF", out)
        self.assertNotIn(b"\xff\xe1", out)
        self.assertNotIn(b"Exif", out)


class StripPngTests(unittest.TestCase):
    def test_strips_text_chunk(self):
        raw = _minimal_png_with_text()
        self.assertIn(b"tEXt", raw)
        self.assertIn(b"secret metadata", raw)
        out = strip_png(raw)
        self.assertTrue(out.startswith(b"\x89PNG\r\n\x1a\n"))
        self.assertNotIn(b"tEXt", out)
        self.assertNotIn(b"secret metadata", out)
        self.assertIn(b"IHDR", out)
        self.assertIn(b"IDAT", out)
        self.assertIn(b"IEND", out)

    def test_strips_exif_and_time(self):
        signature = b"\x89PNG\r\n\x1a\n"
        ihdr = _png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0))
        exif = _png_chunk(b"eXIf", b"\x00" * 8)
        time = _png_chunk(b"tIME", struct.pack(">HBBBBB", 2024, 1, 2, 3, 4, 5))
        phys = _png_chunk(b"pHYs", struct.pack(">IIB", 2835, 2835, 1))
        idat = _png_chunk(b"IDAT", zlib.compress(b"\x00\xff"))
        iend = _png_chunk(b"IEND", b"")
        raw = signature + ihdr + exif + time + phys + idat + iend
        out = strip_png(raw)
        self.assertNotIn(b"eXIf", out)
        self.assertNotIn(b"tIME", out)
        self.assertIn(b"pHYs", out)


class StripImageTests(unittest.TestCase):
    def test_detect_jpeg(self):
        raw = _minimal_jpeg_with_app1()
        out = strip_image(raw)
        self.assertNotIn(b"\xff\xe1", out)

    def test_detect_png(self):
        raw = _minimal_png_with_text()
        out = strip_image(raw)
        self.assertNotIn(b"tEXt", out)

    def test_refuse_unknown(self):
        with self.assertRaises(ValueError) as ctx:
            strip_image(b"not an image")
        self.assertIn("jpeg", str(ctx.exception).lower())


class StripFileTests(unittest.TestCase):
    def test_inplace(self):
        raw = _minimal_jpeg_with_app1()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "photo.jpg"
            path.write_bytes(raw)
            result = strip_file(path)
            self.assertEqual(result, path)
            data = path.read_bytes()
            self.assertNotIn(b"\xff\xe1", data)

    def test_to_dest(self):
        raw = _minimal_png_with_text()
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "in.png"
            dest = Path(tmp) / "out.png"
            src.write_bytes(raw)
            result = strip_file(src, dest)
            self.assertEqual(result, dest)
            self.assertIn(b"tEXt", src.read_bytes())
            self.assertNotIn(b"tEXt", dest.read_bytes())


class CliTests(unittest.TestCase):
    def test_cli_inplace(self):
        raw = _minimal_jpeg_with_app1()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.jpg"
            path.write_bytes(raw)
            code = main([str(path)])
            self.assertEqual(code, 0)
            self.assertNotIn(b"\xff\xe1", path.read_bytes())

    def test_cli_json(self):
        raw = _minimal_png_with_text()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.png"
            path.write_bytes(raw)
            buf = io.StringIO()
            with mock.patch("sys.stdout", buf):
                code = main([str(path), "--json"])
            self.assertEqual(code, 0)
            payload = json.loads(buf.getvalue())
            self.assertEqual(payload["format"], "png")
            self.assertEqual(payload["path"], str(path.resolve()))
            self.assertGreater(payload["bytes_in"], payload["bytes_out"])

    def test_cli_refuse_non_image(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "x.txt"
            path.write_text("hello", encoding="utf-8")
            err = io.StringIO()
            with mock.patch("sys.stderr", err):
                code = main([str(path)])
            self.assertEqual(code, 2)
            self.assertTrue(err.getvalue().startswith("strip-exif:"))


if __name__ == "__main__":
    unittest.main()
