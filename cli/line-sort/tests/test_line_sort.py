import unittest

from line_sort import process_lines


class ProcessLinesTests(unittest.TestCase):
    def test_sort_ascending(self):
        self.assertEqual(process_lines(["c", "a", "b"]), ["a", "b", "c"])

    def test_reverse_after_sort(self):
        self.assertEqual(
            process_lines(["c", "a", "b"], reverse=True),
            ["c", "b", "a"],
        )

    def test_unique_sorted(self):
        self.assertEqual(
            process_lines(["b", "a", "b", "c", "a"], unique=True),
            ["a", "b", "c"],
        )

    def test_unique_and_reverse(self):
        self.assertEqual(
            process_lines(["b", "a", "b"], unique=True, reverse=True),
            ["b", "a"],
        )

    def test_empty(self):
        self.assertEqual(process_lines([]), [])


if __name__ == "__main__":
    unittest.main()
