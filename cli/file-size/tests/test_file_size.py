import json
import tempfile
import unittest
from pathlib import Path

from file_size import format_path_size, human_bytes, main, path_size_bytes


class HumanBytesTests(unittest.TestCase):
    def test_bytes(self):
        self.assertEqual(human_bytes(0), "0 B")
        self.assertEqual(human_bytes(512), "512 B")

    def test_kilobytes(self):
        self.assertEqual(human_bytes(1536), "1.5 KB")
        self.assertEqual(human_bytes(1024), "1.0 KB")

    def test_larger_units(self):
        self.assertEqual(human_bytes(1024**2), "1.0 MB")
        self.assertEqual(human_bytes(1024**3), "1.0 GB")
        self.assertEqual(human_bytes(1024**4), "1.0 TB")


class PathSizeTests(unittest.TestCase):
    def test_file_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.bin"
            path.write_bytes(b"x" * 100)
            self.assertEqual(path_size_bytes(path), 100)

    def test_directory_sums_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.txt").write_bytes(b"aaa")
            sub = root / "sub"
            sub.mkdir()
            (sub / "b.txt").write_bytes(b"bbbb")
            self.assertEqual(path_size_bytes(root), 7)

    def test_directory_does_not_follow_symlinks(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            real = base / "real"
            real.mkdir()
            (real / "big.bin").write_bytes(b"x" * 50)
            root = base / "root"
            root.mkdir()
            (root / "linkdir").symlink_to(real)
            (root / "plain.txt").write_bytes(b"hi")
            # Should not count real/big.bin via the symlink directory
            self.assertEqual(path_size_bytes(root), 2)

    def test_symlink_to_file_sizes_target(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "target.bin"
            target.write_bytes(b"x" * 42)
            link = root / "alias.bin"
            link.symlink_to(target)
            self.assertEqual(path_size_bytes(link), 42)

    def test_format_path_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "f.bin"
            path.write_bytes(b"x" * 1536)
            self.assertEqual(format_path_size(path), f"1.5 KB\t{path}")

    def test_missing_path(self):
        with self.assertRaises(OSError):
            path_size_bytes("/nonexistent/path/for/file-size-tests")


class MainCliTests(unittest.TestCase):
    def test_bytes_flag(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "f.bin"
            path.write_bytes(b"abc")
            # Capture via return + print is awkward; call functions through main's contract
            # by invoking main and checking exit code; stdout captured with redirect.
            import io
            from contextlib import redirect_stdout

            buf = io.StringIO()
            with redirect_stdout(buf):
                code = main(["-b", str(path)])
            self.assertEqual(code, 0)
            self.assertEqual(buf.getvalue().strip(), "3")

    def test_json_flag(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "f.bin"
            path.write_bytes(b"x" * 1024)
            import io
            from contextlib import redirect_stdout

            buf = io.StringIO()
            with redirect_stdout(buf):
                code = main(["--json", str(path)])
            self.assertEqual(code, 0)
            data = json.loads(buf.getvalue())
            self.assertEqual(data["bytes"], 1024)
            self.assertEqual(data["human"], "1.0 KB")
            self.assertEqual(data["path"], str(path))


if __name__ == "__main__":
    unittest.main()
