# Line endings

**Backlog:** T-062 · `line-endings`

Convert CRLF ↔ LF for a file or stdin/stdout.

## Usage

```bash
cd cli/line-endings
python3 line_endings.py -m check myfile.txt
python3 line_endings.py -m to-lf myfile.txt
python3 line_endings.py -m to-crlf myfile.txt --stdout
printf 'a\r\nb\r\n' | python3 line_endings.py -m to-lf
```

## Not for

Binary files or encoding detection beyond UTF-8 text.
