#!/usr/bin/env python3
"""Turn macOS Focus/DND on, off, or toggle via named Shortcuts."""

from __future__ import annotations

import argparse
import json
import platform
import shutil
import subprocess
import sys
from pathlib import Path

SLUG = "focus-toggle"
DEFAULT_CONFIG_PATH = Path.home() / ".config" / "tools" / "focus-toggle.yaml"
DEFAULT_SHORTCUTS = {
    "on": "Focus On",
    "off": "Focus Off",
    "toggle": "Toggle Focus",
}
MODE_TO_KEY = {
    "on": "shortcut_on",
    "off": "shortcut_off",
    "toggle": "shortcut_toggle",
}


def load_config(path: Path) -> dict[str, str]:
    """Load a flat key: value YAML subset (no dependency on PyYAML)."""
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


def resolve_shortcut(
    mode: str,
    config: dict[str, str],
    *,
    cli_shortcut: str | None = None,
) -> str:
    """Resolve the Shortcuts app name for on/off/toggle."""
    if cli_shortcut:
        return cli_shortcut
    if mode not in MODE_TO_KEY:
        raise ValueError(f"unknown mode: {mode!r}")
    key = MODE_TO_KEY[mode]
    return config.get(key) or DEFAULT_SHORTCUTS[mode]


def build_shortcuts_argv(name: str) -> list[str]:
    return ["shortcuts", "run", name]


def run_shortcut(name: str) -> None:
    result = subprocess.run(
        build_shortcuts_argv(name),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        err = (result.stderr or result.stdout or "shortcuts run failed").strip()
        raise RuntimeError(err)


def status_payload(config: dict[str, str]) -> dict:
    return {
        "shortcuts_available": shutil.which("shortcuts") is not None,
        "shortcut_on": resolve_shortcut("on", config),
        "shortcut_off": resolve_shortcut("off", config),
        "shortcut_toggle": resolve_shortcut("toggle", config),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Turn macOS Focus/DND on, off, or toggle via named Shortcuts.",
    )
    parser.add_argument(
        "command",
        choices=("on", "off", "toggle", "status"),
        help="action to run (status reports config + shortcuts availability)",
    )
    parser.add_argument(
        "--shortcut",
        default=None,
        help="override Shortcuts name for on/off/toggle (default: from config)",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=f"YAML config path (default: {DEFAULT_CONFIG_PATH})",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print status/result as JSON on stdout",
    )
    args = parser.parse_args(argv)

    if platform.system() != "Darwin":
        print(f"{SLUG}: macOS only", file=sys.stderr)
        return 1

    config = load_config(args.config)

    if args.command == "status":
        payload = status_payload(config)
        if args.json:
            print(json.dumps(payload, sort_keys=True))
        else:
            avail = "yes" if payload["shortcuts_available"] else "no"
            print(f"shortcuts available: {avail}")
            print(f"shortcut_on: {payload['shortcut_on']}")
            print(f"shortcut_off: {payload['shortcut_off']}")
            print(f"shortcut_toggle: {payload['shortcut_toggle']}")
        return 0

    if shutil.which("shortcuts") is None:
        print(f"{SLUG}: shortcuts command not found", file=sys.stderr)
        return 1

    try:
        name = resolve_shortcut(args.command, config, cli_shortcut=args.shortcut)
        run_shortcut(name)
    except (ValueError, RuntimeError) as exc:
        print(f"{SLUG}: {exc}", file=sys.stderr)
        return 1
    except FileNotFoundError:
        print(f"{SLUG}: shortcuts command not found", file=sys.stderr)
        return 1

    result = {"action": args.command, "shortcut": name, "ok": True}
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        print(f"{args.command}: ran shortcut {name!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
