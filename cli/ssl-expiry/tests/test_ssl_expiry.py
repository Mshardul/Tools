"""Unit tests for ssl_expiry (math/formatting only; no live network)."""

from __future__ import annotations

import unittest
from datetime import datetime, timezone

from ssl_expiry import days_until_expiry, format_report


class DaysUntilExpiryTests(unittest.TestCase):
    def test_positive_days(self):
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        expiry = datetime(2026, 1, 11, tzinfo=timezone.utc)
        self.assertAlmostEqual(days_until_expiry(expiry, now=now), 10.0)

    def test_negative_when_expired(self):
        now = datetime(2026, 6, 15, 12, 0, tzinfo=timezone.utc)
        expiry = datetime(2026, 6, 10, 12, 0, tzinfo=timezone.utc)
        self.assertAlmostEqual(days_until_expiry(expiry, now=now), -5.0)

    def test_fractional_days(self):
        now = datetime(2026, 1, 1, 0, 0, tzinfo=timezone.utc)
        expiry = datetime(2026, 1, 1, 12, 0, tzinfo=timezone.utc)
        self.assertAlmostEqual(days_until_expiry(expiry, now=now), 0.5)

    def test_naive_expiry_treated_as_utc(self):
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        expiry = datetime(2026, 1, 2)  # naive
        self.assertAlmostEqual(days_until_expiry(expiry, now=now), 1.0)


class FormatReportTests(unittest.TestCase):
    def test_format_line(self):
        expiry = datetime(2026, 12, 1, 0, 0, tzinfo=timezone.utc)
        line = format_report("example.com", 443, expiry, 123.0)
        self.assertEqual(
            line,
            "example.com:443 expires 2026-12-01T00:00:00+00:00 (123 days)",
        )

    def test_format_non_default_port(self):
        expiry = datetime(2027, 1, 1, 0, 0, tzinfo=timezone.utc)
        line = format_report("localhost", 8443, expiry, 10.5)
        self.assertIn("localhost:8443", line)
        self.assertIn("(10.5 days)", line)


if __name__ == "__main__":
    unittest.main()
