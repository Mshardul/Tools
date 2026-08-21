#!/usr/bin/env python3
"""Open Terminal (or another terminal app) at a folder (macOS)."""

from __future__ import annotations

import argparse
import platform
import subprocess
import sys
from pathlib import Path


def resolve_target(path: Path | str) -> Path:
    target = Path(path).expanduser().resolve()
    if not target.exists():
        raise FileNotFoundError(str(path))
    if target.is_file():
        return target.parent
    if target.is_dir():
        return target
    raise FileNotFoundError(str(path))


def open_terminal_at(path: Path | str, app: str = "Terminal") -> None:
    folder = resolve_target(path)
    subprocess.run(
        ["open", "-a", app, str(folder)],
        check=True,
        capture_output=True,
        text=True,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Open a macOS terminal app at a folder (Finder Quick Action helper).",
    )
    parser.add_argument(
        "path",
        nargs="?",
        default=".",
        help="folder (or file — uses parent) to open (default: .)",
    )
    parser.add_argument(
        "-a",
        "--app",
        default="Terminal",
        help='terminal app name (default: "Terminal"; try "iTerm")',
    )
    args = parser.parse_args(argv)

    if platform.system() != "Darwin":
        print("open-terminal-here: macOS only", file=sys.stderr)
        return 1

    try:
        folder = resolve_target(args.path)
        open_terminal_at(folder, app=args.app)
    except FileNotFoundError as exc:
        print(f"open-terminal-here: not found: {exc}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        err = (exc.stderr or str(exc)).strip()
        print(f"open-terminal-here: {err}", file=sys.stderr)
        return 1

    print(str(folder))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
