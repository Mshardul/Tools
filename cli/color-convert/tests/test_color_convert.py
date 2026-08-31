import unittest

from color_convert import (
    convert_color,
    detect_format,
    format_color,
    hsl_to_rgb,
    parse_color,
    rgb_to_hsl,
)


class ColorConvertTests(unittest.TestCase):
    def test_parse_hex_six(self):
        self.assertEqual(parse_color("#ff8000", "hex"), (255, 128, 0))

    def test_parse_hex_three(self):
        self.assertEqual(parse_color("f80", "hex"), (255, 136, 0))

    def test_parse_rgb_function(self):
        self.assertEqual(parse_color("rgb(255, 128, 0)", "rgb"), (255, 128, 0))

    def test_parse_rgb_commas(self):
        self.assertEqual(parse_color("255,128,0", "rgb"), (255, 128, 0))

    def test_parse_rgb_spaces(self):
        self.assertEqual(parse_color("255 128 0", "rgb"), (255, 128, 0))

    def test_parse_hsl_function(self):
        self.assertEqual(parse_color("hsl(120, 50%, 40%)", "hsl"), (51, 153, 51))

    def test_parse_hsl_commas(self):
        self.assertEqual(parse_color("120,50%,40%", "hsl"), (51, 153, 51))

    def test_detect_hex(self):
        self.assertEqual(detect_format("#ff8000"), "hex")
        self.assertEqual(detect_format("ff8000"), "hex")

    def test_detect_rgb(self):
        self.assertEqual(detect_format("rgb(255, 128, 0)"), "rgb")
        self.assertEqual(detect_format("255,128,0"), "rgb")

    def test_detect_hsl(self):
        self.assertEqual(detect_format("hsl(120, 50%, 40%)"), "hsl")
        self.assertEqual(detect_format("120,50%,40%"), "hsl")

    def test_format_hex(self):
        self.assertEqual(format_color(255, 128, 0, "hex"), "#ff8000")

    def test_format_rgb(self):
        self.assertEqual(format_color(255, 128, 0, "rgb"), "rgb(255, 128, 0)")

    def test_format_hsl(self):
        out = format_color(255, 128, 0, "hsl")
        self.assertTrue(out.startswith("hsl("))
        self.assertIn("%", out)

    def test_rgb_hsl_roundtrip(self):
        r, g, b = 255, 128, 0
        h, s, lum = rgb_to_hsl(r, g, b)
        r2, g2, b2 = hsl_to_rgb(h, s, lum)
        self.assertEqual((r, g, b), (r2, g2, b2))

    def test_convert_hex_to_rgb(self):
        self.assertEqual(convert_color("#ff8000", from_fmt="hex", to_fmt="rgb"), "rgb(255, 128, 0)")

    def test_convert_rgb_to_hex_auto(self):
        self.assertEqual(convert_color("255,128,0", from_fmt=None, to_fmt="hex"), "#ff8000")

    def test_convert_hsl_to_hex(self):
        self.assertEqual(
            convert_color("hsl(120, 50%, 40%)", from_fmt="hsl", to_fmt="hex"),
            "#339933",
        )

    def test_invalid_hex_raises(self):
        with self.assertRaises(ValueError):
            parse_color("gggggg", "hex")

    def test_out_of_range_rgb_raises(self):
        with self.assertRaises(ValueError):
            parse_color("256,0,0", "rgb")


if __name__ == "__main__":
    unittest.main()
