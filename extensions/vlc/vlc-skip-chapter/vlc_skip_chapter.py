#!/usr/bin/env python3
"""Match chapter titles for VLC auto-skip; install skip_chapter.lua into VLC."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

DEFAULT_PATTERNS: list[str] = ["intro", "credits", "opening", "ending", "outro"]

# Separators allowed after a pattern when using startswith matching.
_START_SEPARATORS = frozenset(" -_.:/()[]")

_SCRIPT_DIR = Path(__file__).resolve().parent
_LUA_FILENAME = "skip_chapter.lua"


def should_skip_chapter(name: str, patterns: list[str] | None = None) -> bool:
    """Return True if chapter *name* should be skipped.

    Matching is case-insensitive. A pattern matches when:
    - the full name equals the pattern,
    - the name starts with the pattern followed by end-of-string or a common
      separator (space, ``-``, ``_``, ``:``, ``.``, ``/``, parentheses/brackets),
    - or the pattern appears as a whole word in the name.
    """
    if name is None:
        return False
    text = name.strip()
    if not text:
        return False

    pats = DEFAULT_PATTERNS if patterns is None else patterns
    lowered = text.lower()

    for raw in pats:
        pat = (raw or "").strip().lower()
        if not pat:
            continue
        if lowered == pat:
            return True
        if lowered.startswith(pat):
            rest = lowered[len(pat) :]
            if not rest or rest[0] in _START_SEPARATORS:
                return True
        if re.search(rf"\b{re.escape(pat)}\b", lowered):
            return True
    return False


def default_vlc_extensions_dir() -> Path:
    """macOS VLC user Lua extensions directory."""
    return (
        Path.home()
        / "Library"
        / "Application Support"
        / "org.videolan.vlc"
        / "lua"
        / "extensions"
    )


def lua_source_path() -> Path:
    """Path to skip_chapter.lua shipped next to this script."""
    return _SCRIPT_DIR / _LUA_FILENAME


def install_lua_extension(
    *,
    source: Path | None = None,
    dest_dir: Path | None = None,
    dry_run: bool = False,
) -> Path:
    """Copy skip_chapter.lua into VLC's lua extensions folder.

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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Check whether a chapter title should be auto-skipped, "
            "or install the VLC Lua extension."
        )
    )
    sub = parser.add_subparsers(dest="command", required=True)

    check_p = sub.add_parser(
        "check",
        help="print skip/keep for a chapter name (exit 0=skip, 1=keep)",
    )
    check_p.add_argument("name", help="chapter title to evaluate")
    check_p.add_argument(
        "--pattern",
        action="append",
        dest="patterns",
        metavar="PATTERN",
        help="skip pattern (repeatable; default: intro, credits, …)",
    )
    check_p.add_argument(
        "--json",
        action="store_true",
        help='print JSON: {"name","decision","patterns"}',
    )

    install_p = sub.add_parser(
        "install",
        help="copy skip_chapter.lua into the macOS VLC lua extensions folder",
    )
    install_p.add_argument(
        "--dry-run",
        action="store_true",
        help="print destination path without copying",
    )

    args = parser.parse_args(argv)

    if args.command == "check":
        patterns = args.patterns if args.patterns else None
        effective = list(patterns) if patterns is not None else list(DEFAULT_PATTERNS)
        skip = should_skip_chapter(args.name, patterns=patterns)
        decision = "skip" if skip else "keep"
        if args.json:
            print(
                json.dumps(
                    {
                        "name": args.name,
                        "decision": decision,
                        "patterns": effective,
                    },
                    ensure_ascii=False,
                )
            )
        else:
            print(decision)
        return 0 if skip else 1

    # install
    try:
        dest = install_lua_extension(dry_run=args.dry_run)
    except OSError as exc:
        print(f"vlc-skip-chapter: {exc}", file=sys.stderr)
        return 1

    print(str(dest))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
