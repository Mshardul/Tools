#!/usr/bin/env python3
"""Decode JWT header and payload without verifying."""

from __future__ import annotations

import argparse
import base64
import json
import sys
from typing import Any


def _b64url_decode(segment: str) -> bytes:
    pad = "=" * (-len(segment) % 4)
    try:
        return base64.urlsafe_b64decode(segment + pad)
    except Exception as exc:
        raise ValueError(f"invalid base64url segment: {exc}") from exc


def decode_jwt(token: str) -> dict[str, Any]:
    parts = token.strip().split(".")
    if len(parts) < 2:
        raise ValueError("JWT must have at least header and payload (two segments)")
    header_raw = _b64url_decode(parts[0])
    payload_raw = _b64url_decode(parts[1])
    try:
        header = json.loads(header_raw)
        payload = json.loads(payload_raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"JWT segment is not JSON: {exc}") from exc
    return {"header": header, "payload": payload}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Decode a JWT header and payload (no signature verification)."
    )
    parser.add_argument("token", nargs="?", help="JWT string (default: stdin)")
    parser.add_argument(
        "--json",
        action="store_true",
        help="print a single JSON object with header and payload",
    )
    args = parser.parse_args(argv)

    token = args.token if args.token is not None else sys.stdin.read()
    token = token.strip()
    if not token:
        print("jwt-decode: no input (pass a token or pipe stdin)", file=sys.stderr)
        return 2

    try:
        result = decode_jwt(token)
    except ValueError as exc:
        print(f"jwt-decode: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print("header:")
        print(json.dumps(result["header"], indent=2, sort_keys=True))
        print("payload:")
        print(json.dumps(result["payload"], indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
