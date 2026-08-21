# Shell escape

**Backlog:** T-071 · `shell-escape`

Escape a string for safe shell use.

## Usage

```bash
cd cli/shell-escape
python3 shell_escape.py 'hello world'
echo 'it is $HOME' | python3 shell_escape.py
python3 shell_escape.py 'x y' -c
```

## Not for

Building full shell commands with multiple arguments (quote each arg separately), or escaping for non-POSIX shells.
