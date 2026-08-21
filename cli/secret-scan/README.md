# Secret scan

**Backlog:** T-076 · `secret-scan`

Scan a file or directory for likely secrets (heuristic regex, not a full Semgrep).

Not for: deep SAST, entropy-only detectors, or redacting/removing secrets from files.

## Usage

```bash
cd cli/secret-scan
python3 secret_scan.py path/to/file.env
python3 secret_scan.py path/to/dir
python3 secret_scan.py --json path/to/dir
```

Exit codes: `0` clean, `1` findings, `2` usage/IO error.

Text findings: `path:line: rule_id: snippet`

## Rules

| id | Pattern |
|---|---|
| `aws-access-key` | `AKIA[0-9A-Z]{16}` |
| `github-pat` | `ghp_[A-Za-z0-9]{36}` or `github_pat_…` |
| `slack-token` | `xox[baprs]-` |
| `private-key` | `-----BEGIN (RSA\|OPENSSH\|EC)? PRIVATE KEY-----` |
| `google-api-key` | `AIza[0-9A-Za-z_-]{35}` |

Dirs skip `.git`, `node_modules`, `__pycache__`, `.venv`, and binary files (null byte in first 8 KiB).

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_secret_scan -v
```
