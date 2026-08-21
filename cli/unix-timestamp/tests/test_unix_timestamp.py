import unittest

from unix_timestamp import from_unix, to_unix


class UnixTimestampTests(unittest.TestCase):
    def test_from_unix_epoch(self):
        self.assertEqual(from_unix(0), "1970-01-01T00:00:00+00:00")

    def test_to_unix_iso(self):
        self.assertEqual(to_unix("1970-01-01T00:00:00Z"), 0)

    def test_roundtrip(self):
        ts = 1_700_000_000
        parsed = from_unix(ts)
        self.assertEqual(to_unix(parsed), ts)

    def test_rejects_bad_date(self):
        with self.assertRaises(ValueError):
            to_unix("not-a-date")


if __name__ == "__main__":
    unittest.main()
