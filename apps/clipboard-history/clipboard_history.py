#!/usr/bin/env python3
"""Local searchable clipboard history with pins (CLI; sqlite store)."""

from __future__ import annotations

import argparse
import json
import platform
import sqlite3
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable, TextIO

MAX_TEXT_BYTES = 200_000  # ~200KB
DEFAULT_POLL_INTERVAL = 1.0
PROG = "clipboard-history"


def default_db_path() -> Path:
    """Prefer XDG-ish share path; fall back to ~/.config/tools/..."""
    share = Path.home() / ".local" / "share" / "tools" / "clipboard-history" / "history.db"
    return share


def _err(msg: str, err: TextIO = sys.stderr) -> None:
    print(f"{PROG}: {msg}", file=err)


def clipboard_read() -> str:
    result = subprocess.run(["pbpaste"], check=True, capture_output=True)
    return result.stdout.decode(errors="replace")


def clipboard_write(text: str) -> None:
    subprocess.run(["pbcopy"], input=text.encode(), check=True)


class HistoryStore:
    """SQLite-backed clipboard history."""

    def __init__(self, db_path: Path | str) -> None:
        self.path = Path(db_path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(self.path))
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._init_schema()

    def _init_schema(self) -> None:
        self._conn.execute(
            """
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts REAL NOT NULL,
                text TEXT NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        self._conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_entries_ts ON entries(ts DESC)"
        )
        self._conn.commit()

    def close(self) -> None:
        self._conn.close()

    def _row_to_dict(self, row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": int(row["id"]),
            "ts": float(row["ts"]),
            "text": str(row["text"]),
            "pinned": bool(row["pinned"]),
        }

    def add(self, text: str, *, ts: float | None = None) -> int | None:
        """Insert text unless consecutive duplicate or over size limit.

        Returns entry id, or None if skipped.
        """
        if len(text.encode("utf-8")) > MAX_TEXT_BYTES:
            return None
        when = time.time() if ts is None else float(ts)
        last = self._conn.execute(
            "SELECT id, text FROM entries ORDER BY id DESC LIMIT 1"
        ).fetchone()
        if last is not None and last["text"] == text:
            return int(last["id"])
        cur = self._conn.execute(
            "INSERT INTO entries (ts, text, pinned) VALUES (?, ?, 0)",
            (when, text),
        )
        self._conn.commit()
        return int(cur.lastrowid)

    def get(self, entry_id: int) -> dict[str, Any]:
        row = self._conn.execute(
            "SELECT id, ts, text, pinned FROM entries WHERE id = ?",
            (entry_id,),
        ).fetchone()
        if row is None:
            raise KeyError(entry_id)
        return self._row_to_dict(row)

    def list_entries(self, *, limit: int | None = None) -> list[dict[str, Any]]:
        sql = "SELECT id, ts, text, pinned FROM entries ORDER BY ts DESC, id DESC"
        params: tuple[Any, ...] = ()
        if limit is not None:
            sql += " LIMIT ?"
            params = (int(limit),)
        rows = self._conn.execute(sql, params).fetchall()
        return [self._row_to_dict(r) for r in rows]

    def search(self, query: str, *, limit: int | None = None) -> list[dict[str, Any]]:
        pattern = f"%{query}%"
        sql = (
            "SELECT id, ts, text, pinned FROM entries "
            "WHERE text LIKE ? COLLATE NOCASE "
            "ORDER BY ts DESC, id DESC"
        )
        params: list[Any] = [pattern]
        if limit is not None:
            sql += " LIMIT ?"
            params.append(int(limit))
        rows = self._conn.execute(sql, params).fetchall()
        return [self._row_to_dict(r) for r in rows]

    def pin(self, entry_id: int) -> None:
        self.get(entry_id)  # raises KeyError if missing
        self._conn.execute(
            "UPDATE entries SET pinned = 1 WHERE id = ?", (entry_id,)
        )
        self._conn.commit()

    def unpin(self, entry_id: int) -> None:
        self.get(entry_id)
        self._conn.execute(
            "UPDATE entries SET pinned = 0 WHERE id = ?", (entry_id,)
        )
        self._conn.commit()

    def list_pins(self) -> list[dict[str, Any]]:
        rows = self._conn.execute(
            "SELECT id, ts, text, pinned FROM entries "
            "WHERE pinned = 1 ORDER BY ts DESC, id DESC"
        ).fetchall()
        return [self._row_to_dict(r) for r in rows]


def watch_clipboard(
    store: HistoryStore,
    *,
    interval: float = DEFAULT_POLL_INTERVAL,
    read_fn: Callable[[], str] = clipboard_read,
    sleep_fn: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.time,
) -> None:
    """Poll pasteboard and append new text until interrupted."""
    while True:
        text = read_fn()
        store.add(text, ts=clock())
        sleep_fn(interval)


def _format_entry_line(entry: dict[str, Any]) -> str:
    pin = "*" if entry["pinned"] else " "
    preview = entry["text"].replace("\n", "\\n")
    if len(preview) > 80:
        preview = preview[:77] + "..."
    return f"{entry['id']:>6}{pin}  {entry['ts']:.0f}  {preview}"


def _print_entries(
    entries: list[dict[str, Any]],
    *,
    as_json: bool,
    out: TextIO,
) -> None:
    if as_json:
        print(json.dumps(entries, ensure_ascii=False), file=out)
        return
    for e in entries:
        print(_format_entry_line(e), file=out)


def main(
    argv: list[str] | None = None,
    *,
    out: TextIO = sys.stdout,
    err: TextIO = sys.stderr,
    clipboard_write_fn: Callable[[str], None] | None = None,
    clipboard_read_fn: Callable[[], str] | None = None,
    sleep_fn: Callable[[float], None] = time.sleep,
) -> int:
    parser = argparse.ArgumentParser(
        prog=PROG,
        description="Local searchable clipboard history with pins.",
    )
    parser.add_argument(
        "--db",
        type=Path,
        default=None,
        help=f"sqlite db path (default: {default_db_path()})",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="JSON output where useful",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_watch = sub.add_parser(
        "watch",
        help="poll pasteboard and store text (macOS pbpaste by default)",
    )
    p_watch.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_POLL_INTERVAL,
        help=f"poll interval seconds (default: {DEFAULT_POLL_INTERVAL})",
    )

    p_list = sub.add_parser("list", help="list recent entries")
    p_list.add_argument("--limit", type=int, default=50, help="max entries (default: 50)")

    p_search = sub.add_parser("search", help="substring search (case-insensitive)")
    p_search.add_argument("query", help="search string")
    p_search.add_argument("--limit", type=int, default=None, help="max hits")

    p_pin = sub.add_parser("pin", help="pin an entry by id")
    p_pin.add_argument("id", type=int, help="entry id")

    p_unpin = sub.add_parser("unpin", help="unpin an entry by id")
    p_unpin.add_argument("id", type=int, help="entry id")

    sub.add_parser("pins", help="list pinned entries")

    p_get = sub.add_parser("get", help="print entry text by id")
    p_get.add_argument("id", type=int, help="entry id")

    p_copy = sub.add_parser("copy", help="copy entry text to pasteboard (macOS pbcopy)")
    p_copy.add_argument("id", type=int, help="entry id")

    args = parser.parse_args(argv)
    db_path = args.db if args.db is not None else default_db_path()
    write_fn = clipboard_write_fn or clipboard_write
    read_fn = clipboard_read_fn or clipboard_read

    store = HistoryStore(db_path)
    try:
        try:
            if args.command == "watch":
                if (
                    clipboard_read_fn is None
                    and platform.system() != "Darwin"
                ):
                    _err(
                        "watch uses pbpaste by default (Darwin); "
                        "inject read_fn for other platforms",
                        err,
                    )
                    return 1
                try:
                    watch_clipboard(
                        store,
                        interval=args.interval,
                        read_fn=read_fn,
                        sleep_fn=sleep_fn,
                    )
                except KeyboardInterrupt:
                    return 0
                except FileNotFoundError:
                    _err("pbpaste not found (macOS only)", err)
                    return 1
                except subprocess.CalledProcessError as exc:
                    _err(str(exc), err)
                    return 1
                return 0

            if args.command == "list":
                entries = store.list_entries(limit=args.limit)
                _print_entries(entries, as_json=args.json, out=out)
                return 0

            if args.command == "search":
                entries = store.search(args.query, limit=args.limit)
                _print_entries(entries, as_json=args.json, out=out)
                return 0

            if args.command == "pin":
                store.pin(args.id)
                if args.json:
                    print(json.dumps(store.get(args.id), ensure_ascii=False), file=out)
                return 0

            if args.command == "unpin":
                store.unpin(args.id)
                if args.json:
                    print(json.dumps(store.get(args.id), ensure_ascii=False), file=out)
                return 0

            if args.command == "pins":
                entries = store.list_pins()
                _print_entries(entries, as_json=args.json, out=out)
                return 0

            if args.command == "get":
                entry = store.get(args.id)
                if args.json:
                    print(json.dumps(entry, ensure_ascii=False), file=out)
                else:
                    out.write(entry["text"])
                    if not entry["text"].endswith("\n"):
                        # get prints raw text; no forced trailing newline if none
                        pass
                return 0

            if args.command == "copy":
                entry = store.get(args.id)
                try:
                    write_fn(entry["text"])
                except FileNotFoundError:
                    _err("pbcopy not found (macOS only)", err)
                    return 1
                except subprocess.CalledProcessError as exc:
                    _err(str(exc), err)
                    return 1
                if args.json:
                    print(
                        json.dumps({"id": entry["id"], "copied": True}),
                        file=out,
                    )
                return 0

            _err(f"unknown command: {args.command}", err)
            return 1
        except KeyError as exc:
            _err(f"no entry with id {exc.args[0]}", err)
            return 1
        except ValueError as exc:
            _err(str(exc), err)
            return 1
    finally:
        store.close()


if __name__ == "__main__":
    raise SystemExit(main())
