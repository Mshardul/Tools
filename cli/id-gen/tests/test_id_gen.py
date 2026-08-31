import unittest

from id_gen import NANOID_ALPHABET, generate_id


class IdGenTests(unittest.TestCase):
    def test_uuid_format(self):
        value = generate_id("uuid")
        parts = value.split("-")
        self.assertEqual(len(parts), 5)
        self.assertEqual(len(value), 36)

    def test_uuid_unique(self):
        self.assertNotEqual(generate_id("uuid"), generate_id("uuid"))

    def test_nanoid_default_length(self):
        value = generate_id("nanoid")
        self.assertEqual(len(value), 21)
        self.assertTrue(all(c in NANOID_ALPHABET for c in value))

    def test_nanoid_custom_length(self):
        value = generate_id("nanoid", length=10)
        self.assertEqual(len(value), 10)

    def test_unknown_type(self):
        with self.assertRaises(ValueError):
            generate_id("nope")


if __name__ == "__main__":
    unittest.main()
