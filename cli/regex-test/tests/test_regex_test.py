import unittest

from regex_test import test_regex


class RegexTestTests(unittest.TestCase):
    def test_match_basic(self):
        result = test_regex(r"\d+", "abc123def")
        self.assertTrue(result["matched"])
        self.assertEqual(result["match"], "123")
        self.assertEqual(result["span"], [3, 6])
        self.assertEqual(result["groups"], ())

    def test_no_match(self):
        result = test_regex(r"\d+", "abc")
        self.assertFalse(result["matched"])
        self.assertIsNone(result["match"])
        self.assertIsNone(result["span"])

    def test_groups(self):
        result = test_regex(r"(\w+)@(\w+)", "user@example.com")
        self.assertTrue(result["matched"])
        self.assertEqual(result["groups"], ("user", "example"))
        self.assertEqual(result["groupdict"], {})

    def test_named_groups(self):
        result = test_regex(
            r"(?P<user>\w+)@(?P<host>\w+)", "a@b", ignore_case=False
        )
        self.assertEqual(result["groupdict"], {"user": "a", "host": "b"})

    def test_ignore_case(self):
        result = test_regex(r"hello", "HELLO", ignore_case=True)
        self.assertTrue(result["matched"])

    def test_multiline(self):
        result = test_regex(r"^world", "hello\nworld", multiline=True)
        self.assertTrue(result["matched"])

    def test_dotall(self):
        result = test_regex(r"a.b", "a\nb", dotall=True)
        self.assertTrue(result["matched"])

    def test_invalid_pattern_raises(self):
        with self.assertRaises(Exception):
            test_regex("[", "text")


if __name__ == "__main__":
    unittest.main()
