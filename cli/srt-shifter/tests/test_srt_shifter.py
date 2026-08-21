import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from srt_shifter import detect_format, main, shift_text


SRT_SAMPLE = """\
1
00:00:01,000 --> 00:00:03,500
Hello world

2
00:00:04,000 --> 00:00:06,000
Second cue
"""

VTT_SAMPLE = """\
WEBVTT

00:00:01.000 --> 00:00:03.500
Hello world

00:00:04.000 --> 00:00:06.000
Second cue
"""


class DetectFormatTests(unittest.TestCase):
    def test_extension_srt(self):
        self.assertEqual(detect_format("subs.srt", ""), "srt")

    def test_extension_vtt(self):
        self.assertEqual(detect_format("subs.vtt", ""), "vtt")

    def test_content_webvtt(self):
        self.assertEqual(detect_format("subs.txt", "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi\n"), "vtt")

    def test_content_srt_fallback(self):
        self.assertEqual(
            detect_format("subs.txt", "1\n00:00:01,000 --> 00:00:02,000\nHi\n"),
            "srt",
        )

    def test_unknown_raises(self):
        with self.assertRaises(ValueError):
            detect_format("subs.txt", "not a subtitle file")


class ShiftSrtTests(unittest.TestCase):
    def test_positive_shift(self):
        out = shift_text(SRT_SAMPLE, 1500, "srt")
        self.assertIn("00:00:02,500 --> 00:00:05,000", out)
        self.assertIn("00:00:05,500 --> 00:00:07,500", out)
        self.assertIn("Hello world", out)
        lines = out.splitlines()
        self.assertIn("1", lines)
        self.assertIn("2", lines)

    def test_negative_shift(self):
        out = shift_text(SRT_SAMPLE, -500, "srt")
        self.assertIn("00:00:00,500 --> 00:00:03,000", out)

    def test_clamp_at_zero(self):
        out = shift_text(SRT_SAMPLE, -5000, "srt")
        self.assertIn("00:00:00,000 --> 00:00:00,000", out)

    def test_preserves_non_timestamp_lines(self):
        out = shift_text(SRT_SAMPLE, 100, "srt")
        self.assertIn("Hello world", out)
        self.assertIn("Second cue", out)


class ShiftVttTests(unittest.TestCase):
    def test_positive_shift(self):
        out = shift_text(VTT_SAMPLE, 1500, "vtt")
        self.assertIn("00:00:02.500 --> 00:00:05.000", out)
        self.assertTrue(out.startswith("WEBVTT"))
        self.assertIn("Hello world", out)

    def test_short_form_mm_ss(self):
        text = "WEBVTT\n\n01:30.000 --> 01:35.500\nHi\n"
        out = shift_text(text, 1000, "vtt")
        self.assertIn("01:31.000 --> 01:36.500", out)

    def test_clamp_at_zero(self):
        out = shift_text(VTT_SAMPLE, -5000, "vtt")
        self.assertIn("00:00:00.000 --> 00:00:00.000", out)


class MainCliTests(unittest.TestCase):
    def test_by_required(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.srt"
            path.write_text(SRT_SAMPLE, encoding="utf-8")
            err = io.StringIO()
            with patch("sys.stderr", err), self.assertRaises(SystemExit) as ctx:
                main([str(path)])
            self.assertEqual(ctx.exception.code, 2)

    def test_overwrite_in_place(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.srt"
            path.write_text(SRT_SAMPLE, encoding="utf-8")
            code = main([str(path), "--by", "1000"])
            self.assertEqual(code, 0)
            text = path.read_text(encoding="utf-8")
            self.assertIn("00:00:02,000 --> 00:00:04,500", text)

    def test_output_stdout(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.srt"
            path.write_text(SRT_SAMPLE, encoding="utf-8")
            out = io.StringIO()
            with patch("sys.stdout", out):
                code = main([str(path), "--by", "1000", "-o", "-"])
            self.assertEqual(code, 0)
            self.assertIn("00:00:02,000 --> 00:00:04,500", out.getvalue())
            # input unchanged
            self.assertEqual(path.read_text(encoding="utf-8"), SRT_SAMPLE)

    def test_output_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "a.srt"
            dest = Path(tmp) / "b.srt"
            src.write_text(SRT_SAMPLE, encoding="utf-8")
            code = main([str(src), "--by", "500", "-o", str(dest)])
            self.assertEqual(code, 0)
            self.assertIn("00:00:01,500 --> 00:00:04,000", dest.read_text(encoding="utf-8"))
            self.assertEqual(src.read_text(encoding="utf-8"), SRT_SAMPLE)

    def test_missing_file(self):
        err = io.StringIO()
        with patch("sys.stderr", err):
            code = main(["/nonexistent/srt-shifter-test.srt", "--by", "100"])
        self.assertEqual(code, 2)
        self.assertTrue(err.getvalue().startswith("srt-shifter:"))

    def test_vtt_by_extension(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.vtt"
            path.write_text(VTT_SAMPLE, encoding="utf-8")
            code = main([str(path), "--by", "1000"])
            self.assertEqual(code, 0)
            self.assertIn("00:00:02.000 --> 00:00:04.500", path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
