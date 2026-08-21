"""Unit tests for git-large-files."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from git_large_files import find_large_blobs, human_bytes, parse_batch_check_line


class ParseAndFormatTests(unittest.TestCase):
    def test_human_bytes(self) -> None:
        self.assertEqual(human_bytes(512), "512 B")
        self.assertEqual(human_bytes(2048), "2.0 KB")

    def test_parse_blob_line(self) -> None:
        kind, oid, size, path = parse_batch_check_line(
            "blob abc123 1500000 path/to/big.bin"
        )
        self.assertEqual(kind, "blob")
        self.assertEqual(oid, "abc123")
        self.assertEqual(size, 1_500_000)
        self.assertEqual(path, "path/to/big.bin")

    def test_parse_tree_ignored_shape(self) -> None:
        kind, oid, size, path = parse_batch_check_line("tree def456 0")
        self.assertEqual(kind, "tree")
        self.assertEqual(size, 0)
        self.assertEqual(path, "")


class FindLargeBlobsTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name)
        subprocess.run(["git", "init"], cwd=self.repo, check=True, capture_output=True)
        subprocess.run(
            ["git", "config", "user.email", "test@example.com"],
            cwd=self.repo,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Test"],
            cwd=self.repo,
            check=True,
            capture_output=True,
        )
        small = self.repo / "small.txt"
        small.write_text("hi\n", encoding="utf-8")
        big = self.repo / "big.bin"
        big.write_bytes(b"x" * 50_000)
        subprocess.run(["git", "add", "."], cwd=self.repo, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "init"],
            cwd=self.repo,
            check=True,
            capture_output=True,
        )

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_finds_blob_above_threshold(self) -> None:
        hits = find_large_blobs(self.repo, min_bytes=10_000, limit=10)
        self.assertTrue(any(h.path.endswith("big.bin") for h in hits))
        self.assertTrue(all(h.size >= 10_000 for h in hits))

    def test_respects_min_bytes(self) -> None:
        hits = find_large_blobs(self.repo, min_bytes=1_000_000, limit=10)
        self.assertEqual(hits, [])

    def test_sorted_largest_first(self) -> None:
        hits = find_large_blobs(self.repo, min_bytes=1, limit=10)
        sizes = [h.size for h in hits]
        self.assertEqual(sizes, sorted(sizes, reverse=True))


if __name__ == "__main__":
    unittest.main()
