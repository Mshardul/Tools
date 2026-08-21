import json
import tempfile
import unittest
from pathlib import Path

from dir_du import dir_usage, human_bytes, main


class HumanBytesTests(unittest.TestCase):
    def test_example(self):
        self.assertEqual(human_bytes(1536), "1.5 KB")
        self.assertEqual(human_bytes(0), "0 B")


class DirUsageTests(unittest.TestCase):
    def test_lists_children_sorted_largest_first(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "small.txt").write_bytes(b"a")
            (root / "big.txt").write_bytes(b"b" * 100)
            nested = root / "nest"
            nested.mkdir()
            (nested / "c.txt").write_bytes(b"c" * 50)
            rows = dir_usage(root)
            names = [name for name, _ in rows]
            self.assertEqual(names, ["big.txt", "nest", "small.txt"])
            self.assertEqual(dict(rows)["big.txt"], 100)
            self.assertEqual(dict(rows)["nest"], 50)
            self.assertEqual(dict(rows)["small.txt"], 1)

    def test_does_not_follow_dir_symlinks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            real = root / "real"
            real.mkdir()
            (real / "payload.bin").write_bytes(b"x" * 80)
            (root / "link").symlink_to(real)
            (root / "keep.txt").write_bytes(b"ok")
            rows = dict(dir_usage(root))
            # symlink dir should not recurse into target; size is 0
            self.assertEqual(rows["keep.txt"], 2)
            self.assertEqual(rows["link"], 0)
            self.assertEqual(rows["real"], 80)

    def test_empty_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(dir_usage(tmp), [])


class MainCliTests(unittest.TestCase):
    def test_max_and_total(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.txt").write_bytes(b"a" * 10)
            (root / "b.txt").write_bytes(b"b" * 20)
            (root / "c.txt").write_bytes(b"c" * 30)
            import io
            from contextlib import redirect_stdout

            buf = io.StringIO()
            with redirect_stdout(buf):
                code = main(["-n", "2", "-b", str(root)])
            self.assertEqual(code, 0)
            lines = buf.getvalue().strip().splitlines()
            self.assertEqual(len(lines), 3)  # 2 rows + TOTAL
            self.assertTrue(lines[-1].endswith("TOTAL"))
            self.assertTrue(lines[-1].startswith("60"))

    def test_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.txt").write_bytes(b"abc")
            import io
            from contextlib import redirect_stdout

            buf = io.StringIO()
            with redirect_stdout(buf):
                code = main(["--json", str(root)])
            self.assertEqual(code, 0)
            data = json.loads(buf.getvalue())
            self.assertEqual(data["total"]["bytes"], 3)
            self.assertEqual(len(data["entries"]), 1)


if __name__ == "__main__":
    unittest.main()
