import string
import unittest

from password_gen import generate_password


class PasswordGenTests(unittest.TestCase):
    def test_length(self):
        self.assertEqual(len(generate_password(length=16)), 16)

    def test_default_charset_alnum_symbols(self):
        pwd = generate_password(length=64, letters=True, digits=True, symbols=True)
        self.assertTrue(any(c in string.ascii_letters for c in pwd))
        self.assertTrue(any(c in string.digits for c in pwd))

    def test_digits_only(self):
        pwd = generate_password(length=20, letters=False, digits=True, symbols=False)
        self.assertTrue(all(c in string.digits for c in pwd))

    def test_rejects_empty_charset(self):
        with self.assertRaises(ValueError):
            generate_password(letters=False, digits=False, symbols=False)

    def test_rejects_short_length(self):
        with self.assertRaises(ValueError):
            generate_password(length=0)


if __name__ == "__main__":
    unittest.main()
