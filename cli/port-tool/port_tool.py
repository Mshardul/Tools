#!/usr/bin/env python3
"""Inspect or free a TCP port."""

from __future__ import annotations

import argparse
import subprocess
import sys


def parse_lsof_pids(output: str) -> list[int]:
    pids: list[int] = []
    seen: set[int] = set()
    lines = output.strip().splitlines()
    if not lines:
        return []
    for line in lines[1:]:
        parts = line.split()
        if len(parts) < 2:
            continue
        try:
            pid = int(parts[1])
        except ValueError:
            continue
        if pid not in seen:
            seen.add(pid)
            pids.append(pid)
    return pids


def lsof_port(port: int) -> str:
    result = subprocess.run(
        ["lsof", f"-iTCP:{port}", "-sTCP:LISTEN", "-n", "-P"],
        capture_output=True,
        text=True,
    )
    # lsof exits 1 when nothing matches
    if result.returncode not in (0, 1):
        raise subprocess.CalledProcessError(result.returncode, result.args, result.stdout, result.stderr)
    return result.stdout


def who(port: int) -> list[tuple[int, str]]:
    output = lsof_port(port)
    rows: list[tuple[int, str]] = []
    seen: set[int] = set()
    lines = output.strip().splitlines()
    for line in lines[1:]:
        parts = line.split()
        if len(parts) < 2:
            continue
        try:
            pid = int(parts[1])
        except ValueError:
            continue
        if pid in seen:
            continue
        seen.add(pid)
        command = parts[0]
        rows.append((pid, command))
    return rows


def kill_pids(pids: list[int], *, force: bool) -> None:
    if not pids:
        return
    sig = "-9" if force else "-TERM"
    subprocess.run(["kill", sig, *[str(p) for p in pids]], check=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Show which process listens on a TCP port, or kill it."
    )
    parser.add_argument("port", type=int, help="TCP port number")
    parser.add_argument(
        "mode",
        nargs="?",
        choices=("who", "kill"),
        default="who",
        help='action: "who" (default) or "kill"',
    )
    parser.add_argument(
        "-f",
        "--force",
        action="store_true",
        help="with kill: send SIGKILL instead of SIGTERM",
    )
    args = parser.parse_args(argv)

    if args.port < 1 or args.port > 65535:
        print("port-tool: port must be 1-65535", file=sys.stderr)
        return 2

    try:
        if args.mode == "who":
            rows = who(args.port)
            if not rows:
                print(f"nothing listening on {args.port}")
                return 0
            for pid, command in rows:
                print(f"{pid}\t{command}")
            return 0

        rows = who(args.port)
        pids = [pid for pid, _ in rows]
        if not pids:
            print(f"nothing listening on {args.port}")
            return 0
        kill_pids(pids, force=args.force)
        for pid, command in rows:
            print(f"killed {pid}\t{command}")
        return 0
    except FileNotFoundError as exc:
        print(f"port-tool: missing command: {exc}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        print(f"port-tool: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
