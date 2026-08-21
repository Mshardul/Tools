import tempfile
import unittest
from pathlib import Path

from trash import load_config, resolve_method, resolve_paths


class TrashTests(unittest.TestCase):
    def test_resolve_requires_existing(self):
        with self.assertRaises(FileNotFoundError):
            resolve_paths(["/this/path/does/not/exist-tools-nursery"])

    def test_load_config_method(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "trash.yaml"
            path.write_text("# comment\nmethod: finder\n")
            self.assertEqual(load_config(path)["method"], "finder")

    def test_resolve_method_default_home(self):
        self.assertEqual(resolve_method(cli_method=None, config={}), "home")

    def test_resolve_method_cli_overrides_config(self):
        self.assertEqual(
            resolve_method(cli_method="home", config={"method": "finder"}),
            "home",
        )

    def test_resolve_method_from_config(self):
        self.assertEqual(
            resolve_method(cli_method=None, config={"method": "finder"}),
            "finder",
        )

    def test_resolve_method_rejects_unknown(self):
        with self.assertRaises(ValueError):
            resolve_method(cli_method="nope", config={})


if __name__ == "__main__":
    unittest.main()
