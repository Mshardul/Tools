#!/usr/bin/env python3
"""Print current local times for a few IANA time zones."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

SLUG = "world-clock"
DEFAULT_CONFIG_PATH = Path.home() / ".config" / "tools" / "world-clock.yaml"
ENV_CONFIG = "TOOLS_WORLD_CLOCK_CONFIG"
DEFAULT_ZONES = [
    "UTC",
    "America/New_York",
    "Europe/London",
    "Asia/Kolkata",
]


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def load_config(path: Path) -> dict:
    """Load world-clock YAML (zones list + optional labels map). Stdlib-only subset."""
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8")
    zones = _parse_zones(text)
    labels = _parse_labels(text)
    cfg: dict = {}
    if zones is not None:
        cfg["zones"] = zones
    if labels:
        cfg["labels"] = labels
    return cfg


def _parse_zones(text: str) -> list[str] | None:
    flow = re.search(r"(?m)^zones:\s*\[([^\]]*)\]\s*$", text)
    if flow:
        inner = flow.group(1).strip()
        if not inner:
            return []
        return [p.strip().strip("\"'") for p in inner.split(",") if p.strip()]

    lines = text.splitlines()
    for i, raw in enumerate(lines):
        if re.match(r"^zones:\s*$", raw.split("#", 1)[0].rstrip()):
            zones: list[str] = []
            for j in range(i + 1, len(lines)):
                line = lines[j].split("#", 1)[0].rstrip()
                if not line.strip():
                    continue
                m = re.match(r"^\s+-\s+(.+)$", line)
                if not m:
                    break
                zones.append(m.group(1).strip().strip("\"'"))
            return zones
    return None


def _parse_labels(text: str) -> dict[str, str]:
    lines = text.splitlines()
    labels: dict[str, str] = {}
    in_labels = False
    for raw in lines:
        line = raw.split("#", 1)[0].rstrip()
        if re.match(r"^labels:\s*$", line):
            in_labels = True
            continue
        if not in_labels:
            continue
        if line and not line.startswith((" ", "\t")):
            break
        if not line.strip():
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        labels[key.strip()] = value.strip().strip("\"'")
    return labels


def resolve_zones(
    cli_zones: list[str] | None,
    config: dict,
) -> list[str]:
    """CLI zones win; else config zones; else built-in defaults."""
    if cli_zones:
        return list(cli_zones)
    zones = config.get("zones")
    if zones:
        return list(zones)
    return list(DEFAULT_ZONES)


def format_clock(
    now_utc: datetime,
    zones: list[str],
    fmt: str | None = None,
    labels: dict[str, str] | None = None,
) -> list[dict]:
    """Return one dict per zone with local time (ISO or strftime)."""
    if now_utc.tzinfo is None:
        now_utc = now_utc.replace(tzinfo=timezone.utc)
    else:
        now_utc = now_utc.astimezone(timezone.utc)

    label_map = labels or {}
    rows: list[dict] = []
    for zone in zones:
        try:
            zi = ZoneInfo(zone)
        except (ZoneInfoNotFoundError, KeyError) as exc:
            raise ValueError(f"invalid time zone: {zone}") from exc
        local = now_utc.astimezone(zi)
        if fmt:
            time_str = local.strftime(fmt)
        else:
            time_str = local.isoformat()
        row: dict = {"zone": zone, "time": time_str}
        if zone in label_map:
            row["label"] = label_map[zone]
        rows.append(row)
    return rows


def config_path_from_env() -> Path:
    override = os.environ.get(ENV_CONFIG)
    if override:
        return Path(override).expanduser()
    return DEFAULT_CONFIG_PATH


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Print current times for one or more IANA time zones."
    )
    parser.add_argument(
        "--zone",
        action="append",
        dest="zones",
        default=None,
        metavar="IANA",
        help="IANA zone (repeatable); overrides config/defaults",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=None,
        help=f"YAML config path (default: {DEFAULT_CONFIG_PATH} or ${ENV_CONFIG})",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print JSON array of {zone, time[, label]}",
    )
    parser.add_argument(
        "--format",
        dest="fmt",
        default=None,
        metavar="STRFTIME",
        help="strftime format instead of ISO local time",
    )
    args = parser.parse_args(argv)

    cfg_path = args.config.expanduser() if args.config else config_path_from_env()
    try:
        config = load_config(cfg_path)
        zones = resolve_zones(args.zones, config)
        labels = config.get("labels") if isinstance(config.get("labels"), dict) else None
        rows = format_clock(_now_utc(), zones, fmt=args.fmt, labels=labels)
    except ValueError as exc:
        print(f"{SLUG}: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"{SLUG}: {exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(rows))
    else:
        for row in rows:
            prefix = row.get("label") or row["zone"]
            print(f"{prefix}: {row['time']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
