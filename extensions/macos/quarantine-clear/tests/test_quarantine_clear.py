"""Unit tests for quarantine_clear (subprocess mocked)."""

from __future__ import annotations

import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from quarantine_clear import check_quarantine, clear_quarantine, resolve_paths


class ResolvePathsTests(unittest.TestCase):
    def test_missing_path_raises(self):
        with self.assertRaises(FileNotFoundError):
            resolve_paths(["/this/path/does/not/exist-quarantine-clear"])


class ClearQuarantineTests(unittest.TestCase):
    def test_removes_attribute(self):
        path = Path("/tmp/fake-quarantined-file")
        with patch("quarantine_clear.subprocess.run") as run:
            run.return_value = MagicMock(returncode=0, stderr="")
            self.assertTrue(clear_quarantine(path))
            run.assert_called_once()
            args = run.call_args[0][0]
            self.assertEqual(args[:3], ["xattr", "-d", "com.apple.quarantine"])
            self.assertEqual(args[3], str(path))

    def test_already_clear_is_false(self):
        path = Path("/tmp/fake-clean-file")
        with patch("quarantine_clear.subprocess.run") as run:
            run.return_value = MagicMock(
                returncode=1,
                stderr="No such xattr: com.apple.quarantine",
            )
            self.assertFalse(clear_quarantine(path))


class CheckQuarantineTests(unittest.TestCase):
    def test_check_set(self):
        path = Path("/tmp/fake-quarantined-file")
        with patch("quarantine_clear.subprocess.run") as run:
            run.return_value = MagicMock(returncode=0, stdout="0000;...", stderr="")
            self.assertTrue(check_quarantine(path))

    def test_check_clear(self):
        path = Path("/tmp/fake-clean-file")
        with patch("quarantine_clear.subprocess.run") as run:
            run.return_value = MagicMock(returncode=1, stdout="", stderr="No such xattr")
            self.assertFalse(check_quarantine(path))


if __name__ == "__main__":
    unittest.main()
