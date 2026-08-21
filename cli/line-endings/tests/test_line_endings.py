import unittest

from line_endings import convert_endings, detect_endings


class LineEndingsTests(unittest.TestCase):
    def test_detect_lf(self):
        self.assertEqual(detect_endings("a\nb\n"), "lf")

    def test_detect_crlf(self):
        self.assertEqual(detect_endings("a\r\nb\r\n"), "crlf")

    def test_detect_mixed(self):
        self.assertEqual(detect_endings("a\nb\r\nc"), "mixed")

    def test_detect_none(self):
        self.assertEqual(detect_endings("no newlines here"), "none")

    def test_detect_empty(self):
        self.assertEqual(detect_endings(""), "none")

    def test_to_lf(self):
        self.assertEqual(convert_endings("a\r\nb\r\n", "to-lf"), "a\nb\n")

    def test_to_crlf(self):
        self.assertEqual(convert_endings("a\nb\n", "to-crlf"), "a\r\nb\r\n")

    def test_to_lf_preserves_no_trailing_newline(self):
        self.assertEqual(convert_endings("a\r\nb", "to-lf"), "a\nb")

    def test_to_lf_preserves_trailing_newline(self):
        self.assertEqual(convert_endings("a\r\nb\r\n", "to-lf"), "a\nb\n")

    def test_to_crlf_from_mixed(self):
        self.assertEqual(convert_endings("a\nb\r\nc", "to-crlf"), "a\r\nb\r\nc")

    def test_check_mode_unchanged(self):
        self.assertEqual(convert_endings("a\nb\n", "check"), "a\nb\n")

    def test_single_lf_only(self):
        self.assertEqual(detect_endings("\n"), "lf")


if __name__ == "__main__":
    unittest.main()
