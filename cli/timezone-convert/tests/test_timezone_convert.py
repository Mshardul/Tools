import unittest
from datetime import datetime
from unittest.mock import patch
from zoneinfo import ZoneInfo

from timezone_convert import convert_timezone, parse_datetime


class TimezoneConvertTests(unittest.TestCase):
    def test_parse_iso_with_offset(self):
        dt = parse_datetime("2026-08-21T10:00:00+00:00")
        self.assertEqual(dt.hour, 10)
        self.assertIsNotNone(dt.tzinfo)

    def test_parse_iso_naive(self):
        dt = parse_datetime("2026-08-21T10:00:00")
        self.assertEqual(dt.hour, 10)
        self.assertIsNone(dt.tzinfo)

    def test_parse_space_separated(self):
        dt = parse_datetime("2026-08-21 10:00:00")
        self.assertEqual(dt.year, 2026)
        self.assertEqual(dt.hour, 10)
        self.assertIsNone(dt.tzinfo)

    def test_parse_space_separated_with_seconds(self):
        dt = parse_datetime("2026-08-21 10:00:30")
        self.assertEqual(dt.second, 30)

    def test_convert_naive_utc_to_ist(self):
        out = convert_timezone(
            "2026-08-21T10:00:00",
            from_tz="UTC",
            to_tz="Asia/Kolkata",
        )
        self.assertIn("+05:30", out)
        self.assertIn("15:30:00", out)

    def test_convert_aware_preserves_instant(self):
        out = convert_timezone(
            "2026-08-21T10:00:00+00:00",
            from_tz="UTC",
            to_tz="America/New_York",
        )
        self.assertTrue(out.endswith("-04:00") or out.endswith("-05:00"))
        self.assertIn("T", out)

    def test_convert_space_format(self):
        out = convert_timezone(
            "2026-08-21 10:00:00",
            from_tz="UTC",
            to_tz="Asia/Kolkata",
        )
        self.assertIn("15:30:00", out)

    @patch("timezone_convert.datetime")
    def test_convert_now(self, mock_datetime):
        fixed = datetime(2026, 8, 21, 10, 0, 0, tzinfo=ZoneInfo("UTC"))
        mock_datetime.now.return_value = fixed
        mock_datetime.fromisoformat = datetime.fromisoformat
        out = convert_timezone("now", from_tz="UTC", to_tz="Asia/Kolkata")
        self.assertIn("15:30:00", out)

    def test_invalid_zone_raises(self):
        with self.assertRaises(ValueError):
            convert_timezone("2026-08-21T10:00:00", from_tz="UTC", to_tz="Not/AZone")

    def test_invalid_datetime_raises(self):
        with self.assertRaises(ValueError):
            parse_datetime("not-a-date")


if __name__ == "__main__":
    unittest.main()
