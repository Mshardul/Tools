# Git large files

**Backlog:** T-073 · `git-large-files`

List large blobs reachable in a git repository’s history (stdlib + `git`).

```bash
# from repo root
.venv/bin/python cli/git-large-files/git_large_files.py
.venv/bin/python cli/git-large-files/git_large_files.py /path/to/repo -m 500000 -n 10
.venv/bin/python cli/git-large-files/git_large_files.py --json
```

| Flag | Default | Meaning |
|---|---|---|
| `-m` / `--min-bytes` | `1000000` | Minimum blob size |
| `-n` / `--limit` | `20` | Max rows |
| `--json` | off | JSON array of `{oid,bytes,human,path}` |

**Not for:** rewriting history or removing blobs (use `git filter-repo` / BFG). This only reports.
