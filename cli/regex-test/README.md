# Regex test

**Backlog:** T-070 · `regex-test`

Test a regex pattern against a string.

## Usage

```bash
cd cli/regex-test
python3 regex_test.py '\d+' 'abc123def'
python3 regex_test.py '(?P<user>\w+)@(\w+)' 'a@b.com'
echo 'hello\nworld' | python3 regex_test.py '^world' -m
python3 regex_test.py 'foo' 'bar' --json
```

Exit code is 0 when matched, 1 when not matched, 2 on invalid input or pattern.

## Not for

Replacing text, splitting strings, or running regex across many files (use `grep`/`rg`).
