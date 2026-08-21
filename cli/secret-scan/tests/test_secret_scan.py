import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from secret_scan import RULES, is_binary, main, scan_path, scan_text


class RulesTests(unittest.TestCase):
    def test_rule_ids(self):
        ids = {r["id"] for r in RULES}
        self.assertEqual(
            ids,
            {
                "aws-access-key",
                "github-pat",
                "slack-token",
                "private-key",
                "google-api-key",
            },
        )


class ScanTextTests(unittest.TestCase):
    def test_aws_access_key(self):
        key = "AKIA" + ("A" * 16)
        findings = scan_text(f"cred={key}\n", path="f.env")
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0]["rule"], "aws-access-key")
        self.assertEqual(findings[0]["line"], 1)
        self.assertEqual(findings[0]["match"], key)

    def test_aws_case_sensitive(self):
        findings = scan_text("akia" + ("A" * 16) + "\n", path="f.env")
        self.assertEqual(findings, [])

    def test_github_pat_classic(self):
        tok = "ghp_" + ("a" * 36)
        findings = scan_text(tok + "\n", path="t.txt")
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0]["rule"], "github-pat")
        self.assertEqual(findings[0]["match"], tok)

    def test_github_pat_fine_grained_prefix(self):
        findings = scan_text("token=github_pat_11AAAA\n", path="t.txt")
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0]["rule"], "github-pat")
        self.assertIn("github_pat_", findings[0]["match"])

    def test_slack_token(self):
        findings = scan_text("xoxb-1234567890-abcdefgh\n", path="s.txt")
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0]["rule"], "slack-token")

    def test_private_key_headers(self):
        for header in (
            "-----BEGIN PRIVATE KEY-----",
            "-----BEGIN RSA PRIVATE KEY-----",
            "-----BEGIN OPENSSH PRIVATE KEY-----",
            "-----BEGIN EC PRIVATE KEY-----",
        ):
            with self.subTest(header=header):
                findings = scan_text(header + "\n", path="k.pem")
                self.assertEqual(len(findings), 1)
                self.assertEqual(findings[0]["rule"], "private-key")

    def test_google_api_key(self):
        key = "AIza" + ("0" * 35)
        findings = scan_text(key + "\n", path="g.txt")
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0]["rule"], "google-api-key")
        self.assertEqual(findings[0]["match"], key)

    def test_line_numbers(self):
        text = "ok\n" + ("AKIA" + ("B" * 16)) + "\n"
        findings = scan_text(text, path="m.txt")
        self.assertEqual(findings[0]["line"], 2)

    def test_clean_text(self):
        self.assertEqual(scan_text("hello world\n", path="c.txt"), [])


class BinaryAndWalkTests(unittest.TestCase):
    def test_is_binary_null_in_first_8k(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "bin.dat"
            p.write_bytes(b"abc\x00def")
            self.assertTrue(is_binary(p))
            p2 = Path(tmp) / "text.txt"
            p2.write_text("plain\n", encoding="utf-8")
            self.assertFalse(is_binary(p2))

    def test_scan_path_skips_junk_dirs_and_binary(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "ok.txt").write_text(
                "AKIA" + ("C" * 16) + "\n", encoding="utf-8"
            )
            git = root / ".git"
            git.mkdir()
            (git / "secret").write_text(
                "AKIA" + ("D" * 16) + "\n", encoding="utf-8"
            )
            nm = root / "node_modules" / "pkg"
            nm.mkdir(parents=True)
            (nm / "x.js").write_text(
                "AKIA" + ("E" * 16) + "\n", encoding="utf-8"
            )
            pc = root / "__pycache__"
            pc.mkdir()
            (pc / "m.pyc").write_text(
                "AKIA" + ("F" * 16) + "\n", encoding="utf-8"
            )
            venv = root / ".venv" / "lib"
            venv.mkdir(parents=True)
            (venv / "y.py").write_text(
                "AKIA" + ("G" * 16) + "\n", encoding="utf-8"
            )
            (root / "blob.bin").write_bytes(b"\x00" + b"AKIA" + (b"H" * 16))

            findings = scan_path(root)
            paths = {f["path"] for f in findings}
            self.assertEqual(len(findings), 1)
            self.assertTrue(any(p.endswith("ok.txt") for p in paths))


class MainCliTests(unittest.TestCase):
    def test_exit_0_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "clean.txt"
            p.write_text("nothing here\n", encoding="utf-8")
            out = io.StringIO()
            with redirect_stdout(out):
                code = main([str(p)])
            self.assertEqual(code, 0)
            self.assertEqual(out.getvalue(), "")

    def test_exit_1_findings_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "leak.env"
            key = "AKIA" + ("Z" * 16)
            p.write_text(f"K={key}\n", encoding="utf-8")
            out = io.StringIO()
            with redirect_stdout(out):
                code = main([str(p)])
            self.assertEqual(code, 1)
            line = out.getvalue().strip()
            self.assertIn(":1: aws-access-key:", line)
            self.assertIn(key, line)
            self.assertTrue(line.startswith(str(p)))

    def test_json_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "leak.env"
            key = "AKIA" + ("Y" * 16)
            p.write_text(f"{key}\n", encoding="utf-8")
            out = io.StringIO()
            with redirect_stdout(out):
                code = main(["--json", str(p)])
            self.assertEqual(code, 1)
            data = json.loads(out.getvalue())
            self.assertEqual(len(data), 1)
            self.assertEqual(data[0]["rule"], "aws-access-key")
            self.assertEqual(data[0]["line"], 1)
            self.assertEqual(data[0]["match"], key)
            self.assertEqual(data[0]["path"], str(p))

    def test_missing_path_exit_2(self):
        err = io.StringIO()
        with redirect_stderr(err):
            code = main(["/nonexistent/secret-scan-path-xyz"])
        self.assertEqual(code, 2)
        self.assertIn("secret-scan:", err.getvalue())

    def test_no_args_exit_2(self):
        err = io.StringIO()
        with redirect_stderr(err):
            code = main([])
        self.assertEqual(code, 2)
        self.assertIn("secret-scan:", err.getvalue())


if __name__ == "__main__":
    unittest.main()
