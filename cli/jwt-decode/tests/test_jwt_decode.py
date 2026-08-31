import unittest

from jwt_decode import decode_jwt


class JwtDecodeTests(unittest.TestCase):
    def test_decode_header_and_payload(self):
        # {"alg":"none"} . {"sub":"123","name":"Ada"} . sig
        token = "eyJhbGciOiJub25lIn0.eyJzdWIiOiIxMjMiLCJuYW1lIjoiQWRhIn0.x"
        result = decode_jwt(token)
        self.assertEqual(result["header"], {"alg": "none"})
        self.assertEqual(result["payload"], {"sub": "123", "name": "Ada"})

    def test_rejects_too_few_parts(self):
        with self.assertRaises(ValueError):
            decode_jwt("only.one")


if __name__ == "__main__":
    unittest.main()
