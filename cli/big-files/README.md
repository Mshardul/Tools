# Big files

**Backlog:** T-061 · `big-files`

Largest N files under a path (files only; symlinks are skipped and not followed).

Status: active

## Usage

```bash
cd cli/big-files
python3 big_files.py
python3 big_files.py /path/to/tree
python3 big_files.py -n 20 .
python3 big_files.py -b some/dir
python3 big_files.py --json -n 5 .
```

Default path is `.`, default count is 10. Output is `SIZE\tPATH` (human or raw with `-b`), or a JSON array with `--json`.

## Not for

Git blob history (see planned `git-large-files`), directory totals (see `dir-du`), or deleting files.
