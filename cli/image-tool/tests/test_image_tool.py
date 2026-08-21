"""Unit tests for image-tool."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from PIL import Image

from image_tool import compress_image, convert_image, resize_image


def _make_png(path: Path, size: tuple[int, int] = (100, 80), color=(255, 0, 0)) -> Path:
    img = Image.new("RGB", size, color)
    img.save(path, format="PNG")
    return path


class ImageToolTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.src = _make_png(self.root / "in.png", (200, 100))

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_resize_by_width(self) -> None:
        out = self.root / "out.png"
        resize_image(self.src, out, width=50, height=None)
        with Image.open(out) as img:
            self.assertEqual(img.size, (50, 25))

    def test_resize_by_height(self) -> None:
        out = self.root / "out.png"
        resize_image(self.src, out, width=None, height=40)
        with Image.open(out) as img:
            self.assertEqual(img.size, (80, 40))

    def test_convert_png_to_jpeg(self) -> None:
        out = self.root / "out.jpg"
        convert_image(self.src, out, fmt="JPEG")
        with Image.open(out) as img:
            self.assertEqual(img.format, "JPEG")

    def test_compress_reduces_size(self) -> None:
        # Larger noisy image so quality drop is measurable.
        noisy = self.root / "noisy.png"
        Image.new("RGB", (400, 400), (128, 64, 32)).save(noisy, format="PNG")
        out = self.root / "out.jpg"
        compress_image(noisy, out, quality=40)
        self.assertTrue(out.is_file())
        self.assertLess(out.stat().st_size, noisy.stat().st_size)

    def test_resize_requires_dimension(self) -> None:
        out = self.root / "out.png"
        with self.assertRaises(ValueError):
            resize_image(self.src, out, width=None, height=None)


if __name__ == "__main__":
    unittest.main()
