import json
import unittest
from io import StringIO
from unittest.mock import patch

from json_query import format_result, main, query_json, query_path


class QueryPathTests(unittest.TestCase):
    def test_dot_path(self):
        data = {"foo": {"bar": 1}}
        self.assertEqual(query_path(data, "foo.bar"), 1)
        self.assertEqual(query_path(data, ".foo.bar"), 1)

    def test_index_path(self):
        data = {"items": [{"name": "a"}, {"name": "b"}]}
        self.assertEqual(query_path(data, "items[0].name"), "a")
        self.assertEqual(query_path(data, "items[1].name"), "b")

    def test_root_path(self):
        data = {"a": 1}
        self.assertEqual(query_path(data, ""), data)
        self.assertEqual(query_path(data, "."), data)

    def test_missing_key(self):
        with self.assertRaises(ValueError):
            query_path({"a": 1}, "b")

    def test_index_out_of_range(self):
        with self.assertRaises(ValueError):
            query_path({"items": [1]}, "items[3]")

    def test_bad_path_syntax(self):
        with self.assertRaises(ValueError):
            query_path({"a": 1}, "a[")


class QueryJsonTests(unittest.TestCase):
    def test_query_json_text(self):
        text = '{"users":[{"id":1},{"id":2}]}'
        self.assertEqual(query_json(text, "users[1].id"), 2)

    def test_invalid_json(self):
        with self.assertRaises(ValueError):
            query_json("{nope}", "a")


class FormatResultTests(unittest.TestCase):
    def test_scalar_compact(self):
        self.assertEqual(format_result("hi"), '"hi"')
        self.assertEqual(format_result(3), "3")
        self.assertEqual(format_result(True), "true")
        self.assertEqual(format_result(None), "null")

    def test_object_pretty(self):
        out = format_result({"a": 1})
        self.assertEqual(out, json.dumps({"a": 1}, indent=2, ensure_ascii=False) + "\n")

    def test_array_pretty(self):
        out = format_result([1, 2])
        self.assertEqual(out, json.dumps([1, 2], indent=2, ensure_ascii=False) + "\n")


class MainCliTests(unittest.TestCase):
    def test_main_file(self):
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "data.json"
            path.write_text('{"x":{"y":9}}', encoding="utf-8")
            with patch("sys.stdout", new_callable=StringIO) as out:
                code = main(["x.y", str(path)])
            self.assertEqual(code, 0)
            self.assertEqual(out.getvalue().strip(), "9")

    def test_main_stdin(self):
        with patch("sys.stdin", StringIO('{"a":[10,20]}')):
            with patch("sys.stdout", new_callable=StringIO) as out:
                code = main(["a[1]"])
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue().strip(), "20")

    def test_main_error_exit_2(self):
        with patch("sys.stdin", StringIO("{bad")):
            with patch("sys.stderr", new_callable=StringIO) as err:
                with patch("sys.stdout", new_callable=StringIO):
                    code = main(["a"])
        self.assertEqual(code, 2)
        self.assertIn("json-query:", err.getvalue())


if __name__ == "__main__":
    unittest.main()
