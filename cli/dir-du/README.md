# Dir disk usage

**Backlog:** T-060 · `dir-du`

Disk usage summary for immediate children of a folder (largest first), plus a TOTAL line.

Status: active

## Usage

```bash
cd cli/dir-du
python3 dir_du.py
python3 dir_du.py /path/to/dir
python3 dir_du.py -n 5 .
python3 dir_du.py -b some/dir
python3 dir_du.py --json .
```

Default directory is `.`. `-n/--max` limits child rows (TOTAL still reflects the full tree of children). Directory symlinks are not followed when summing.

## Not for

Full-tree listings of every nested path (see `big-files` for largest files) or block-accurate `du -B` reporting.
