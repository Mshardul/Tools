#!/usr/bin/env python3
"""List and show text snippets from a git-friendly folder."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from collections.abc import Mapping
from pathlib import Path

DEFAULT_SNIPPETS_DIR = Path("snippets")
DEFAULT_CONFIG_PATH = Path.home() / ".config" / "tools" / "file-snippets.yaml"
ENV_VAR = "TOOLS_FILE_SNIPPETS_DIR"


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


def resolve_snippets_dir(
    *,
    cli_dir: str | Path | None = None,
    env: Mapping[str, str] | None = None,
    config_path: Path | None = None,
) -> Path:
    """Resolve snippets directory: CLI > env > config > default."""
    if cli_dir is not None:
        return Path(cli_dir).expanduser()
    environ = os.environ if env is None else env
    env_val = environ.get(ENV_VAR)
    if env_val:
        return Path(env_val).expanduser()
    cfg_path = DEFAULT_CONFIG_PATH if config_path is None else config_path
    snippets_dir = load_config(cfg_path).get("snippets_dir")
    if snippets_dir:
        return Path(snippets_dir).expanduser()
    return DEFAULT_SNIPPETS_DIR


def list_snippet_names(snippets_dir: Path) -> list[str]:
    if not snippets_dir.is_dir():
        raise FileNotFoundError(f"snippets directory not found: {snippets_dir}")
    names: list[str] = []
    for path in snippets_dir.iterdir():
        if path.name.startswith("."):
            continue
        if path.is_file():
            names.append(path.stem)
    return sorted(names)


def _snippet_file(snippets_dir: Path, name: str) -> Path:
    if not snippets_dir.is_dir():
        raise FileNotFoundError(f"snippets directory not found: {snippets_dir}")
    matches = sorted(
        p
        for p in snippets_dir.iterdir()
        if not p.name.startswith(".") and p.is_file() and p.stem == name
    )
    if not matches:
        raise FileNotFoundError(f"unknown snippet: {name}")
    return matches[0]


def read_snippet(snippets_dir: Path, name: str) -> str:
    return _snippet_file(snippets_dir, name).read_text(encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="List and show text snippets from a folder of files."
    )
    parser.add_argument(
        "--dir",
        dest="snippets_dir",
        default=None,
        help=f"snippets directory (default: ./snippets, or ${ENV_VAR}, or config snippets_dir)",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    list_p = sub.add_parser("list", help="list snippet names")
    list_p.add_argument(
        "--json",
        action="store_true",
        help="print names as a JSON array",
    )

    show_p = sub.add_parser("show", help="print a snippet's contents")
    show_p.add_argument("name", help="snippet name (filename stem)")
    show_p.add_argument(
        "-c",
        "--clipboard",
        action="store_true",
        help="also copy contents to the clipboard (macOS pbcopy)",
    )

    args = parser.parse_args(argv)

    try:
        snippets_dir = resolve_snippets_dir(cli_dir=args.snippets_dir)
        if args.command == "list":
            names = list_snippet_names(snippets_dir)
            if args.json:
                print(json.dumps(names, ensure_ascii=False))
            else:
                for name in names:
                    print(name)
            return 0
        text = read_snippet(snippets_dir, args.name)
    except OSError as exc:
        print(f"file-snippets: {exc}", file=sys.stderr)
        return 2

    sys.stdout.write(text)
    if args.clipboard:
        try:
            subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(
                f"file-snippets: could not copy to clipboard: {exc}",
                file=sys.stderr,
            )
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
