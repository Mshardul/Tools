import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from data_convert import convert, detect_format, dump, load  # noqa: E402

try:
    import yaml  # noqa: F401

    HAS_YAML = True
except ImportError:
    HAS_YAML = False


class DataConvertTests(unittest.TestCase):
    def test_json_env_roundtrip_flat_dict(self):
        text = '{"HOST":"localhost","PORT":"8080"}'
        env = convert(text, "json", "env")
        self.assertIn("HOST=localhost", env)
        self.assertIn("PORT=8080", env)
        back = convert(env, "env", "json")
        self.assertEqual(json.loads(back), {"HOST": "localhost", "PORT": "8080"})

    def test_json_csv_list_of_dicts(self):
        text = '[{"name":"a","n":"1"},{"name":"b","n":"2"}]'
        csv_text = convert(text, "json", "csv")
        self.assertIn("name,n", csv_text.replace(" ", ""))
        self.assertIn("a", csv_text)
        self.assertIn("b", csv_text)
        back = convert(csv_text, "csv", "json")
        rows = json.loads(back)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["name"], "a")
        self.assertEqual(rows[1]["n"], "2")

    def test_json_toml_nested_dict(self):
        text = '{"app":{"name":"demo","port":3000},"debug":true}'
        toml_text = convert(text, "json", "toml")
        self.assertIn("debug", toml_text)
        self.assertIn("app", toml_text)
        back = convert(toml_text, "toml", "json")
        data = json.loads(back)
        self.assertEqual(data["app"]["name"], "demo")
        self.assertEqual(data["app"]["port"], 3000)
        self.assertIs(data["debug"], True)

    def test_invalid_format(self):
        with self.assertRaises(ValueError) as ctx:
            convert("{}", "json", "xml")
        self.assertIn("format", str(ctx.exception).lower())

    def test_invalid_from_format(self):
        with self.assertRaises(ValueError):
            load("{}", "bogus")

    def test_csv_non_tabular_raises(self):
        with self.assertRaises(ValueError):
            dump({"not": "a table"}, "csv")

    def test_env_nested_raises(self):
        with self.assertRaises(ValueError):
            dump({"a": {"b": 1}}, "env")

    def test_detect_format_from_extension(self):
        self.assertEqual(detect_format("foo.json"), "json")
        self.assertEqual(detect_format("foo.yml"), "yaml")
        self.assertEqual(detect_format("foo.yaml"), "yaml")
        self.assertEqual(detect_format("foo.toml"), "toml")
        self.assertEqual(detect_format("foo.csv"), "csv")
        self.assertEqual(detect_format("foo.env"), "env")

    def test_load_dump_json(self):
        data = load('{"x":1}', "json")
        self.assertEqual(data, {"x": 1})
        self.assertEqual(json.loads(dump(data, "json")), {"x": 1})

    @unittest.skipUnless(HAS_YAML, "PyYAML not installed")
    def test_json_yaml_roundtrip(self):
        text = '{"a":1,"b":["c"]}'
        yaml_text = convert(text, "json", "yaml")
        self.assertIn("a:", yaml_text)
        back = convert(yaml_text, "yaml", "json")
        self.assertEqual(json.loads(back), {"a": 1, "b": ["c"]})


if __name__ == "__main__":
    unittest.main()
