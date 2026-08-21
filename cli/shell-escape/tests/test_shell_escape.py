import unittest

from shell_escape import escape


class ShellEscapeTests(unittest.TestCase):
    def test_simple_word(self):
        self.assertEqual(escape("hello"), "hello")

    def test_spaces(self):
        self.assertEqual(escape("hello world"), "'hello world'")

    def test_special_chars(self):
        result = escape("it's a $test")
        self.assertTrue(result.startswith("'"))
        self.assertTrue(result.endswith("'"))


if __name__ == "__main__":
    unittest.main()
