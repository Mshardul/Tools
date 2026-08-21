#!/usr/bin/env python3
"""Pretty-print or minify XML."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from xml.dom import Node, minidom
from xml.parsers.expat import ExpatError


def _strip_whitespace_text_nodes(node: Node) -> None:
    """Remove ignorable whitespace-only text nodes (between elements)."""
    to_remove: list[Node] = []
    for child in list(node.childNodes):
        if child.nodeType == Node.TEXT_NODE:
            if child.data is not None and child.data.strip() == "":
                to_remove.append(child)
        elif child.nodeType == Node.ELEMENT_NODE:
            _strip_whitespace_text_nodes(child)
    for child in to_remove:
        node.removeChild(child)


def format_xml(text: str, mode: str = "pretty") -> str:
    try:
        dom = minidom.parseString(text.encode("utf-8"))
    except ExpatError as exc:
        raise ValueError(f"invalid XML: {exc}") from exc
    except Exception as exc:  # pragma: no cover - defensive
        raise ValueError(f"invalid XML: {exc}") from exc

    _strip_whitespace_text_nodes(dom)

    if mode == "pretty":
        rough = dom.toprettyxml(indent="  ", encoding=None)
        # Drop XML declaration and blank lines from toprettyxml.
        lines = [
            line
            for line in rough.splitlines()
            if line.strip() and not line.strip().startswith("<?xml")
        ]
        return "\n".join(lines) + "\n"
    if mode == "minify":
        # Serialize document element only (no XML declaration).
        root = dom.documentElement
        if root is None:
            raise ValueError("invalid XML: no document element")
        return root.toxml()
    raise ValueError(f"unknown mode: {mode!r}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Pretty-print or minify XML.")
    parser.add_argument(
        "-m",
        "--mode",
        choices=("pretty", "minify"),
        default="pretty",
        help="pretty or minify (default: pretty)",
    )
    parser.add_argument(
        "path",
        nargs="?",
        help="XML file (default: stdin)",
    )
    args = parser.parse_args(argv)

    try:
        if args.path is not None:
            text = Path(args.path).read_text(encoding="utf-8")
        else:
            text = sys.stdin.read()
        if not text.strip():
            raise ValueError("no input (pass a file or pipe stdin)")
        out = format_xml(text, mode=args.mode)
    except (OSError, ValueError) as exc:
        print(f"xml-format: {exc}", file=sys.stderr)
        return 2

    if args.mode == "minify":
        print(out)
    else:
        sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
