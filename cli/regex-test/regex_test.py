#!/usr/bin/env python3
"""Test a regex pattern against text."""

from __future__ import annotations

import argparse
import json
import re
import sys


def test_regex(
    pattern: str,
    text: str,
    *,
    ignore_case: bool = False,
    multiline: bool = False,
    dotall: bool = False,
) -> dict:
    flags = 0
    if ignore_case:
        flags |= re.IGNORECASE
    if multiline:
        flags |= re.MULTILINE
    if dotall:
        flags |= re.DOTALL

    match = re.search(pattern, text, flags)
    if match is None:
        return {
            "matched": False,
            "match": None,
            "span": None,
            "groups": (),
            "groupdict": {},
        }

    return {
        "matched": True,
        "match": match.group(0),
        "span": list(match.span()),
        "groups": match.groups(),
        "groupdict": match.groupdict(),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Test a regex pattern against text.")
    parser.add_argument("pattern", help="regex pattern")
    parser.add_argument("text", nargs="?", help="input text (default: stdin)")
    parser.add_argument(
        "-i",
        "--ignore-case",
        action="store_true",
        help="case-insensitive match (re.I)",
    )
    parser.add_argument(
        "-m",
        "--multiline",
        action="store_true",
        help="multiline mode (re.M)",
    )
    parser.add_argument(
        "-s",
        "--dotall",
        action="store_true",
        help="dot matches newline (re.S)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print structured JSON output",
    )
    args = parser.parse_args(argv)

    text = args.text if args.text is not None else sys.stdin.read()
    if text == "":
        print("regex-test: no input (pass text or pipe stdin)", file=sys.stderr)
        return 2

    if args.text is None and text.endswith("\n"):
        text = text[:-1]

    try:
        result = test_regex(
            args.pattern,
            text,
            ignore_case=args.ignore_case,
            multiline=args.multiline,
            dotall=args.dotall,
        )
    except re.error as exc:
        print(f"regex-test: invalid pattern: {exc}", file=sys.stderr)
        return 2

    if args.json:
        payload = {
            "matched": result["matched"],
            "match": result["match"],
            "span": result["span"],
            "groups": list(result["groups"]),
            "groupdict": result["groupdict"],
        }
        print(json.dumps(payload))
    elif result["matched"]:
        print("matched: yes")
        print(f"match: {result['match']}")
        print(f"span: {result['span'][0]},{result['span'][1]}")
        if result["groups"]:
            print(f"groups: {list(result['groups'])}")
        if result["groupdict"]:
            print(f"groupdict: {result['groupdict']}")
    else:
        print("matched: no")

    return 0 if result["matched"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
