#!/usr/bin/env python3
"""Explain a 5-field cron expression in plain English."""

from __future__ import annotations

import argparse
import sys

MONTH_NAMES = {
    1: "January",
    2: "February",
    3: "March",
    4: "April",
    5: "May",
    6: "June",
    7: "July",
    8: "August",
    9: "September",
    10: "October",
    11: "November",
    12: "December",
}

MONTH_ALIASES = {
    "jan": 1,
    "feb": 2,
    "mar": 3,
    "apr": 4,
    "may": 5,
    "jun": 6,
    "jul": 7,
    "aug": 8,
    "sep": 9,
    "oct": 10,
    "nov": 11,
    "dec": 12,
}

DOW_NAMES = {
    0: "Sunday",
    1: "Monday",
    2: "Tuesday",
    3: "Wednesday",
    4: "Thursday",
    5: "Friday",
    6: "Saturday",
    7: "Sunday",
}

DOW_ALIASES = {
    "sun": 0,
    "mon": 1,
    "tue": 2,
    "wed": 3,
    "thu": 4,
    "fri": 5,
    "sat": 6,
}

FIELD_BOUNDS = {
    "minute": (0, 59),
    "hour": (0, 23),
    "dom": (1, 31),
    "month": (1, 12),
    "dow": (0, 7),
}


def _parse_atom(token: str, field: str) -> int:
    lower = token.lower()
    if field == "month" and lower in MONTH_ALIASES:
        return MONTH_ALIASES[lower]
    if field == "dow" and lower in DOW_ALIASES:
        return DOW_ALIASES[lower]
    try:
        value = int(token, 10)
    except ValueError as exc:
        raise ValueError(f"invalid {field} value: {token!r}") from exc
    lo, hi = FIELD_BOUNDS[field]
    if value < lo or value > hi:
        raise ValueError(f"{field} out of range: {value}")
    return value


def _ordinal(n: int) -> str:
    if 10 <= n % 100 <= 20:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
    return f"{n}{suffix}"


def _join_words(parts: list[str]) -> str:
    if len(parts) == 1:
        return parts[0]
    if len(parts) == 2:
        return f"{parts[0]} and {parts[1]}"
    return ", ".join(parts[:-1]) + f", and {parts[-1]}"


def _describe_number(value: int, field: str) -> str:
    if field == "month":
        return MONTH_NAMES[value]
    if field == "dow":
        return DOW_NAMES[value]
    return str(value)


def _describe_part(part: str, field: str) -> str:
    """Describe one list item (may include range and/or step)."""
    step = None
    body = part
    if "/" in part:
        body, step_s = part.split("/", 1)
        if not body:
            raise ValueError(f"invalid {field} step: {part!r}")
        try:
            step = int(step_s, 10)
        except ValueError as exc:
            raise ValueError(f"invalid {field} step: {part!r}") from exc
        if step < 1:
            raise ValueError(f"invalid {field} step: {part!r}")

    if body == "*":
        if step is None:
            return "*"
        return f"every {_ordinal(step)}"

    if "-" in body:
        start_s, end_s = body.split("-", 1)
        start = _parse_atom(start_s, field)
        end = _parse_atom(end_s, field)
        if start > end and field != "dow":
            raise ValueError(f"invalid {field} range: {part!r}")
        start_label = _describe_number(start, field)
        end_label = _describe_number(end, field)
        if step is None:
            return f"{start_label} through {end_label}"
        return f"every {_ordinal(step)} from {start_label} through {end_label}"

    value = _parse_atom(body, field)
    label = _describe_number(value, field)
    if step is None:
        return label
    # Single value with step is unusual; treat as every Nth starting at value
    # within the field's natural range — but crontab usually uses */N or A-B/N.
    lo, hi = FIELD_BOUNDS[field]
    return f"every {_ordinal(step)} from {label} through {_describe_number(hi, field)}"


def _describe_field(raw: str, field: str) -> str | None:
    """Return a human phrase fragment, or None if the field is unrestricted (*)."""
    parts = [p.strip() for p in raw.split(",") if p.strip()]
    if not parts:
        raise ValueError(f"empty {field} field")

    if len(parts) == 1 and parts[0] == "*":
        return None

    described = [_describe_part(p, field) for p in parts]

    if len(described) == 1 and described[0] == "*":
        return None

    # Step-only on *: "every 15th"
    if len(described) == 1 and described[0].startswith("every ") and "/" in parts[0] and parts[0].startswith("*/"):
        return described[0]

    return _join_words(described)


def _with_unit(desc: str, unit: str) -> str:
    """Insert unit after ordinal step: 'every 2nd from A through B' → 'every 2nd hour from …'."""
    if desc.startswith("every "):
        rest = desc[len("every ") :]
        if " from " in rest:
            ordinal, span = rest.split(" from ", 1)
            return f"every {ordinal} {unit} from {span}"
        return f"every {rest} {unit}"
    return desc


def _minute_phrase(desc: str | None, raw: str) -> str:
    if desc is None:
        return "every minute"
    if desc.startswith("every "):
        return _with_unit(desc, "minute")
    if "," not in raw and "-" not in raw and "/" not in raw:
        return f"minute {desc}"
    if " through " in desc:
        return f"every minute from {desc}"
    return f"minute {desc}"


def _hour_phrase(desc: str | None, raw: str) -> str:
    if desc is None:
        return "every hour"
    if desc.startswith("every "):
        return _with_unit(desc, "hour")
    if "," not in raw and "-" not in raw and "/" not in raw:
        return f"hour {desc}"
    if " through " in desc:
        return f"every hour from {desc}"
    return f"hour {desc}"


def _is_single_number(raw: str, field: str) -> bool:
    if any(c in raw for c in "*,-/"):
        return False
    try:
        _parse_atom(raw, field)
    except ValueError:
        return False
    return True


def explain(expr: str) -> str:
    """Return a plain-English explanation of a 5-field cron expression."""
    text = expr.strip()
    if not text:
        raise ValueError("empty cron expression")
    fields = text.split()
    if len(fields) != 5:
        raise ValueError(f"expected 5 fields, got {len(fields)}")

    minute_r, hour_r, dom_r, month_r, dow_r = fields

    # Validate by describing (raises on bad tokens)
    minute_d = _describe_field(minute_r, "minute")
    hour_d = _describe_field(hour_r, "hour")
    dom_d = _describe_field(dom_r, "dom")
    month_d = _describe_field(month_r, "month")
    dow_d = _describe_field(dow_r, "dow")

    # Compact HH:MM when both minute and hour are single numbers
    if _is_single_number(minute_r, "minute") and _is_single_number(hour_r, "hour"):
        minute_n = _parse_atom(minute_r, "minute")
        hour_n = _parse_atom(hour_r, "hour")
        core = f"At {hour_n:02d}:{minute_n:02d}"
    elif minute_d is None and hour_d is None:
        core = "At every minute"
    elif hour_d is None:
        core = f"At {_minute_phrase(minute_d, minute_r)} past every hour"
    elif minute_d is None:
        core = f"At every minute past {_hour_phrase(hour_d, hour_r)}"
    else:
        core = (
            f"At {_minute_phrase(minute_d, minute_r)} "
            f"past {_hour_phrase(hour_d, hour_r)}"
        )

    # Order: day-of-month, day-of-week, month (matches common cron explainers)
    extras: list[str] = []
    if dom_d is not None:
        if dom_d.startswith("every "):
            extras.append(f"on {_with_unit(dom_d, 'day-of-month')}")
        else:
            extras.append(f"on day-of-month {dom_d}")
    if dow_d is not None:
        extras.append(f"on {dow_d}")
    if month_d is not None:
        if month_d.startswith("every "):
            extras.append(f"in {_with_unit(month_d, 'month')}")
        else:
            extras.append(f"in {month_d}")

    if extras:
        return core + " " + " ".join(extras) + "."
    if core == "At every minute":
        return "At every minute."
    return core + "."


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Explain a 5-field cron expression in plain English."
    )
    parser.add_argument(
        "fields",
        nargs="+",
        help="cron expression as one quoted string, or five separate fields",
    )
    args = parser.parse_args(argv)

    if len(args.fields) == 1:
        expr = args.fields[0]
    elif len(args.fields) == 5:
        expr = " ".join(args.fields)
    else:
        print(
            "cron-explain: expected one quoted expression or five fields",
            file=sys.stderr,
        )
        return 2

    try:
        print(explain(expr))
    except ValueError as exc:
        print(f"cron-explain: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
