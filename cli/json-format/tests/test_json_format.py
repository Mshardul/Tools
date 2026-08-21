import unittest

from json_format import format_json


class JsonFormatTests(unittest.TestCase):
    def test_pretty(self):
        out = format_json('{"a":1,"b":[2]}', mode="pretty")
        self.assertIn("\n", out)
        self.assertIn('"a": 1', out)

    def test_minify(self):
        out = format_json('{\n  "a": 1\n}', mode="minify")
        self.assertEqual(out, '{"a":1}')

    def test_invalid(self):
        with self.assertRaises(ValueError):
            format_json("{nope}", mode="pretty")


if __name__ == "__main__":
    unittest.main()
