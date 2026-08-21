#!/usr/bin/env python3
"""Days until a host's TLS certificate expires."""

from __future__ import annotations

import argparse
import json
import socket
import ssl
import sys
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime


def fetch_cert_expiry(host: str, port: int = 443, timeout: float = 10) -> datetime:
    """Connect to host:port and return the peer certificate notAfter as UTC-aware datetime."""
    context = ssl.create_default_context()
    with socket.create_connection((host, port), timeout=timeout) as sock:
        with context.wrap_socket(sock, server_hostname=host) as ssock:
            cert = ssock.getpeercert()
    if not cert:
        raise ssl.SSLError("peer certificate missing")
    not_after = cert.get("notAfter")
    if not not_after:
        raise ValueError("certificate has no notAfter")
    expiry = parsedate_to_datetime(not_after)
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=timezone.utc)
    return expiry.astimezone(timezone.utc)


def days_until_expiry(expiry: datetime, *, now: datetime | None = None) -> float:
    """Return days until expiry (negative if already expired)."""
    if now is None:
        now = datetime.now(timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=timezone.utc)
    delta = expiry.astimezone(timezone.utc) - now.astimezone(timezone.utc)
    return delta.total_seconds() / 86400.0


def format_report(host: str, port: int, expiry: datetime, days: float) -> str:
    """Human-readable one-line report."""
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=timezone.utc)
    expires = expiry.astimezone(timezone.utc).isoformat()
    rounded = round(days, 1)
    days_str = str(int(rounded)) if rounded == int(rounded) else f"{rounded:.1f}"
    return f"{host}:{port} expires {expires} ({days_str} days)"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Show days until a host's TLS certificate expires."
    )
    parser.add_argument("host", help="hostname to check")
    parser.add_argument(
        "-p",
        "--port",
        type=int,
        default=443,
        help="TLS port (default: 443)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help='print JSON: {"host","port","expires","days"}',
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=10.0,
        help="connect timeout in seconds (default: 10)",
    )
    args = parser.parse_args(argv)

    if args.port < 1 or args.port > 65535:
        print("ssl-expiry: port must be 1-65535", file=sys.stderr)
        return 2

    try:
        expiry = fetch_cert_expiry(args.host, args.port, timeout=args.timeout)
        days = days_until_expiry(expiry)
    except (OSError, ssl.SSLError, ValueError) as exc:
        print(f"ssl-expiry: {exc}", file=sys.stderr)
        return 1

    if args.json:
        payload = {
            "host": args.host,
            "port": args.port,
            "expires": expiry.astimezone(timezone.utc).isoformat(),
            "days": round(days, 3),
        }
        print(json.dumps(payload))
    else:
        print(format_report(args.host, args.port, expiry, days))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
