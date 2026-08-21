import hashlib
import tempfile
import unittest
from pathlib import Path

from file_hash import hash_bytes, hash_file


class FileHashTests(unittest.TestCase):
    def test_hash_bytes_sha256(self):
        data = b"abc"
        expected = hashlib.sha256(data).hexdigest()
        self.assertEqual(hash_bytes(data, "sha256"), expected)

    def test_hash_file(self):
        data = b"file-contents"
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "x.bin"
            path.write_bytes(data)
            self.assertEqual(hash_file(path, "sha256"), hashlib.sha256(data).hexdigest())

    def test_unknown_algo(self):
        with self.assertRaises(ValueError):
            hash_bytes(b"x", "nope")


if __name__ == "__main__":
    unittest.main()
