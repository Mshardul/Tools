#!/usr/bin/env python3
"""Move files to the macOS Trash."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_CONFIG_PATH = Path.home() / ".config" / "tools" / "trash.yaml"
VALID_METHODS = ("home", "finder")


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


def resolve_method(*, cli_method: str | None, config: dict[str, str]) -> str:
    method = (cli_method or config.get("method") or "home").lower()
    if method not in VALID_METHODS:
        raise ValueError(f"method must be one of {VALID_METHODS}, got {method!r}")
    return method


def resolve_paths(paths: list[str]) -> list[Path]:
    resolved: list[Path] = []
    for raw in paths:
        path = Path(raw).expanduser().resolve()
        if not path.exists():
            raise FileNotFoundError(raw)
        resolved.append(path)
    return resolved


def trash_via_finder(path: Path) -> None:
    posix = str(path).replace('"', '\\"')
    script = (
        'tell application "Finder"\n'
        f'move (POSIX file "{posix}") to trash\n'
        "end tell"
    )
    subprocess.run(["osascript", "-e", script], check=True, capture_output=True)


def trash_via_home(path: Path) -> None:
    trash_dir = Path.home() / ".Trash"
    trash_dir.mkdir(exist_ok=True)
    dest = trash_dir / path.name
    if dest.exists():
        stamp = time.strftime("%Y-%m-%d %H.%M.%S")
        dest = trash_dir / f"{path.stem} {stamp}{path.suffix}"
    shutil.move(str(path), str(dest))


def trash_paths(paths: list[Path], *, method: str) -> None:
    for path in paths:
        if method == "finder":
            trash_via_finder(path)
        else:
            trash_via_home(path)


def config_path_from_env() -> Path:
    override = os.environ.get("TOOLS_TRASH_CONFIG")
    if override:
        return Path(override).expanduser()
    return DEFAULT_CONFIG_PATH


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Move files or folders to the Trash (default: ~/.Trash, no Finder)."
    )
    parser.add_argument("paths", nargs="+", help="paths to trash")
    parser.add_argument(
        "--method",
        choices=VALID_METHODS,
        default=None,
        help='trash backend: "home" (default) or "finder"',
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=None,
        help=f"YAML config path (default: {DEFAULT_CONFIG_PATH} or $TOOLS_TRASH_CONFIG)",
    )
    args = parser.parse_args(argv)

    cfg_path = args.config.expanduser() if args.config else config_path_from_env()
    try:
        method = resolve_method(cli_method=args.method, config=load_config(cfg_path))
        paths = resolve_paths(args.paths)
        trash_paths(paths, method=method)
    except FileNotFoundError as exc:
        print(f"trash: not found: {exc}", file=sys.stderr)
        return 2
    except ValueError as exc:
        print(f"trash: {exc}", file=sys.stderr)
        return 2
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"trash: {exc}", file=sys.stderr)
        return 1

    for path in paths:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
