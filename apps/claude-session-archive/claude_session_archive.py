#!/usr/bin/env python3
"""Search and export local Claude Code JSONL sessions."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

PROG = "claude-session-archive"
SUMMARY_MAX = 120
SNIPPET_MAX = 120
SNIPPET_CTX = 40


def default_root() -> Path:
    return Path.home() / ".claude" / "projects"


def discover_sessions(root: Path | str) -> list[Path]:
    """Return all ``*.jsonl`` session files under *root*, sorted by path."""
    root_path = Path(root)
    if not root_path.exists():
        raise FileNotFoundError(f"No such file or directory: {root_path}")
    found: list[Path] = []
    for dirpath, _dirnames, filenames in os.walk(root_path, followlinks=False):
        for name in filenames:
            if not name.endswith(".jsonl"):
                continue
            fp = Path(dirpath) / name
            if fp.is_symlink():
                continue
            if fp.is_file():
                found.append(fp.resolve())
    found.sort(key=lambda p: str(p))
    return found


def _user_text_from_message(message: Any) -> str:
    if not isinstance(message, dict):
        return ""
    content = message.get("content")
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts: list[str] = []
        for part in content:
            if isinstance(part, dict) and part.get("type") == "text":
                text = part.get("text")
                if isinstance(text, str) and text.strip():
                    parts.append(text.strip())
        return "\n".join(parts)
    return ""


def _assistant_text_from_message(message: Any) -> str:
    return _user_text_from_message(message)


def _truncate(text: str, max_len: int) -> str:
    text = " ".join(text.split())
    if len(text) <= max_len:
        return text
    return text[: max_len - 3] + "..."


def session_summary(path: Path | str) -> str:
    """Best-effort title: ``ai-title`` / ``aiTitle``, else first user text."""
    fp = Path(path)
    ai_title = ""
    first_user = ""
    try:
        with fp.open(encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(obj, dict):
                    continue
                typ = obj.get("type")
                if typ == "ai-title" and not ai_title:
                    title = obj.get("aiTitle") or obj.get("title") or ""
                    if isinstance(title, str) and title.strip():
                        ai_title = title.strip()
                elif typ == "user" and not first_user:
                    text = _user_text_from_message(obj.get("message"))
                    if text:
                        first_user = text
                if ai_title and first_user:
                    break
    except OSError:
        return ""
    chosen = ai_title or first_user
    return _truncate(chosen, SUMMARY_MAX) if chosen else ""


def list_sessions(root: Path | str) -> list[dict[str, Any]]:
    """List sessions with path, mtime (ISO), size (bytes), and summary."""
    rows: list[dict[str, Any]] = []
    for path in discover_sessions(root):
        try:
            st = path.stat()
        except OSError:
            continue
        mtime = datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).isoformat()
        rows.append(
            {
                "path": str(path),
                "mtime": mtime,
                "size": st.st_size,
                "summary": session_summary(path),
            }
        )
    rows.sort(key=lambda r: r["mtime"], reverse=True)
    return rows


def _snippet_around(text: str, query: str, max_len: int = SNIPPET_MAX) -> str:
    lower = text.lower()
    q = query.lower()
    idx = lower.find(q)
    if idx < 0:
        return _truncate(text, max_len)
    start = max(0, idx - SNIPPET_CTX)
    end = min(len(text), idx + len(query) + SNIPPET_CTX)
    snippet = text[start:end]
    if start > 0:
        snippet = "..." + snippet
    if end < len(text):
        snippet = snippet + "..."
    return _truncate(snippet, max_len)


def search_sessions(root: Path | str, query: str) -> list[dict[str, Any]]:
    """Case-insensitive substring search across session JSONL text."""
    if not query:
        return []
    q_lower = query.lower()
    results: list[dict[str, Any]] = []
    for path in discover_sessions(root):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if q_lower not in text.lower():
            continue
        results.append(
            {
                "path": str(path),
                "snippet": _snippet_around(text, query),
            }
        )
    return results


def _iter_message_blocks(path: Path) -> list[tuple[str, str]]:
    blocks: list[tuple[str, str]] = []
    try:
        with path.open(encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(obj, dict):
                    continue
                typ = obj.get("type")
                if typ == "user":
                    text = _user_text_from_message(obj.get("message"))
                    if text:
                        blocks.append(("user", text))
                elif typ == "assistant":
                    text = _assistant_text_from_message(obj.get("message"))
                    if text:
                        blocks.append(("assistant", text))
    except OSError:
        pass
    return blocks


def export_session(
    session_path: Path | str,
    out_path: Path | str,
    fmt: str = "jsonl",
) -> None:
    """Copy JSONL or write a markdown summary of *session_path* to *out_path*."""
    src = Path(session_path)
    dest = Path(out_path)
    if not src.is_file():
        raise FileNotFoundError(f"No such file or directory: {src}")

    fmt_norm = fmt.lower().strip()
    if fmt_norm in ("md", "markdown"):
        fmt_norm = "markdown"
    elif fmt_norm != "jsonl":
        raise ValueError(f"unsupported export format: {fmt}")

    dest.parent.mkdir(parents=True, exist_ok=True)

    if fmt_norm == "jsonl":
        shutil.copy2(src, dest)
        return

    title = session_summary(src) or src.stem
    lines = [f"# {title}", "", f"Source: `{src}`", ""]
    for role, text in _iter_message_blocks(src):
        heading = "User" if role == "user" else "Assistant"
        lines.append(f"## {heading}")
        lines.append("")
        lines.append(text)
        lines.append("")
    dest.write_text("\n".join(lines), encoding="utf-8")


def _human_size(n: int) -> str:
    value = float(n)
    for unit in ("B", "KB", "MB", "GB"):
        if value < 1024.0 or unit == "GB":
            if unit == "B":
                return f"{int(value)} B"
            return f"{value:.1f} {unit}"
        value /= 1024.0
    return f"{value:.1f} GB"


def _err(msg: str) -> None:
    print(f"{PROG}: {msg}", file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog=PROG,
        description="Search and export local Claude Code JSONL sessions.",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=None,
        help=f"projects directory (default: {default_root()})",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print structured JSON (for launchers)",
    )

    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="list sessions under --root")

    p_search = sub.add_parser("search", help="case-insensitive substring search")
    p_search.add_argument("query", help="substring to find in session JSONL text")

    p_export = sub.add_parser("export", help="copy or summarize a session file")
    p_export.add_argument("session_path", type=Path, help="path to a .jsonl session")
    p_export.add_argument(
        "-o",
        "--output",
        type=Path,
        required=True,
        dest="output",
        help="output path",
    )
    p_export.add_argument(
        "--format",
        choices=("jsonl", "markdown", "md"),
        default=None,
        help="export format (default: from -o suffix, else jsonl)",
    )

    args = parser.parse_args(argv)
    root = args.root if args.root is not None else default_root()

    try:
        if args.command == "list":
            rows = list_sessions(root)
            if args.json:
                print(json.dumps(rows, ensure_ascii=False))
            else:
                for row in rows:
                    size = _human_size(int(row["size"]))
                    summary = row["summary"] or "(no summary)"
                    print(f"{row['path']}\t{row['mtime']}\t{size}\t{summary}")
            return 0

        if args.command == "search":
            results = search_sessions(root, args.query)
            if args.json:
                print(json.dumps(results, ensure_ascii=False))
            else:
                for row in results:
                    print(f"{row['path']}\t{row['snippet']}")
            return 0

        if args.command == "export":
            fmt = args.format
            if fmt is None:
                suffix = args.output.suffix.lower()
                if suffix in (".md", ".markdown"):
                    fmt = "markdown"
                else:
                    fmt = "jsonl"
            export_session(args.session_path, args.output, fmt=fmt)
            payload = {
                "source": str(Path(args.session_path).resolve()),
                "output": str(Path(args.output).resolve()),
                "format": "markdown" if fmt in ("md", "markdown") else "jsonl",
            }
            if args.json:
                print(json.dumps(payload, ensure_ascii=False))
            else:
                print(payload["output"])
            return 0

    except (OSError, ValueError) as exc:
        _err(str(exc))
        return 1

    _err(f"unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
