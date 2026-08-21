# File size

**Backlog:** T-059 · `file-size`

Human-readable size of a file or directory tree (1024-based units).

Status: active

## Usage

```bash
cd cli/file-size
python3 file_size.py README.md
python3 file_size.py -b some/dir
python3 file_size.py --json path/to/file
```

Output is `HUMAN\tPATH` by default, a raw integer with `-b/--bytes`, or JSON with `--json`.

Directories sum nested file sizes without following symlinks. A symlink path to a file is sized via the target once.

## Not for

Interactive disk maps, inode quotas, or block-level `du` accounting on networked filesystems.
