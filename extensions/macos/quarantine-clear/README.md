# Quarantine clear

**Backlog:** T-088 · `quarantine-clear`

Clear Gatekeeper quarantine (`com.apple.quarantine`) on one or more paths.

Not for: disabling Gatekeeper globally, signing apps, or non-macOS systems.

## Usage

```bash
python3 quarantine_clear.py ~/Downloads/Some.app
python3 quarantine_clear.py file1 file2
python3 quarantine_clear.py --check ~/Downloads/Some.app
```

`--check` exits `1` if any path still has the quarantine attribute, `0` if all are clear.

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_quarantine_clear -v
```
