import unittest

from number_base import convert_base, detect_base, normalize_base


class NumberBaseTests(unittest.TestCase):
    def test_normalize_aliases(self):
        self.assertEqual(normalize_base("bin"), "bin")
        self.assertEqual(normalize_base("2"), "bin")
        self.assertEqual(normalize_base("oct"), "oct")
        self.assertEqual(normalize_base("8"), "oct")
        self.assertEqual(normalize_base("dec"), "dec")
        self.assertEqual(normalize_base("10"), "dec")
        self.assertEqual(normalize_base("hex"), "hex")
        self.assertEqual(normalize_base("16"), "hex")

    def test_detect_binary(self):
        self.assertEqual(detect_base("0b1010"), "bin")

    def test_detect_octal(self):
        self.assertEqual(detect_base("0o17"), "oct")

    def test_detect_hex(self):
        self.assertEqual(detect_base("0xFF"), "hex")

    def test_detect_decimal(self):
        self.assertEqual(detect_base("42"), "dec")

    def test_dec_to_hex(self):
        self.assertEqual(convert_base("255", from_base="dec", to_base="hex"), "0xff")

    def test_hex_to_bin(self):
        self.assertEqual(convert_base("0xFF", from_base="hex", to_base="bin"), "0b11111111")

    def test_bin_to_dec(self):
        self.assertEqual(convert_base("0b1010", from_base="bin", to_base="dec"), "10")

    def test_auto_detect_hex(self):
        self.assertEqual(convert_base("0x1A", from_base=None, to_base="dec"), "26")

    def test_underscores_stripped(self):
        self.assertEqual(convert_base("1_000", from_base="dec", to_base="dec"), "1000")

    def test_negative_decimal(self):
        self.assertEqual(convert_base("-42", from_base="dec", to_base="hex"), "-0x2a")

    def test_negative_binary(self):
        self.assertEqual(convert_base("-0b1010", from_base="bin", to_base="dec"), "-10")

    def test_oct_to_hex(self):
        self.assertEqual(convert_base("0o17", from_base="oct", to_base="hex"), "0xf")

    def test_invalid_digit_raises(self):
        with self.assertRaises(ValueError):
            convert_base("0xGG", from_base="hex", to_base="dec")


if __name__ == "__main__":
    unittest.main()
