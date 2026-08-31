#!/usr/bin/env python3
"""Open AirDrop sharing for one or more files/folders (macOS)."""

from __future__ import annotations

import argparse
import json
import platform
import subprocess
import sys
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Any

SLUG = "airdrop-folder"
AIRDROP_APP = "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"

Runner = Callable[..., Any]


def resolve_paths(paths: Sequence[str]) -> list[Path]:
    if not paths:
        raise ValueError("at least one path is required")
    resolved: list[Path] = []
    for raw in paths:
        path = Path(raw).expanduser().resolve()
        if not path.exists():
            raise FileNotFoundError(raw)
        resolved.append(path)
    return resolved


def applescript_quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def build_finder_select_script(paths: Sequence[Path]) -> str:
    """AppleScript: reveal + select paths in Finder (for AirDrop sharing)."""
    posix_list = ", ".join(f'(POSIX file "{applescript_quote(str(p))}")' for p in paths)
    return (
        'tell application "Finder"\n'
        "  activate\n"
        f"  set theItems to {{{posix_list}}}\n"
        "  reveal theItems\n"
        "  select theItems\n"
        "end tell"
    )


def build_open_airdrop_argv() -> list[str]:
    return ["open", AIRDROP_APP]


def share_via_airdrop(
    paths: Sequence[Path],
    *,
    runner: Runner = subprocess.run,
) -> None:
    """Select paths in Finder, then open the AirDrop window."""
    script = build_finder_select_script(paths)
    result = runner(
        ["osascript", "-e", script],
        capture_output=True,
        text=True,
    )
    if getattr(result, "returncode", 0) != 0:
        err = (
            getattr(result, "stderr", None) or getattr(result, "stdout", None) or "osascript failed"
        )
        raise RuntimeError(str(err).strip())

    result = runner(
        build_open_airdrop_argv(),
        capture_output=True,
        text=True,
    )
    if getattr(result, "returncode", 0) != 0:
        err = getattr(result, "stderr", None) or getattr(result, "stdout", None) or "open failed"
        raise RuntimeError(str(err).strip())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Open AirDrop and select files/folders in Finder (Finder Quick Action helper)."
        ),
    )
    parser.add_argument(
        "paths",
        nargs="+",
        help="one or more files or folders to share",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print success payload as JSON on stdout",
    )
    args = parser.parse_args(argv)

    if platform.system() != "Darwin":
        print(f"{SLUG}: macOS only", file=sys.stderr)
        return 1

    try:
        resolved = resolve_paths(args.paths)
    except FileNotFoundError as exc:
        print(f"{SLUG}: not found: {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"{SLUG}: {exc}", file=sys.stderr)
        return 1

    try:
        share_via_airdrop(resolved)
    except RuntimeError as exc:
        print(f"{SLUG}: {exc}", file=sys.stderr)
        return 1
    except FileNotFoundError:
        print(f"{SLUG}: required command not found", file=sys.stderr)
        return 1

    payload = {"ok": True, "paths": [str(p) for p in resolved]}
    if args.json:
        print(json.dumps(payload, sort_keys=True))
    else:
        for path in resolved:
            print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
