#!/usr/bin/env python3
"""Per-file VLC audio/subtitle/delay memory: store helpers + install Lua extension."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

_SCRIPT_DIR = Path(__file__).resolve().parent
_LUA_FILENAME = "file_memory.lua"
_STORE_FILENAME = "file_memory_store.json"


def normalize_media_path(uri_or_path: str) -> str:
    """Normalize a file URI or filesystem path for stable store keys.

    ``file:///…`` and ``file://localhost/…`` become absolute paths; percent
    encoding is decoded; trailing slashes are stripped.
    """
    if uri_or_path is None:
        raise ValueError("media path is required")
    text = str(uri_or_path).strip()
    if not text:
        raise ValueError("media path is required")

    if text.lower().startswith("file:"):
        parsed = urlparse(text)
        path = unquote(parsed.path or "")
        # file://host/path → path may already include leading /
        if parsed.netloc and parsed.netloc not in ("", "localhost"):
            # uncommon; keep host in key for uniqueness
            path = f"/{parsed.netloc}{path}"
        text = path

    text = text.replace("\\", "/")
    while len(text) > 1 and text.endswith("/"):
        text = text[:-1]
    if not text:
        raise ValueError("media path is required")
    return text


def hash_path(uri_or_path: str) -> str:
    """SHA-256 hex digest of the normalized media path (diagnostic helper)."""
    normalized = normalize_media_path(uri_or_path)
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def default_vlc_extensions_dir() -> Path:
    """macOS VLC user Lua extensions directory."""
    return (
        Path.home() / "Library" / "Application Support" / "org.videolan.vlc" / "lua" / "extensions"
    )


def default_store_path() -> Path:
    """JSON store path beside installed extensions (VLC Lua can ``io.open`` it)."""
    return default_vlc_extensions_dir() / _STORE_FILENAME


def lua_source_path() -> Path:
    """Path to file_memory.lua shipped next to this script."""
    return _SCRIPT_DIR / _LUA_FILENAME


def load_store(path: Path) -> dict:
    """Load the JSON store; missing or empty file → ``{}``."""
    p = Path(path)
    if not p.is_file():
        return {}
    raw = p.read_text(encoding="utf-8").strip()
    if not raw:
        return {}
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError(f"store root must be an object: {p}")
    return data


def save_store(path: Path, data: dict) -> None:
    """Write the JSON store, creating parent directories as needed."""
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(
        json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def get_entry(store: dict, uri_or_path: str) -> dict | None:
    """Return the saved entry for *uri_or_path*, or ``None``.

    Store object keys are normalized paths (same as the Lua extension).
    """
    key = normalize_media_path(uri_or_path)
    entry = store.get(key)
    if entry is None:
        return None
    if not isinstance(entry, dict):
        return None
    return entry


def set_entry(
    store: dict,
    uri_or_path: str,
    *,
    audio_track: int | None = None,
    spu_track: int | None = None,
    audio_delay: float | None = None,
    subtitle_delay: float | None = None,
) -> str:
    """Upsert memory for *uri_or_path*. Returns the store key (normalized path)."""
    key = normalize_media_path(uri_or_path)
    entry = dict(store.get(key) or {})
    entry["path"] = key
    if audio_track is not None:
        entry["audio_track"] = int(audio_track)
    if spu_track is not None:
        entry["spu_track"] = int(spu_track)
    if audio_delay is not None:
        entry["audio_delay"] = float(audio_delay)
    if subtitle_delay is not None:
        entry["subtitle_delay"] = float(subtitle_delay)
    store[key] = entry
    return key


def install_lua_extension(
    *,
    source: Path | None = None,
    dest_dir: Path | None = None,
    dry_run: bool = False,
) -> Path:
    """Copy file_memory.lua into VLC's lua extensions folder.

    Creates *dest_dir* when not dry-run. Returns the destination file path.
    """
    src = lua_source_path() if source is None else Path(source)
    target_dir = default_vlc_extensions_dir() if dest_dir is None else Path(dest_dir)
    dest = target_dir / _LUA_FILENAME

    if dry_run:
        return dest

    if not src.is_file():
        raise FileNotFoundError(f"Lua extension not found: {src}")

    target_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    return dest


def uninstall_lua_extension(
    *,
    dest_dir: Path | None = None,
    dry_run: bool = False,
) -> Path:
    """Remove file_memory.lua from the VLC extensions folder if present."""
    target_dir = default_vlc_extensions_dir() if dest_dir is None else Path(dest_dir)
    dest = target_dir / _LUA_FILENAME

    if dry_run:
        return dest

    if dest.is_file():
        dest.unlink()
    return dest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Install/uninstall the VLC per-file memory Lua extension, "
            "or print a diagnostic hash of a media path."
        )
    )
    sub = parser.add_subparsers(dest="command", required=True)

    hash_p = sub.add_parser(
        "hash",
        help="print SHA-256 of the normalized path (diagnostic)",
    )
    hash_p.add_argument("path", help="file URI or filesystem path")

    install_p = sub.add_parser(
        "install",
        help="copy file_memory.lua into the macOS VLC lua extensions folder",
    )
    install_p.add_argument(
        "--dry-run",
        action="store_true",
        help="print destination path without copying",
    )

    uninstall_p = sub.add_parser(
        "uninstall",
        help="remove file_memory.lua from the macOS VLC lua extensions folder",
    )
    uninstall_p.add_argument(
        "--dry-run",
        action="store_true",
        help="print destination path without deleting",
    )

    args = parser.parse_args(argv)

    if args.command == "hash":
        try:
            print(hash_path(args.path))
        except ValueError as exc:
            print(f"vlc-file-memory: {exc}", file=sys.stderr)
            return 1
        return 0

    try:
        if args.command == "install":
            dest = install_lua_extension(dry_run=args.dry_run)
        else:
            dest = uninstall_lua_extension(dry_run=args.dry_run)
    except OSError as exc:
        print(f"vlc-file-memory: {exc}", file=sys.stderr)
        return 1

    print(str(dest))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
