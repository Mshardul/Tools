import unittest

from cron_explain import explain


class CronExplainTests(unittest.TestCase):
    def test_every_15_minutes(self):
        self.assertEqual(
            explain("*/15 * * * *"),
            "At every 15th minute past every hour.",
        )

    def test_specific_time(self):
        self.assertEqual(explain("5 4 * * *"), "At 04:05.")

    def test_weekday_range(self):
        self.assertEqual(
            explain("0 22 * * 1-5"),
            "At 22:00 on Monday through Friday.",
        )

    def test_day_of_month(self):
        self.assertEqual(
            explain("15 14 1 * *"),
            "At 14:15 on day-of-month 1.",
        )

    def test_month_name_and_dow_name(self):
        self.assertEqual(
            explain("5 4 * jan sun"),
            "At 04:05 on Sunday in January.",
        )

    def test_step_on_hour_range(self):
        self.assertEqual(
            explain("23 0-20/2 * * *"),
            "At minute 23 past every 2nd hour from 0 through 20.",
        )

    def test_list_of_minutes(self):
        self.assertEqual(
            explain("0,30 * * * *"),
            "At minute 0 and 30 past every hour.",
        )

    def test_dow_zero_and_seven_are_sunday(self):
        self.assertEqual(explain("0 0 * * 0"), "At 00:00 on Sunday.")
        self.assertEqual(explain("0 0 * * 7"), "At 00:00 on Sunday.")

    def test_every_minute(self):
        self.assertEqual(explain("* * * * *"), "At every minute.")

    def test_invalid_field_count(self):
        with self.assertRaises(ValueError):
            explain("* * *")

    def test_invalid_minute(self):
        with self.assertRaises(ValueError):
            explain("60 * * * *")

    def test_invalid_token(self):
        with self.assertRaises(ValueError):
            explain("a * * * *")

    def test_empty(self):
        with self.assertRaises(ValueError):
            explain("")


if __name__ == "__main__":
    unittest.main()
