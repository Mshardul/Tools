import unittest

from url_encode import url_decode, url_encode


class UrlEncodeTests(unittest.TestCase):
    def test_encode_spaces(self):
        self.assertEqual(url_encode("a b"), "a%20b")

    def test_decode_roundtrip(self):
        text = "hello world/&?"
        self.assertEqual(url_decode(url_encode(text)), text)

    def test_decode_plus_as_space(self):
        self.assertEqual(url_decode("a+b"), "a b")


if __name__ == "__main__":
    unittest.main()
