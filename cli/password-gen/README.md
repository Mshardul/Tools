# Password generator

**Backlog:** T-026 · `password-gen`

Random password with length and charset options.

Not for: storing or syncing passwords (use a password manager).

## Usage

```bash
python3 password_gen.py
python3 password_gen.py -l 32 --no-symbols -c
```

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_password_gen -v
```
