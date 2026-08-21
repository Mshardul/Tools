# File hasher

**Backlog:** T-013 · `file-hash`

SHA-256 (and md5 / sha1 / sha512) of a file, string, or stdin.

## Usage

```bash
cd cli/file-hash
python3 file_hash.py README.md
python3 file_hash.py -a sha1 README.md
python3 file_hash.py -s 'abc'
echo -n 'abc' | python3 file_hash.py
python3 file_hash.py -s 'abc' -c
```

## Not for

Incremental checksum databases, signing, or comparing two trees (use `diff` / dedicated tools).
