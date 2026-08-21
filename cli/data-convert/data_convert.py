#!/usr/bin/env python3
"""Convert among json, yaml, toml, csv, and env formats."""

from __future__ import annotations

import argparse
import csv
import io
import json
import sys
import tomllib
from pathlib import Path
from typing import Any

_EXT_MAP = {
    ".json": "json",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".toml": "toml",
    ".csv": "csv",
    ".env": "env",
}


def detect_format(path: str | Path) -> str:
    suffix = Path(path).suffix.lower()
    if suffix not in _EXT_MAP:
        raise ValueError(
            f"cannot detect format from extension {suffix!r} "
            "(use --from with json, yaml, toml, csv, or env)"
        )
    return _EXT_MAP[suffix]


def _normalize_fmt(fmt: str) -> str:
    key = fmt.lower().strip()
    if key == "yml":
        key = "yaml"
    if key not in ("json", "yaml", "toml", "csv", "env"):
        raise ValueError(
            f"unknown format: {fmt!r} (use json, yaml, toml, csv, or env)"
        )
    return key


def _require_yaml():
    try:
        import yaml  # noqa: F401
    except ImportError as exc:
        raise ValueError(
            "YAML support requires PyYAML (pip install pyyaml)"
        ) from exc
    return __import__("yaml")


def load(text: str, fmt: str) -> Any:
    fmt = _normalize_fmt(fmt)
    if fmt == "json":
        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError(f"invalid JSON: {exc}") from exc
    if fmt == "yaml":
        yaml = _require_yaml()
        return yaml.safe_load(text)
    if fmt == "toml":
        try:
            return tomllib.loads(text)
        except tomllib.TOMLDecodeError as exc:
            raise ValueError(f"invalid TOML: {exc}") from exc
    if fmt == "csv":
        return _load_csv(text)
    if fmt == "env":
        return _load_env(text)
    raise ValueError(f"unknown format: {fmt!r}")


def dump(data: Any, fmt: str) -> str:
    fmt = _normalize_fmt(fmt)
    if fmt == "json":
        return json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if fmt == "yaml":
        yaml = _require_yaml()
        out = yaml.safe_dump(data, default_flow_style=False, allow_unicode=True)
        return out if out.endswith("\n") else out + "\n"
    if fmt == "toml":
        return dump_toml(data)
    if fmt == "csv":
        return _dump_csv(data)
    if fmt == "env":
        return _dump_env(data)
    raise ValueError(f"unknown format: {fmt!r}")


def convert(text: str, from_fmt: str, to_fmt: str) -> str:
    return dump(load(text, from_fmt), to_fmt)


def _load_csv(text: str) -> list[dict[str, str]]:
    reader = csv.DictReader(io.StringIO(text))
    if reader.fieldnames is None:
        raise ValueError("CSV has no header row")
    return list(reader)


def _dump_csv(data: Any) -> str:
    buf = io.StringIO()
    if isinstance(data, list) and data and isinstance(data[0], dict):
        fieldnames: list[str] = []
        for row in data:
            for key in row:
                if key not in fieldnames:
                    fieldnames.append(str(key))
        writer = csv.DictWriter(buf, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for row in data:
            writer.writerow({k: row.get(k, "") for k in fieldnames})
        return buf.getvalue()
    if isinstance(data, list) and data and isinstance(data[0], (list, tuple)):
        writer = csv.writer(buf, lineterminator="\n")
        for row in data:
            writer.writerow(row)
        return buf.getvalue()
    if isinstance(data, list) and not data:
        return ""
    raise ValueError(
        "CSV dump requires a list of dicts or list of lists (tabular data)"
    )


def _load_env(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"invalid env line {lineno}: {raw!r}")
        key, _, value = line.partition("=")
        key = key.strip()
        if not key:
            raise ValueError(f"invalid env line {lineno}: empty key")
        result[key] = value
    return result


def _dump_env(data: Any) -> str:
    if not isinstance(data, dict):
        raise ValueError("env dump requires a flat dict of scalar values")
    lines: list[str] = []
    for key, value in data.items():
        if isinstance(value, dict):
            raise ValueError(
                "env dump does not support nested dicts "
                f"(key {key!r} is nested)"
            )
        if isinstance(value, (list, tuple)):
            raise ValueError(
                "env dump does not support lists "
                f"(key {key!r} is a list)"
            )
        if value is None:
            lines.append(f"{key}=")
        elif isinstance(value, bool):
            lines.append(f"{key}={'true' if value else 'false'}")
        else:
            lines.append(f"{key}={value}")
    return "\n".join(lines) + ("\n" if lines else "")


def dump_toml(obj: Any) -> str:
    """Serialize dict/list/str/int/float/bool/None to TOML text."""
    try:
        import tomli_w  # type: ignore

        return tomli_w.dumps(obj)
    except ImportError:
        pass
    if not isinstance(obj, dict):
        raise ValueError("TOML dump requires a top-level dict")
    return _dump_toml_table(obj, ())


def _toml_escape_str(s: str) -> str:
    return '"' + (
        s.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    ) + '"'


def _toml_inline(value: Any) -> str:
    if value is None:
        raise ValueError("TOML does not support null values")
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        return str(value)
    if isinstance(value, str):
        return _toml_escape_str(value)
    if isinstance(value, list):
        return "[" + ", ".join(_toml_inline(v) for v in value) + "]"
    if isinstance(value, dict):
        parts = []
        for k, v in value.items():
            if not isinstance(k, str):
                raise ValueError(f"TOML keys must be strings: {k!r}")
            parts.append(f"{_toml_key(k)} = {_toml_inline(v)}")
        return "{ " + ", ".join(parts) + " }"
    raise ValueError(f"unsupported TOML type: {type(value).__name__}")


def _toml_key(key: str) -> str:
    if key.isidentifier() or (
        key
        and all(c.isalnum() or c in "-_" for c in key)
        and not key[0].isdigit()
    ):
        return key
    return _toml_escape_str(key)


def _dump_toml_table(table: dict, path: tuple[str, ...]) -> str:
    lines: list[str] = []
    nested_tables: list[tuple[str, dict]] = []
    array_tables: list[tuple[str, list]] = []

    for key, value in table.items():
        if not isinstance(key, str):
            raise ValueError(f"TOML keys must be strings: {key!r}")
        if isinstance(value, dict):
            nested_tables.append((key, value))
        elif isinstance(value, list) and value and isinstance(value[0], dict):
            array_tables.append((key, value))
        else:
            lines.append(f"{_toml_key(key)} = {_toml_inline(value)}")

    chunks: list[str] = []
    if path and (lines or not nested_tables and not array_tables):
        header = ".".join(_toml_key(p) for p in path)
        chunks.append(f"[{header}]")
    if lines:
        chunks.extend(lines)

    body = "\n".join(chunks)
    parts: list[str] = [body] if body else []

    for key, nested in nested_tables:
        parts.append(_dump_toml_table(nested, path + (key,)))

    for key, arr in array_tables:
        for item in arr:
            if not isinstance(item, dict):
                raise ValueError("array of tables must contain only dicts")
            header = ".".join(_toml_key(p) for p in path + (key,))
            item_lines = [f"[[{header}]]"]
            more_nested: list[tuple[str, dict]] = []
            for ik, iv in item.items():
                if isinstance(iv, dict):
                    more_nested.append((ik, iv))
                elif isinstance(iv, list) and iv and isinstance(iv[0], dict):
                    raise ValueError(
                        "nested array-of-tables inside array-of-tables "
                        "is not supported by this encoder"
                    )
                else:
                    item_lines.append(f"{_toml_key(ik)} = {_toml_inline(iv)}")
            block = "\n".join(item_lines)
            for nk, nv in more_nested:
                block += "\n" + _dump_toml_table(nv, path + (key, nk))
            parts.append(block)

    out = "\n\n".join(p for p in parts if p)
    return out + ("\n" if out else "")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="data-convert",
        description="Convert among json, yaml, toml, csv, and env formats.",
    )
    parser.add_argument(
        "--from",
        dest="from_fmt",
        metavar="FMT",
        help="input format (json, yaml, toml, csv, env); "
        "optional if FILE has a known extension",
    )
    parser.add_argument(
        "--to",
        dest="to_fmt",
        metavar="FMT",
        required=True,
        help="output format (json, yaml, toml, csv, env)",
    )
    parser.add_argument(
        "-o",
        "--output",
        metavar="OUT",
        help="write result to OUT instead of stdout",
    )
    parser.add_argument(
        "file",
        nargs="?",
        help="input file (default: stdin)",
    )
    args = parser.parse_args(argv)

    try:
        from_fmt = args.from_fmt
        if from_fmt is None:
            if args.file is None:
                raise ValueError(
                    "provide --from FMT, or a FILE with a known extension"
                )
            from_fmt = detect_format(args.file)
        from_fmt = _normalize_fmt(from_fmt)
        to_fmt = _normalize_fmt(args.to_fmt)

        if args.file is not None:
            text = Path(args.file).read_text(encoding="utf-8")
        else:
            text = sys.stdin.read()

        out = convert(text, from_fmt, to_fmt)
    except (OSError, ValueError) as exc:
        print(f"data-convert: {exc}", file=sys.stderr)
        return 2

    if args.output:
        try:
            Path(args.output).write_text(out, encoding="utf-8")
        except OSError as exc:
            print(f"data-convert: {exc}", file=sys.stderr)
            return 2
    else:
        sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
