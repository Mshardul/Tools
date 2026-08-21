#!/usr/bin/env python3
"""Chrome Native Messaging host for send-to-downloader.

Protocol: 4-byte little-endian length + UTF-8 JSON on stdin/stdout.
Expects { "action": "add", "url": "...", "title": "..." } and replies
{ "ok": true, "entry": {...} } or { "ok": false, "error": "..." }.
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

# Allow importing sibling CLI when launched via absolute path.
_LEAF = Path(__file__).resolve().parents[1]
if str(_LEAF) not in sys.path:
    sys.path.insert(0, str(_LEAF))

from send_to_downloader import add_entry, resolve_queue_path  # noqa: E402


def read_message() -> dict | None:
    raw_len = sys.stdin.buffer.read(4)
    if not raw_len or len(raw_len) < 4:
        return None
    (length,) = struct.unpack("<I", raw_len)
    data = sys.stdin.buffer.read(length)
    if len(data) < length:
        return None
    return json.loads(data.decode("utf-8"))


def write_message(payload: dict) -> None:
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


def handle(msg: dict) -> dict:
    action = (msg or {}).get("action") or "add"
    if action != "add":
        return {"ok": False, "error": f"unsupported action: {action!r}"}
    url = (msg or {}).get("url") or ""
    title = (msg or {}).get("title") or None
    try:
        queue = resolve_queue_path()
        entry = add_entry(queue, url, title=title)
    except (ValueError, OSError) as exc:
        return {"ok": False, "error": str(exc)}
    return {"ok": True, "entry": entry}


def main() -> int:
    while True:
        try:
            msg = read_message()
        except (json.JSONDecodeError, struct.error) as exc:
            write_message({"ok": False, "error": f"bad message: {exc}"})
            return 1
        if msg is None:
            return 0
        write_message(handle(msg))


if __name__ == "__main__":
    raise SystemExit(main())
