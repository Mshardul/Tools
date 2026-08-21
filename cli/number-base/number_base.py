#!/usr/bin/env python3
"""Convert integers among binary, octal, decimal, and hex."""

from __future__ import annotations

import argparse
import subprocess
import sys

_BASE_ALIASES = {
    "bin": 2,
    "2": 2,
    "oct": 8,
    "8": 8,
    "dec": 10,
    "10": 10,
    "hex": 16,
    "16": 16,
}

_BASE_NAMES = {
    2: "bin",
    8: "oct",
    10: "dec",
    16: "hex",
}

_PREFIXES = {
    "bin": "0b",
    "oct": "0o",
    "hex": "0x",
}


def normalize_base(name: str) -> str:
    key = name.lower()
    if key not in _BASE_ALIASES:
        raise ValueError(f"unknown base: {name!r} (use bin, oct, dec, hex)")
    return _BASE_NAMES[_BASE_ALIASES[key]]


def detect_base(value: str) -> str:
    text = value.strip().replace("_", "")
    if text.startswith(("+", "-")):
        text = text[1:]
    lower = text.lower()
    if lower.startswith("0b"):
        return "bin"
    if lower.startswith("0o"):
        return "oct"
    if lower.startswith("0x"):
        return "hex"
    return "dec"


def _parse_int(value: str, from_base: str) -> int:
    text = value.strip().replace("_", "")
    base = _BASE_ALIASES[normalize_base(from_base)]
    negative = text.startswith("-")
    if text.startswith(("+", "-")):
        text = text[1:]
    lower = text.lower()
    if base == 2 and lower.startswith("0b"):
        text = text[2:]
    elif base == 8 and lower.startswith("0o"):
        text = text[2:]
    elif base == 16 and lower.startswith("0x"):
        text = text[2:]
    try:
        number = int(text, base)
    except ValueError as exc:
        raise ValueError(f"invalid {from_base} integer: {value!r}") from exc
    return -number if negative else number


def _format_int(number: int, to_base: str) -> str:
    base_name = normalize_base(to_base)
    base = _BASE_ALIASES[base_name]
    negative = number < 0
    number = abs(number)
    if base == 10:
        out = str(number)
    elif base == 2:
        out = bin(number)
    elif base == 8:
        out = oct(number)
    else:
        out = hex(number)
    if negative:
        out = "-" + out
    return out


def convert_base(value: str, *, from_base: str | None, to_base: str) -> str:
    source = from_base or detect_base(value)
    number = _parse_int(value, source)
    return _format_int(number, to_base)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert integers among binary, octal, decimal, and hex."
    )
    parser.add_argument(
        "--from",
        dest="from_base",
        choices=tuple(_BASE_ALIASES),
        help="source base (auto-detect if omitted)",
    )
    parser.add_argument(
        "--to",
        dest="to_base",
        choices=tuple(_BASE_ALIASES),
        required=True,
        help="target base",
    )
    parser.add_argument("value", nargs="?", help="integer value (default: stdin)")
    parser.add_argument(
        "-c",
        "--copy",
        action="store_true",
        help="copy result to the clipboard (macOS pbcopy)",
    )
    args = parser.parse_args(argv)

    value = args.value if args.value is not None else sys.stdin.read()
    if args.value is None and value.endswith("\n"):
        value = value[:-1]
    if value.strip() == "":
        print("number-base: no input (pass a value or pipe stdin)", file=sys.stderr)
        return 2

    try:
        out = convert_base(value, from_base=args.from_base, to_base=args.to_base)
    except ValueError as exc:
        print(f"number-base: {exc}", file=sys.stderr)
        return 2

    print(out)
    if args.copy:
        try:
            subprocess.run(["pbcopy"], input=out.encode("utf-8"), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"number-base: could not copy to clipboard: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
