#!/usr/bin/env python3
"""Mute, unmute, or toggle macOS microphone input volume."""

from __future__ import annotations

import argparse
import json
import platform
import re
import subprocess
import sys
from pathlib import Path

SLUG = "mic-mute"
DEFAULT_STATE_PATH = Path.home() / ".config" / "tools" / "mic-mute.yaml"
DEFAULT_RESTORE_VOLUME = 50


def parse_volume_settings(text: str) -> dict:
    """Parse `osascript` 'get volume settings' output into a dict."""
    cleaned = text.strip()
    match = re.search(
        r"output volume:\s*(\d+)\s*,\s*"
        r"input volume:\s*(\d+)\s*,\s*"
        r"alert volume:\s*(\d+)\s*,\s*"
        r"output muted:\s*(true|false)",
        cleaned,
        re.IGNORECASE,
    )
    if not match:
        raise ValueError(f"unrecognized volume settings: {cleaned!r}")
    return {
        "output_volume": int(match.group(1)),
        "input_volume": int(match.group(2)),
        "alert_volume": int(match.group(3)),
        "output_muted": match.group(4).lower() == "true",
    }


def decide_toggle(current_input_volume: int) -> str:
    """Return 'mute' or 'unmute' based on current input volume."""
    return "unmute" if current_input_volume == 0 else "mute"


def load_state(path: Path) -> dict:
    """Load flat YAML state; last_input_volume coerced to int when present."""
    if not path.is_file():
        return {}
    data: dict = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip().strip("\"'")
        if key == "last_input_volume":
            data[key] = int(value)
        else:
            data[key] = value
    return data


def save_state(path: Path, *, last_input_volume: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"last_input_volume: {last_input_volume}\n", encoding="utf-8")


def get_volume_settings() -> dict:
    result = subprocess.run(
        ["osascript", "-e", "get volume settings"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        err = (result.stderr or result.stdout or "osascript failed").strip()
        raise RuntimeError(err)
    return parse_volume_settings(result.stdout)


def set_input_volume(volume: int) -> None:
    if volume < 0 or volume > 100:
        raise ValueError(f"input volume must be 0-100, got {volume}")
    result = subprocess.run(
        ["osascript", "-e", f"set volume input volume {volume}"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        err = (result.stderr or result.stdout or "osascript failed").strip()
        raise RuntimeError(err)


def notify(title: str, message: str) -> None:
    safe_title = title.replace("\\", "\\\\").replace('"', '\\"')
    safe_message = message.replace("\\", "\\\\").replace('"', '\\"')
    script = (
        f'display notification "{safe_message}" with title "{safe_title}"'
    )
    subprocess.run(["osascript", "-e", script], check=True, capture_output=True)


def mute(state_path: Path) -> dict:
    settings = get_volume_settings()
    current = settings["input_volume"]
    if current > 0:
        save_state(state_path, last_input_volume=current)
    set_input_volume(0)
    return {
        "action": "mute",
        "muted": True,
        "input_volume": 0,
        "previous_input_volume": current,
    }


def unmute(state_path: Path) -> dict:
    state = load_state(state_path)
    restore = state.get("last_input_volume", DEFAULT_RESTORE_VOLUME)
    if not isinstance(restore, int) or restore <= 0:
        restore = DEFAULT_RESTORE_VOLUME
    set_input_volume(restore)
    return {
        "action": "unmute",
        "muted": False,
        "input_volume": restore,
    }


def toggle(state_path: Path) -> dict:
    settings = get_volume_settings()
    action = decide_toggle(settings["input_volume"])
    if action == "mute":
        return mute(state_path)
    return unmute(state_path)


def status_payload() -> dict:
    settings = get_volume_settings()
    muted = settings["input_volume"] == 0
    return {
        "muted": muted,
        "input_volume": settings["input_volume"],
        "output_volume": settings["output_volume"],
        "output_muted": settings["output_muted"],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Mute, unmute, or toggle macOS microphone input volume.",
    )
    parser.add_argument(
        "command",
        choices=("mute", "unmute", "toggle", "status"),
        help="action to perform",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_STATE_PATH,
        help=f"state/config YAML path (default: {DEFAULT_STATE_PATH})",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print structured JSON on stdout",
    )
    parser.add_argument(
        "--notify",
        action="store_true",
        help="post a macOS notification after mute/unmute/toggle",
    )
    args = parser.parse_args(argv)

    if platform.system() != "Darwin":
        print(f"{SLUG}: macOS only", file=sys.stderr)
        return 1

    try:
        if args.command == "status":
            payload = status_payload()
        elif args.command == "mute":
            payload = mute(args.config)
        elif args.command == "unmute":
            payload = unmute(args.config)
        else:
            payload = toggle(args.config)
    except FileNotFoundError:
        print(f"{SLUG}: osascript not found (macOS only)", file=sys.stderr)
        return 1
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"{SLUG}: {exc}", file=sys.stderr)
        return 1

    if args.notify and args.command != "status":
        try:
            if payload.get("muted"):
                notify("Mic mute", "Microphone muted")
            else:
                vol = payload.get("input_volume", "?")
                notify("Mic mute", f"Microphone unmuted ({vol})")
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"{SLUG}: notify failed: {exc}", file=sys.stderr)
            return 1

    if args.json:
        print(json.dumps(payload, sort_keys=True))
    elif args.command == "status":
        state = "muted" if payload["muted"] else "unmuted"
        print(f"{state} (input volume {payload['input_volume']})")
    else:
        state = "muted" if payload.get("muted") else "unmuted"
        print(f"{payload['action']}: {state} (input volume {payload['input_volume']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
