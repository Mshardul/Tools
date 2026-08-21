#!/usr/bin/env python3
"""CLI-first 25/5 pomodoro focus timer."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable

DEFAULT_WORK_MIN = 25
DEFAULT_BREAK_MIN = 5
DEFAULT_STATE_PATH = Path.home() / ".config" / "tools" / "pomodoro-state.json"
CHUNK_SEC = 1.0


def apple_script_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def notify(title: str, message: str) -> None:
    script = (
        f'display notification "{apple_script_escape(message)}" '
        f'with title "{apple_script_escape(title)}"'
    )
    subprocess.run(["osascript", "-e", script], check=False)


def phase_seconds(
    phase: str,
    work_min: int,
    break_min: int,
    seconds_override: int | None,
) -> int:
    if seconds_override is not None:
        if seconds_override < 0:
            raise ValueError("seconds override must be >= 0")
        return seconds_override
    if phase == "work":
        if work_min < 0:
            raise ValueError("work minutes must be >= 0")
        return work_min * 60
    if phase == "break":
        if break_min < 0:
            raise ValueError("break minutes must be >= 0")
        return break_min * 60
    raise ValueError(f"unknown phase: {phase!r}")


def write_state(path: Path | str, *, phase: str, end_ts: float) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    payload = {"phase": phase, "end_ts": end_ts}
    p.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def read_state(path: Path | str) -> dict | None:
    p = Path(path)
    if not p.is_file():
        return None
    data = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return None
    return data


def clear_state(path: Path | str) -> None:
    p = Path(path)
    if p.exists():
        p.unlink()


def remaining_seconds(state: dict, now: float) -> float:
    end_ts = float(state["end_ts"])
    return max(0.0, end_ts - now)


def run_timer(
    phase: str,
    *,
    duration_sec: int,
    state_path: Path | str,
    sleep_fn: Callable[[float], None] = time.sleep,
    notify_fn: Callable[[str, str], None] = notify,
    clock: Callable[[], float] = time.time,
    do_notify: bool = True,
    out=sys.stdout,
) -> None:
    start = clock()
    end_ts = start + duration_sec
    write_state(state_path, phase=phase, end_ts=end_ts)
    print(f"pomodoro: {phase} started ({duration_sec}s)", file=out)

    left = float(duration_sec)
    while left > 0:
        chunk = min(CHUNK_SEC, left)
        sleep_fn(chunk)
        left -= chunk

    clear_state(state_path)
    print(f"pomodoro: {phase} done", file=out)
    if do_notify:
        notify_fn("Pomodoro", f"{phase} done")


def format_status(state: dict | None, now: float, *, as_json: bool) -> str:
    if state is None:
        payload = {"status": "idle"}
        if as_json:
            return json.dumps(payload, sort_keys=True)
        return "idle"
    rem = remaining_seconds(state, now)
    phase = state.get("phase", "?")
    if as_json:
        return json.dumps(
            {
                "status": "running" if rem > 0 else "done",
                "phase": phase,
                "remaining_sec": rem,
            },
            sort_keys=True,
        )
    if rem <= 0:
        return f"{phase}: done"
    mins = int(rem) // 60
    secs = int(rem) % 60
    return f"{phase}: {mins}m {secs}s remaining"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="CLI-first 25/5 pomodoro focus timer.",
    )
    parser.add_argument(
        "command",
        choices=("work", "break", "status", "reset"),
        help="start a phase, show status, or clear state",
    )
    parser.add_argument(
        "--work-min",
        type=int,
        default=DEFAULT_WORK_MIN,
        help=f"work duration in minutes (default: {DEFAULT_WORK_MIN})",
    )
    parser.add_argument(
        "--break-min",
        type=int,
        default=DEFAULT_BREAK_MIN,
        help=f"break duration in minutes (default: {DEFAULT_BREAK_MIN})",
    )
    parser.add_argument(
        "--seconds",
        type=int,
        default=None,
        metavar="N",
        help="override duration in seconds (for smoke tests)",
    )
    parser.add_argument(
        "--no-notify",
        action="store_true",
        help="skip macOS notification on complete",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="JSON output for status",
    )
    parser.add_argument(
        "--state-file",
        type=Path,
        default=DEFAULT_STATE_PATH,
        help="path to state file",
    )
    args = parser.parse_args(argv)

    state_path = args.state_file

    if args.command == "reset":
        clear_state(state_path)
        print("pomodoro: reset")
        return 0

    if args.command == "status":
        state = read_state(state_path)
        print(format_status(state, time.time(), as_json=args.json))
        return 0

    # work | break
    try:
        duration = phase_seconds(
            args.command, args.work_min, args.break_min, args.seconds
        )
    except ValueError as exc:
        print(f"pomodoro: {exc}", file=sys.stderr)
        return 1

    try:
        run_timer(
            args.command,
            duration_sec=duration,
            state_path=state_path,
            do_notify=not args.no_notify,
        )
    except OSError as exc:
        print(f"pomodoro: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
