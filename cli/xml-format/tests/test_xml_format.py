import io
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from xml_format import format_xml, main


class FormatXmlTests(unittest.TestCase):
    def test_pretty(self):
        out = format_xml("<root><a>1</a><b>2</b></root>", mode="pretty")
        self.assertIn("\n", out)
        self.assertIn("  <a>1</a>", out)
        self.assertTrue(out.endswith("\n"))

    def test_minify(self):
        out = format_xml(
            "<root>\n  <a>1</a>\n  <b>2</b>\n</root>\n",
            mode="minify",
        )
        self.assertEqual(out, "<root><a>1</a><b>2</b></root>")

    def test_invalid(self):
        with self.assertRaises(ValueError) as ctx:
            format_xml("<root><unclosed>", mode="pretty")
        self.assertIn("invalid XML", str(ctx.exception))


class MainCliTests(unittest.TestCase):
    def test_file_pretty(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "doc.xml"
            path.write_text("<root><x/></root>", encoding="utf-8")
            buf = io.StringIO()
            with redirect_stdout(buf):
                code = main([str(path)])
            self.assertEqual(code, 0)
            self.assertIn("  <x/>", buf.getvalue())

    def test_stdin_minify(self):
        buf_out = io.StringIO()
        buf_err = io.StringIO()
        with redirect_stdout(buf_out), redirect_stderr(buf_err):
            # stdin via monkeypatch of sys.stdin
            import sys

            old = sys.stdin
            sys.stdin = io.StringIO("<root>\n  <a/>\n</root>")
            try:
                code = main(["-m", "minify"])
            finally:
                sys.stdin = old
        self.assertEqual(code, 0)
        self.assertEqual(buf_out.getvalue().strip(), "<root><a/></root>")

    def test_empty_stdin_exits_2(self):
        import sys

        buf_err = io.StringIO()
        old = sys.stdin
        sys.stdin = io.StringIO("")
        try:
            with redirect_stdout(io.StringIO()), redirect_stderr(buf_err):
                code = main([])
        finally:
            sys.stdin = old
        self.assertEqual(code, 2)
        self.assertTrue(buf_err.getvalue().startswith("xml-format:"))

    def test_bad_xml_prefix(self):
        import sys

        buf_err = io.StringIO()
        old = sys.stdin
        sys.stdin = io.StringIO("<not><valid")
        try:
            with redirect_stdout(io.StringIO()), redirect_stderr(buf_err):
                code = main([])
        finally:
            sys.stdin = old
        self.assertEqual(code, 2)
        self.assertTrue(buf_err.getvalue().startswith("xml-format:"))


if __name__ == "__main__":
    unittest.main()
