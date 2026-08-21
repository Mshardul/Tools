#!/usr/bin/env python3
"""Resize, compress, or convert images (Pillow)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

FORMAT_ALIASES = {
    "jpg": "JPEG",
    "jpeg": "JPEG",
    "png": "PNG",
    "webp": "WEBP",
    "gif": "GIF",
    "tif": "TIFF",
    "tiff": "TIFF",
    "bmp": "BMP",
}


def _normalize_format(fmt: str) -> str:
    key = fmt.strip().lower().lstrip(".")
    if key not in FORMAT_ALIASES:
        raise ValueError(f"unsupported format: {fmt!r}")
    return FORMAT_ALIASES[key]


def _open_rgb_compatible(src: Path) -> Image.Image:
    img = Image.open(src)
    img.load()
    return img


def _save(img: Image.Image, dest: Path, fmt: str, quality: int | None = None) -> None:
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    kwargs: dict = {}
    if fmt == "JPEG":
        if img.mode in ("RGBA", "LA", "P"):
            img = img.convert("RGB")
        kwargs["quality"] = 85 if quality is None else quality
        kwargs["optimize"] = True
    elif fmt == "WEBP":
        kwargs["quality"] = 80 if quality is None else quality
    elif fmt == "PNG" and quality is not None:
        # Pillow PNG: compress_level 0-9; map quality 1-100 roughly.
        kwargs["optimize"] = True
        kwargs["compress_level"] = max(0, min(9, round((100 - quality) / 11)))
    img.save(dest, format=fmt, **kwargs)


def resize_image(
    src: Path | str,
    dest: Path | str,
    width: int | None = None,
    height: int | None = None,
) -> Path:
    if width is None and height is None:
        raise ValueError("resize requires --width and/or --height")
    if width is not None and width < 1:
        raise ValueError("width must be >= 1")
    if height is not None and height < 1:
        raise ValueError("height must be >= 1")

    src_p, dest_p = Path(src), Path(dest)
    with _open_rgb_compatible(src_p) as img:
        ow, oh = img.size
        if width is not None and height is not None:
            size = (width, height)
        elif width is not None:
            size = (width, max(1, round(oh * (width / ow))))
        else:
            assert height is not None
            size = (max(1, round(ow * (height / oh))), height)
        out = img.resize(size, Image.Resampling.LANCZOS)
        if dest_p.suffix:
            fmt = _normalize_format(dest_p.suffix)
        else:
            fmt = _normalize_format(img.format or "PNG")
        _save(out, dest_p, fmt)
    return dest_p


def convert_image(src: Path | str, dest: Path | str, fmt: str | None = None) -> Path:
    src_p, dest_p = Path(src), Path(dest)
    if fmt is None:
        if not dest_p.suffix:
            raise ValueError("convert needs --to or an output extension")
        fmt_norm = _normalize_format(dest_p.suffix)
    else:
        fmt_norm = _normalize_format(fmt)
    with _open_rgb_compatible(src_p) as img:
        _save(img, dest_p, fmt_norm)
    return dest_p


def compress_image(
    src: Path | str,
    dest: Path | str,
    quality: int = 70,
) -> Path:
    if quality < 1 or quality > 100:
        raise ValueError("quality must be 1..100")
    src_p, dest_p = Path(src), Path(dest)
    # Default compress output to JPEG when dest has no hint.
    if dest_p.suffix:
        fmt = _normalize_format(dest_p.suffix)
    else:
        fmt = "JPEG"
        dest_p = dest_p.with_suffix(".jpg")
    with _open_rgb_compatible(src_p) as img:
        _save(img, dest_p, fmt, quality=quality)
    return dest_p


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Resize, compress, or convert images.",
    )
    parser.add_argument("input", help="source image path")
    parser.add_argument(
        "-o",
        "--output",
        required=True,
        help="output image path",
    )
    parser.add_argument(
        "-m",
        "--mode",
        choices=("resize", "compress", "convert"),
        required=True,
        help="operation to perform",
    )
    parser.add_argument("--width", type=int, help="resize target width")
    parser.add_argument("--height", type=int, help="resize target height")
    parser.add_argument(
        "-q",
        "--quality",
        type=int,
        default=70,
        help="compress quality 1-100 (default: 70)",
    )
    parser.add_argument(
        "--to",
        dest="to_fmt",
        help="convert target format (jpeg, png, webp, …)",
    )
    parser.add_argument("--json", action="store_true", help="print JSON summary")
    args = parser.parse_args(argv)

    src = Path(args.input)
    dest = Path(args.output)

    try:
        if args.mode == "resize":
            out = resize_image(src, dest, width=args.width, height=args.height)
        elif args.mode == "compress":
            out = compress_image(src, dest, quality=args.quality)
        else:
            out = convert_image(src, dest, fmt=args.to_fmt)
    except (OSError, ValueError) as exc:
        print(f"image-tool: {exc}", file=sys.stderr)
        return 2

    if args.json:
        with Image.open(out) as img:
            w, h = img.size
            fmt = img.format
        print(
            json.dumps(
                {
                    "path": str(out),
                    "width": w,
                    "height": h,
                    "format": fmt,
                    "bytes": out.stat().st_size,
                },
                ensure_ascii=False,
            )
        )
    else:
        print(str(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
