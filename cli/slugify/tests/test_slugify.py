import unittest

from slugify import slugify


class SlugifyTests(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(slugify("Hello World"), "hello-world")

    def test_strips_punctuation(self):
        self.assertEqual(slugify("Hello, World!"), "hello-world")

    def test_collapses_separators(self):
        self.assertEqual(slugify("  foo   bar  "), "foo-bar")

    def test_empty(self):
        self.assertEqual(slugify("@@@"), "")


if __name__ == "__main__":
    unittest.main()
