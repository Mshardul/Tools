#!/usr/bin/env python3
"""Battery percent, charging state, and ETA from macOS pmset."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

SLUG = "battery-eta"


def fetch_pmset_batt() -> str:
    """Run `pmset -g batt` and return stdout text."""
    completed = subprocess.run(
        ["pmset", "-g", "batt"],
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout


def parse_pmset_batt(text: str) -> dict:
    """Parse pmset -g batt output into structured fields."""
    source: str | None = None
    percent: int | None = None
    status: str | None = None
    eta: str | None = None
    present: bool | None = None

    source_m = re.search(r"Now drawing from '([^']+)'", text)
    if source_m:
        source = source_m.group(1)

    present_m = re.search(r"present:\s*(true|false)", text, re.IGNORECASE)
    if present_m:
        present = present_m.group(1).lower() == "true"

    # Battery detail: "45%; discharging; 3:45 remaining present: true"
    for line in text.splitlines():
        if "%;" not in line:
            continue
        m = re.search(r"(\d+)%;\s*(.+)", line)
        if not m:
            continue
        percent = int(m.group(1))
        rest = m.group(2).strip()
        rest = re.sub(r"\s*present:\s*(true|false)\s*$", "", rest, flags=re.I)
        parts = [p.strip() for p in rest.split(";") if p.strip()]
        if parts:
            status = parts[0].lower()
        if len(parts) > 1:
            mid = parts[1]
            if re.search(r"no estimate", mid, re.IGNORECASE):
                eta = None
            else:
                eta_m = re.search(r"(\d+:\d{2})", mid)
                if eta_m:
                    eta = eta_m.group(1)
        break

    return {
        "source": source,
        "percent": percent,
        "status": status,
        "eta": eta,
        "present": present,
    }


def format_status(parsed: dict) -> str:
    """Human one-liner: percent, status, ETA when present, power source."""
    percent = parsed.get("percent")
    status = parsed.get("status")
    eta = parsed.get("eta")
    source = parsed.get("source")

    if percent is not None and status:
        if status == "charging" and eta:
            core = f"{percent}% {status}, {eta} until full"
        elif status == "discharging" and eta:
            core = f"{percent}% {status}, {eta} remaining"
        else:
            core = f"{percent}% {status}"
    elif percent is not None:
        core = f"{percent}%"
    elif status:
        core = str(status)
    elif source:
        core = source
    else:
        core = "unknown"

    if source and core != source:
        return f"{core} ({source})"
    return core


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Show macOS battery percent, status, and time remaining/until full."
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print parsed fields as JSON",
    )
    parser.add_argument(
        "--raw",
        action="store_true",
        help="print raw pmset -g batt stdout",
    )
    args = parser.parse_args(argv)

    try:
        text = fetch_pmset_batt()
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"{SLUG}: {exc}", file=sys.stderr)
        return 1

    if args.raw:
        sys.stdout.write(text)
        return 0

    parsed = parse_pmset_batt(text)
    if args.json:
        print(json.dumps(parsed))
    else:
        print(format_status(parsed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
