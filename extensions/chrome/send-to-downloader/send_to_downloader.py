#!/usr/bin/env python3
"""Queue tab URLs for the local youtube-downloader workflow."""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

SLUG = "send-to-downloader"
DEFAULT_QUEUE_PATH = Path.home() / ".config" / "tools" / "send-to-downloader" / "queue.jsonl"
DEFAULT_CONFIG_PATH = Path.home() / ".config" / "tools" / "send-to-downloader.yaml"
ENV_CONFIG = "TOOLS_SEND_TO_DOWNLOADER_CONFIG"


def validate_url(url: str) -> str:
    """Return a cleaned http(s) URL or raise ValueError."""
    cleaned = (url or "").strip()
    if not cleaned:
        raise ValueError("URL is required")
    parsed = urlparse(cleaned)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise ValueError(f"URL must be http(s) with a host, got {cleaned!r}")
    return cleaned


def load_config(path: Path) -> dict[str, str]:
    """Load a flat key: value YAML subset (no PyYAML dependency)."""
    if not path.is_file():
        return {}
    data: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or ":" not in line:
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip("\"'")
    return data


def config_path_from_env() -> Path:
    override = os.environ.get(ENV_CONFIG)
    if override:
        return Path(override).expanduser()
    return DEFAULT_CONFIG_PATH


def resolve_queue_path(
    *,
    cli_queue: Path | None = None,
    cli_config: Path | None = None,
) -> Path:
    """Resolve queue file: --queue > config queue key > default."""
    if cli_queue is not None:
        return Path(cli_queue).expanduser()
    cfg_path = Path(cli_config).expanduser() if cli_config else config_path_from_env()
    config = load_config(cfg_path)
    if "queue" in config and config["queue"]:
        return Path(config["queue"]).expanduser()
    return DEFAULT_QUEUE_PATH


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def add_entry(
    queue_path: Path,
    url: str,
    *,
    title: str | None = None,
    ts: str | None = None,
) -> dict:
    """Validate URL and append one JSONL record. Returns the entry."""
    cleaned = validate_url(url)
    entry: dict = {
        "url": cleaned,
        "ts": ts if ts is not None else _now_iso(),
    }
    if title is not None and title.strip():
        entry["title"] = title.strip()
    queue_path = Path(queue_path).expanduser()
    queue_path.parent.mkdir(parents=True, exist_ok=True)
    with queue_path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, ensure_ascii=False, sort_keys=True) + "\n")
    return entry


def list_entries(queue_path: Path) -> list[dict]:
    """Return pending queue entries (skip blank/invalid lines)."""
    path = Path(queue_path).expanduser()
    if not path.is_file():
        return []
    entries: list[dict] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict) and "url" in obj:
            entries.append(obj)
    return entries


def drain_queue(queue_path: Path, *, keep: bool = False) -> list[dict]:
    """Return pending entries; clear the queue unless keep is True."""
    path = Path(queue_path).expanduser()
    entries = list_entries(path)
    if not keep:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("", encoding="utf-8")
    return entries


def _print_entries(entries: list[dict], *, as_json: bool) -> None:
    if as_json:
        print(json.dumps(entries, ensure_ascii=False, sort_keys=True))
        return
    for entry in entries:
        url = entry.get("url", "")
        title = entry.get("title")
        if title:
            print(f"{url}\t{title}")
        else:
            print(url)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Queue page URLs for the local youtube-downloader workflow "
            "(Chrome extension / native host companion)."
        ),
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=None,
        help=f"YAML config path (default: {DEFAULT_CONFIG_PATH} or ${ENV_CONFIG})",
    )
    parser.add_argument(
        "--queue",
        type=Path,
        default=None,
        help=f"queue JSONL path (default: {DEFAULT_QUEUE_PATH} or config queue:)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print structured JSON on stdout",
    )

    sub = parser.add_subparsers(dest="command", required=True)

    add_p = sub.add_parser("add", help="append a URL to the queue")
    add_p.add_argument("url", help="http(s) URL to queue")
    add_p.add_argument("--title", default=None, help="optional page title")

    sub.add_parser("list", help="print pending queue entries")

    drain_p = sub.add_parser("drain", help="print pending URLs and clear the queue")
    drain_p.add_argument(
        "--keep",
        action="store_true",
        help="print without clearing",
    )

    args = parser.parse_args(argv)

    try:
        queue = resolve_queue_path(cli_queue=args.queue, cli_config=args.config)
        if args.command == "add":
            entry = add_entry(queue, args.url, title=args.title)
            if args.json:
                print(json.dumps(entry, ensure_ascii=False, sort_keys=True))
            else:
                print(entry["url"])
        elif args.command == "list":
            _print_entries(list_entries(queue), as_json=args.json)
        else:
            _print_entries(drain_queue(queue, keep=args.keep), as_json=args.json)
    except ValueError as exc:
        print(f"{SLUG}: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"{SLUG}: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
