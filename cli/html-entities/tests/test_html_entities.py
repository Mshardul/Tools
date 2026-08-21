import unittest

from html_entities import decode_entities, encode_entities


class HtmlEntitiesTests(unittest.TestCase):
    def test_encode_quotes_and_ampersand(self):
        self.assertEqual(
            encode_entities('<a href="x">&</a>'),
            "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;",
        )

    def test_decode_roundtrip(self):
        text = 'Say "hi" & <bye>'
        self.assertEqual(decode_entities(encode_entities(text)), text)

    def test_decode_named(self):
        self.assertEqual(decode_entities("&lt;"), "<")


if __name__ == "__main__":
    unittest.main()
