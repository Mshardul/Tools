import json
import tempfile
import unittest
from pathlib import Path

from big_files import find_big_files, human_bytes, main


class HumanBytesTests(unittest.TestCase):
    def test_example(self):
        self.assertEqual(human_bytes(1536), "1.5 KB")


class FindBigFilesTests(unittest.TestCase):
    def test_finds_largest_n(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.txt").write_bytes(b"a" * 10)
            sub = root / "sub"
            sub.mkdir()
            (sub / "b.txt").write_bytes(b"b" * 50)
            (sub / "c.txt").write_bytes(b"c" * 30)
            results = find_big_files(root, n=2)
            self.assertEqual(len(results), 2)
            self.assertEqual(results[0][1], 50)
            self.assertEqual(results[1][1], 30)
            self.assertEqual(results[0][0].name, "b.txt")

    def test_skips_symlinks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "target.bin"
            target.write_bytes(b"x" * 100)
            link = root / "alias.bin"
            link.symlink_to(target)
            (root / "small.txt").write_bytes(b"y" * 5)
            results = find_big_files(root, n=10)
            names = {p.name for p, _ in results}
            self.assertIn("target.bin", names)
            self.assertNotIn("alias.bin", names)

    def test_does_not_follow_dir_symlinks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            outside = root / "outside"
            outside.mkdir()
            (outside / "huge.bin").write_bytes(b"z" * 200)
            tree = root / "tree"
            tree.mkdir()
            (tree / "tiny.txt").write_bytes(b"t")
            (tree / "linkdir").symlink_to(outside)
            results = find_big_files(tree, n=10)
            self.assertEqual(len(results), 1)
            self.assertEqual(results[0][0].name, "tiny.txt")

    def test_n_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "a.txt").write_bytes(b"a")
            self.assertEqual(find_big_files(tmp, n=0), [])


class MainCliTests(unittest.TestCase):
    def test_bytes_and_count(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.txt").write_bytes(b"a" * 5)
            (root / "b.txt").write_bytes(b"b" * 15)
            import io
            from contextlib import redirect_stdout

            buf = io.StringIO()
            with redirect_stdout(buf):
                code = main(["-n", "1", "-b", str(root)])
            self.assertEqual(code, 0)
            line = buf.getvalue().strip()
            self.assertTrue(line.startswith("15\t"))
            self.assertIn("b.txt", line)

    def test_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.txt").write_bytes(b"hello")
            import io
            from contextlib import redirect_stdout

            buf = io.StringIO()
            with redirect_stdout(buf):
                code = main(["--json", "-n", "5", str(root)])
            self.assertEqual(code, 0)
            data = json.loads(buf.getvalue())
            self.assertEqual(len(data), 1)
            self.assertEqual(data[0]["bytes"], 5)
            self.assertEqual(data[0]["human"], "5 B")


if __name__ == "__main__":
    unittest.main()
