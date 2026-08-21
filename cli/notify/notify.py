#!/usr/bin/env python3
"""Post a macOS notification."""

from __future__ import annotations

import argparse
import subprocess
import sys


def apple_script_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def notify(title: str, message: str, *, sound: str | None = None) -> None:
    script = (
        f'display notification "{apple_script_escape(message)}" '
        f'with title "{apple_script_escape(title)}"'
    )
    if sound:
        script += f' sound name "{apple_script_escape(sound)}"'
    subprocess.run(["osascript", "-e", script], check=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Post a macOS notification.")
    parser.add_argument("message", help="notification body")
    parser.add_argument(
        "-t",
        "--title",
        default="Tools",
        help='notification title (default: "Tools")',
    )
    parser.add_argument(
        "-s",
        "--sound",
        default=None,
        help='optional sound name (e.g. "Glass", "default")',
    )
    args = parser.parse_args(argv)

    try:
        notify(args.title, args.message, sound=args.sound)
    except FileNotFoundError:
        print("notify: osascript not found (macOS only)", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        print(f"notify: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
