#!/usr/bin/env python3
"""Warn about large blobs in git history."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

UNITS = ("B", "KB", "MB", "GB", "TB")
DEFAULT_MIN_BYTES = 1_000_000  # 1 MiB-ish (decimal MB label uses 1000? we use 1024)


@dataclass(frozen=True)
class BlobHit:
    oid: str
    size: int
    path: str


def human_bytes(n: int) -> str:
    if n < 0:
        raise ValueError(f"size must be non-negative, got {n}")
    value = float(n)
    for i, unit in enumerate(UNITS):
        if value < 1024.0 or i == len(UNITS) - 1:
            if unit == "B":
                return f"{int(value)} B"
            return f"{value:.1f} {unit}"
        value /= 1024.0
    return f"{value:.1f} TB"  # pragma: no cover


def parse_batch_check_line(line: str) -> tuple[str, str, int, str]:
    """Parse `git cat-file --batch-check` output with rest path.

    Expected shapes:
      blob <oid> <size> [<path>]
      tree <oid> <size>
    """
    parts = line.strip().split(" ", 3)
    if len(parts) < 3:
        raise ValueError(f"bad batch-check line: {line!r}")
    kind, oid, size_s = parts[0], parts[1], parts[2]
    path = parts[3] if len(parts) > 3 else ""
    return kind, oid, int(size_s), path


def _git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        err = (result.stderr or result.stdout or "git failed").strip()
        raise RuntimeError(err)
    return result.stdout


def find_large_blobs(
    repo: Path | str,
    min_bytes: int = DEFAULT_MIN_BYTES,
    limit: int = 20,
) -> list[BlobHit]:
    repo = Path(repo)
    if min_bytes < 0:
        raise ValueError(f"min_bytes must be non-negative, got {min_bytes}")
    if limit < 0:
        raise ValueError(f"limit must be non-negative, got {limit}")
    if limit == 0:
        return []
    if not (repo / ".git").exists() and not _is_git_dir(repo):
        # Allow bare or worktree: ask git
        try:
            _git(repo, "rev-parse", "--git-dir")
        except RuntimeError as exc:
            raise FileNotFoundError(f"not a git repository: {repo}") from exc

    # Map object id -> path (best-effort from rev-list --objects)
    rev_out = _git(repo, "rev-list", "--objects", "--all")
    oid_paths: dict[str, str] = {}
    for line in rev_out.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(" ", 1)
        oid = parts[0]
        path = parts[1] if len(parts) > 1 else ""
        if path and oid not in oid_paths:
            oid_paths[oid] = path

    oids = list(oid_paths.keys()) if oid_paths else []
    if not oids:
        # Still scan all objects if rev-list returned oids without paths
        oids = [line.split(" ", 1)[0] for line in rev_out.splitlines() if line.strip()]

    if not oids:
        return []

    proc = subprocess.run(
        [
            "git",
            "-C",
            str(repo),
            "cat-file",
            "--batch-check=%(objecttype) %(objectname) %(objectsize)",
        ],
        input="\n".join(oids) + "\n",
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "cat-file failed").strip()
        raise RuntimeError(err)

    hits: list[BlobHit] = []
    seen: set[str] = set()
    for line in proc.stdout.splitlines():
        if not line.strip():
            continue
        kind, oid, size, _ = parse_batch_check_line(line)
        if kind != "blob":
            continue
        if size < min_bytes:
            continue
        if oid in seen:
            continue
        seen.add(oid)
        hits.append(BlobHit(oid=oid, size=size, path=oid_paths.get(oid, "")))

    hits.sort(key=lambda h: (-h.size, h.path, h.oid))
    return hits[:limit]


def _is_git_dir(path: Path) -> bool:
    return (path / "HEAD").is_file() and (
        (path / "objects").is_dir() or (path / "commondir").is_file()
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="List large blobs reachable in a git repository's history.",
    )
    parser.add_argument(
        "repo",
        nargs="?",
        default=".",
        help="repository path (default: .)",
    )
    parser.add_argument(
        "-m",
        "--min-bytes",
        type=int,
        default=DEFAULT_MIN_BYTES,
        metavar="N",
        help=f"minimum blob size in bytes (default: {DEFAULT_MIN_BYTES})",
    )
    parser.add_argument(
        "-n",
        "--limit",
        type=int,
        default=20,
        metavar="N",
        help="max results (default: 20)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print JSON array of matches",
    )
    args = parser.parse_args(argv)

    try:
        hits = find_large_blobs(
            Path(args.repo).expanduser(),
            min_bytes=args.min_bytes,
            limit=args.limit,
        )
    except (OSError, ValueError, RuntimeError, FileNotFoundError) as exc:
        print(f"git-large-files: {exc}", file=sys.stderr)
        return 2

    if args.json:
        payload = [
            {
                "oid": h.oid,
                "bytes": h.size,
                "human": human_bytes(h.size),
                "path": h.path,
            }
            for h in hits
        ]
        print(json.dumps(payload, ensure_ascii=False))
        return 0

    for h in hits:
        path = h.path or "(unknown path)"
        print(f"{human_bytes(h.size)}\t{h.oid[:12]}\t{path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
