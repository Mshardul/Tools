#!/usr/bin/env python3
"""Tiny path query on JSON (jq-lite)."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


def _parse_path(path: str) -> list[str | int]:
    path = path.strip()
    if path in ("", "."):
        return []

    # Allow a single leading dot before the first segment.
    if path.startswith("."):
        path = path[1:]
    if path == "":
        return []

    parts: list[str | int] = []
    pos = 0
    while pos < len(path):
        if path[pos] == ".":
            pos += 1
            if pos >= len(path):
                raise ValueError(f"bad path: trailing dot in {path!r}")
            continue
        if path[pos] == "[":
            m = re.match(r"\[(\d+)\]", path[pos:])
            if not m:
                raise ValueError(f"bad path: invalid index at {path[pos:]!r}")
            parts.append(int(m.group(1)))
            pos += m.end()
            continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", path[pos:])
        if not m:
            raise ValueError(f"bad path: unexpected {path[pos:]!r}")
        parts.append(m.group(0))
        pos += m.end()
    return parts


def query_path(data: Any, path: str) -> Any:
    parts = _parse_path(path)
    cur = data
    for part in parts:
        if isinstance(part, int):
            if not isinstance(cur, list):
                raise ValueError(f"cannot index non-array at [{part}]")
            try:
                cur = cur[part]
            except IndexError as exc:
                raise ValueError(f"index out of range: [{part}]") from exc
        else:
            if not isinstance(cur, dict):
                raise ValueError(f"cannot access key {part!r} on non-object")
            if part not in cur:
                raise ValueError(f"missing key: {part!r}")
            cur = cur[part]
    return cur


def query_json(text: str, path: str) -> Any:
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON: {exc}") from exc
    return query_path(data, path)


def format_result(value: Any) -> str:
    if isinstance(value, (dict, list)):
        return json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    return json.dumps(value, ensure_ascii=False)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Query JSON with a simple path (jq-lite).",
    )
    parser.add_argument(
        "path",
        help="dot/index path, e.g. foo.bar or items[0].name",
    )
    parser.add_argument(
        "file",
        nargs="?",
        help="JSON file (default: stdin)",
    )
    args = parser.parse_args(argv)

    try:
        if args.file is not None:
            text = Path(args.file).read_text(encoding="utf-8")
        else:
            text = sys.stdin.read()
        if not text.strip():
            raise ValueError("no input (pass a file or pipe stdin)")
        result = query_json(text, args.path)
        out = format_result(result)
    except (OSError, ValueError) as exc:
        print(f"json-query: {exc}", file=sys.stderr)
        return 2

    if out.endswith("\n"):
        sys.stdout.write(out)
    else:
        print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
