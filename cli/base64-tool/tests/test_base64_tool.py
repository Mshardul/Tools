import unittest

from base64_tool import b64_decode, b64_encode


class Base64ToolTests(unittest.TestCase):
    def test_encode_bytes(self):
        self.assertEqual(b64_encode(b"hi"), "aGk=")

    def test_decode_roundtrip(self):
        raw = b"hello world"
        self.assertEqual(b64_decode(b64_encode(raw)), raw)

    def test_decode_invalid(self):
        with self.assertRaises(ValueError):
            b64_decode("!!!")


if __name__ == "__main__":
    unittest.main()
