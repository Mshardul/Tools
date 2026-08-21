#!/usr/bin/env python3
"""Clear Gatekeeper quarantine xattr from files (macOS)."""

from __future__ import annotations

import argparse
import platform
import shutil
import subprocess
import sys
from pathlib import Path

QUARANTINE_ATTR = "com.apple.quarantine"


def resolve_paths(paths: list[str]) -> list[Path]:
    resolved: list[Path] = []
    for raw in paths:
        path = Path(raw).expanduser().resolve()
        if not path.exists():
            raise FileNotFoundError(raw)
        resolved.append(path)
    return resolved


def clear_quarantine(path: Path) -> bool:
    """Remove com.apple.quarantine. Return True if removed, False if it was not set."""
    result = subprocess.run(
        ["xattr", "-d", QUARANTINE_ATTR, str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return True
    stderr = (result.stderr or "").lower()
    if "no such xattr" in stderr or "not found" in stderr:
        return False
    raise subprocess.CalledProcessError(
        result.returncode, result.args, result.stdout, result.stderr
    )


def check_quarantine(path: Path) -> bool:
    """Return True if com.apple.quarantine is set."""
    result = subprocess.run(
        ["xattr", "-p", QUARANTINE_ATTR, str(path)],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Clear Gatekeeper quarantine xattr from one or more paths."
    )
    parser.add_argument("paths", nargs="+", help="file or directory paths")
    parser.add_argument(
        "--check",
        action="store_true",
        help="only report whether quarantine is set (exit 1 if any path is set)",
    )
    args = parser.parse_args(argv)

    if platform.system() != "Darwin":
        print("quarantine-clear: macOS only", file=sys.stderr)
        return 1

    if shutil.which("xattr") is None:
        print("quarantine-clear: xattr command not found", file=sys.stderr)
        return 1

    try:
        paths = resolve_paths(args.paths)
    except FileNotFoundError as exc:
        print(f"quarantine-clear: not found: {exc}", file=sys.stderr)
        return 1

    try:
        if args.check:
            any_set = False
            for path in paths:
                set_ = check_quarantine(path)
                status = "set" if set_ else "clear"
                print(f"{path}: quarantine {status}")
                if set_:
                    any_set = True
            return 1 if any_set else 0

        for path in paths:
            removed = clear_quarantine(path)
            if removed:
                print(f"{path}: quarantine cleared")
            else:
                print(f"{path}: quarantine already clear")
        return 0
    except subprocess.CalledProcessError as exc:
        err = (exc.stderr or str(exc)).strip()
        print(f"quarantine-clear: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
