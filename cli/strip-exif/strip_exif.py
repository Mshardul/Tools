#!/usr/bin/env python3
"""Remove EXIF/GPS and text metadata from JPEG and PNG images."""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

JPEG_SOI = b"\xff\xd8"
PNG_SIG = b"\x89PNG\r\n\x1a\n"

# PNG chunks that carry metadata only (not needed for display).
PNG_STRIP = {b"eXIf", b"tEXt", b"zTXt", b"iTXt", b"tIME"}


def _detect_format(data: bytes) -> str:
    if data.startswith(JPEG_SOI):
        return "jpeg"
    if data.startswith(PNG_SIG):
        return "png"
    raise ValueError("unsupported format (expected JPEG or PNG)")


def strip_jpeg(data: bytes) -> bytes:
    """Strip APP1 (EXIF/XMP) segments; keep APP0 JFIF and image data."""
    if not data.startswith(JPEG_SOI):
        raise ValueError("not a JPEG image")
    if len(data) < 4:
        raise ValueError("truncated JPEG")

    out = bytearray(JPEG_SOI)
    i = 2
    n = len(data)

    while i < n:
        if data[i] != 0xFF:
            raise ValueError(f"invalid JPEG marker at offset {i}")
        # Skip fill bytes (0xFF padding before marker code).
        while i < n and data[i] == 0xFF:
            i += 1
        if i >= n:
            raise ValueError("truncated JPEG marker")
        marker = data[i]
        i += 1

        # Standalone markers (no length).
        if marker == 0xD9:  # EOI
            out.extend(b"\xff\xd9")
            break
        if marker == 0xD8:  # SOI (ignore nested)
            continue
        if 0xD0 <= marker <= 0xD7 or marker == 0x01:
            out.append(0xFF)
            out.append(marker)
            continue

        if i + 2 > n:
            raise ValueError("truncated JPEG segment length")
        length = struct.unpack(">H", data[i : i + 2])[0]
        if length < 2 or i + length > n:
            raise ValueError("invalid JPEG segment length")
        segment = bytes([0xFF, marker]) + data[i : i + length]
        next_i = i + length

        if marker == 0xE1:  # APP1 — EXIF / XMP
            i = next_i
            continue

        if marker == 0xDA:  # SOS — rest of file is scan data through EOI
            out.extend(segment)
            out.extend(data[next_i:])
            break

        out.extend(segment)
        i = next_i
    else:
        raise ValueError("JPEG missing EOI or SOS")

    return bytes(out)


def strip_png(data: bytes) -> bytes:
    """Strip eXIf, tEXt, zTXt, iTXt, and tIME chunks; keep display-critical chunks."""
    if not data.startswith(PNG_SIG):
        raise ValueError("not a PNG image")
    if len(data) < 8:
        raise ValueError("truncated PNG")

    out = bytearray(PNG_SIG)
    i = 8
    n = len(data)
    saw_iend = False

    while i + 12 <= n:
        length = struct.unpack(">I", data[i : i + 4])[0]
        chunk_type = data[i + 4 : i + 8]
        end = i + 12 + length
        if length < 0 or end > n:
            raise ValueError("invalid PNG chunk length")
        chunk = data[i:end]
        i = end

        if chunk_type in PNG_STRIP:
            continue
        out.extend(chunk)
        if chunk_type == b"IEND":
            saw_iend = True
            break

    if not saw_iend:
        raise ValueError("PNG missing IEND chunk")
    return bytes(out)


def strip_image(data: bytes) -> bytes:
    """Detect JPEG/PNG by magic bytes and return metadata-stripped image bytes."""
    fmt = _detect_format(data)
    if fmt == "jpeg":
        return strip_jpeg(data)
    return strip_png(data)


def strip_file(src: Path, dest: Path | None = None) -> Path:
    """Strip metadata from *src*; write to *dest* or overwrite *src* in place."""
    src = Path(src)
    data = src.read_bytes()
    cleaned = strip_image(data)
    out_path = Path(dest) if dest is not None else src
    out_path.write_bytes(cleaned)
    return out_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Remove EXIF/GPS and text metadata from JPEG and PNG images.",
    )
    parser.add_argument("file", help="image path (JPEG or PNG)")
    parser.add_argument(
        "-o",
        "--output",
        dest="output",
        metavar="OUT",
        help="write cleaned image to OUT (default: overwrite FILE in place)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print a JSON summary to stdout",
    )
    args = parser.parse_args(argv)

    src = Path(args.file)
    dest = Path(args.output) if args.output else None

    try:
        raw = src.read_bytes()
        fmt = _detect_format(raw)
        cleaned = strip_image(raw)
        out_path = Path(dest) if dest is not None else src
        out_path.write_bytes(cleaned)
    except (OSError, ValueError) as exc:
        print(f"strip-exif: {exc}", file=sys.stderr)
        return 2

    if args.json:
        payload = {
            "path": str(out_path.resolve()),
            "format": fmt,
            "bytes_in": len(raw),
            "bytes_out": len(cleaned),
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print(str(out_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
