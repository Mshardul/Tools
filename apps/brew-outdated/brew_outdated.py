#!/usr/bin/env python3
"""Report outdated Homebrew formulae and casks."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from typing import Any

SLUG = "brew-outdated"


def fetch_brew_outdated_json(
    *,
    json_text: str | None = None,
    brew_cmd: str | None = None,
) -> str:
    """Return stdout of `brew outdated --json=v2`.

    Prefer an explicit ``json_text`` (tests), then ``BREW_OUTDATED_JSON`` env,
    otherwise run brew.
    """
    if json_text is not None:
        return json_text
    env_json = os.environ.get("BREW_OUTDATED_JSON")
    if env_json is not None:
        return env_json
    cmd = brew_cmd or "brew"
    completed = subprocess.run(
        [cmd, "outdated", "--json=v2"],
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout


def parse_brew_outdated(text: str) -> dict[str, Any]:
    """Parse brew outdated --json=v2 into {count, formulae, casks} name lists."""
    data = json.loads(text) if text.strip() else {}
    if not isinstance(data, dict):
        data = {}

    def names(key: str) -> list[str]:
        items = data.get(key) or []
        result: list[str] = []
        for item in items:
            if isinstance(item, dict) and item.get("name"):
                result.append(str(item["name"]))
            elif isinstance(item, str):
                result.append(item)
        return result

    formulae = names("formulae")
    casks = names("casks")
    return {
        "count": len(formulae) + len(casks),
        "formulae": formulae,
        "casks": casks,
    }


def filter_report(
    report: dict[str, Any],
    *,
    formulae_only: bool = False,
    casks_only: bool = False,
) -> dict[str, Any]:
    """Apply --formulae-only / --casks-only filters and recompute count."""
    formulae = list(report.get("formulae") or [])
    casks = list(report.get("casks") or [])
    if formulae_only:
        casks = []
    if casks_only:
        formulae = []
    return {
        "count": len(formulae) + len(casks),
        "formulae": formulae,
        "casks": casks,
    }


def format_human(report: dict[str, Any]) -> str:
    """Human summary: count line, then package names when any."""
    count = int(report.get("count") or 0)
    names = list(report.get("formulae") or []) + list(report.get("casks") or [])
    if count == 0:
        return "0 outdated"
    lines = [f"{count} outdated"]
    lines.extend(names)
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="List outdated Homebrew formulae and casks."
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help='print JSON: {"count","formulae","casks"}',
    )
    parser.add_argument(
        "--formulae-only",
        action="store_true",
        help="only report outdated formulae",
    )
    parser.add_argument(
        "--casks-only",
        action="store_true",
        help="only report outdated casks",
    )
    args = parser.parse_args(argv)

    if args.formulae_only and args.casks_only:
        print(
            f"{SLUG}: use only one of --formulae-only or --casks-only",
            file=sys.stderr,
        )
        return 2

    try:
        text = fetch_brew_outdated_json()
    except FileNotFoundError:
        print(f"{SLUG}: brew not found on PATH", file=sys.stderr)
        return 1
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"{SLUG}: {exc}", file=sys.stderr)
        return 1

    try:
        report = parse_brew_outdated(text)
    except json.JSONDecodeError as exc:
        print(f"{SLUG}: invalid brew JSON: {exc}", file=sys.stderr)
        return 1

    report = filter_report(
        report,
        formulae_only=args.formulae_only,
        casks_only=args.casks_only,
    )

    if args.json:
        print(json.dumps(report))
    else:
        print(format_human(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
