#!/usr/bin/env python3
"""Convert among hex, rgb, and hsl color formats."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys


def detect_format(value: str) -> str:
    text = value.strip()
    if re.match(r"^hsl\s*\(", text, re.IGNORECASE) or "%" in text:
        return "hsl"
    if re.match(r"^rgb\s*\(", text, re.IGNORECASE):
        return "rgb"
    if re.match(r"^#?[0-9a-fA-F]{3}$", text) or re.match(r"^#?[0-9a-fA-F]{6}$", text):
        return "hex"
    if re.match(r"^[\d,\s]+$", text) and text.count(",") >= 2:
        return "rgb"
    if re.match(r"^[\d,\s.]+%", text) or ("," in text and "%" in text):
        return "hsl"
    raise ValueError(f"could not detect color format from {value!r}")


def parse_color(value: str, fmt: str) -> tuple[int, int, int]:
    text = value.strip()
    fmt = fmt.lower()
    if fmt == "hex":
        text = text.lstrip("#")
        if len(text) == 3:
            text = "".join(ch * 2 for ch in text)
        if len(text) != 6 or not re.fullmatch(r"[0-9a-fA-F]{6}", text):
            raise ValueError(f"invalid hex color: {value!r}")
        r = int(text[0:2], 16)
        g = int(text[2:4], 16)
        b = int(text[4:6], 16)
        return r, g, b
    if fmt == "rgb":
        match = re.match(r"^rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$", text, re.IGNORECASE)
        if match:
            parts = [int(match.group(i)) for i in range(1, 4)]
        else:
            parts = [int(p.strip()) for p in re.split(r"[\s,]+", text) if p.strip()]
            if len(parts) != 3:
                raise ValueError(f"invalid rgb color: {value!r}")
        for channel in parts:
            if not 0 <= channel <= 255:
                raise ValueError(f"rgb channel out of range 0-255: {channel}")
        return parts[0], parts[1], parts[2]
    if fmt == "hsl":
        match = re.match(
            r"^hsl\s*\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*\)$",
            text,
            re.IGNORECASE,
        )
        if match:
            h = float(match.group(1))
            s = float(match.group(2))
            l = float(match.group(3))
        else:
            parts = [p.strip() for p in text.split(",")]
            if len(parts) != 3:
                raise ValueError(f"invalid hsl color: {value!r}")
            h = float(parts[0])
            s = float(parts[1].rstrip("%"))
            l = float(parts[2].rstrip("%"))
        if not 0 <= h <= 360:
            raise ValueError(f"hue out of range 0-360: {h}")
        for name, pct in (("saturation", s), ("lightness", l)):
            if not 0 <= pct <= 100:
                raise ValueError(f"{name} out of range 0-100%: {pct}")
        return hsl_to_rgb(h, s, l)
    raise ValueError(f"unknown format: {fmt!r}")


def rgb_to_hsl(r: int, g: int, b: int) -> tuple[float, float, float]:
    rf, gf, bf = r / 255, g / 255, b / 255
    max_c = max(rf, gf, bf)
    min_c = min(rf, gf, bf)
    lightness = (max_c + min_c) / 2
    if max_c == min_c:
        hue = 0.0
        saturation = 0.0
    else:
        delta = max_c - min_c
        saturation = delta / (2 - max_c - min_c) if lightness > 0.5 else delta / (max_c + min_c)
        if max_c == rf:
            hue = (gf - bf) / delta + (6 if gf < bf else 0)
        elif max_c == gf:
            hue = (bf - rf) / delta + 2
        else:
            hue = (rf - gf) / delta + 4
        hue *= 60
    return hue, saturation * 100, lightness * 100


def hsl_to_rgb(h: float, s: float, l: float) -> tuple[int, int, int]:
    if not 0 <= h <= 360:
        raise ValueError(f"hue out of range 0-360: {h}")
    for name, pct in (("saturation", s), ("lightness", l)):
        if not 0 <= pct <= 100:
            raise ValueError(f"{name} out of range 0-100%: {pct}")
    h_norm = (h % 360) / 360
    s_norm = s / 100
    l_norm = l / 100
    if s_norm == 0:
        channel = round(l_norm * 255)
        return channel, channel, channel
    if l_norm < 0.5:
        temp2 = l_norm * (1 + s_norm)
    else:
        temp2 = l_norm + s_norm - l_norm * s_norm
    temp1 = 2 * l_norm - temp2

    def hue_to_rgb(p: float, q: float, t: float) -> float:
        if t < 0:
            t += 1
        if t > 1:
            t -= 1
        if t < 1 / 6:
            return p + (q - p) * 6 * t
        if t < 1 / 2:
            return q
        if t < 2 / 3:
            return p + (q - p) * (2 / 3 - t) * 6
        return p

    q = temp2 if l_norm < 0.5 else temp1 + s_norm * (1 - abs(2 * l_norm - 1))
    p = 2 * l_norm - q
    r = hue_to_rgb(p, q, h_norm + 1 / 3)
    g = hue_to_rgb(p, q, h_norm)
    b = hue_to_rgb(p, q, h_norm - 1 / 3)
    return round(r * 255), round(g * 255), round(b * 255)


def _format_pct(value: float) -> str:
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return f"{value:.1f}"


def format_color(r: int, g: int, b: int, fmt: str) -> str:
    fmt = fmt.lower()
    if fmt == "hex":
        return f"#{r:02x}{g:02x}{b:02x}"
    if fmt == "rgb":
        return f"rgb({r}, {g}, {b})"
    if fmt == "hsl":
        h, s, l = rgb_to_hsl(r, g, b)
        return f"hsl({int(round(h))}, {_format_pct(s)}%, {_format_pct(l)}%)"
    raise ValueError(f"unknown format: {fmt!r}")


def convert_color(value: str, *, from_fmt: str | None, to_fmt: str) -> str:
    source = from_fmt or detect_format(value)
    r, g, b = parse_color(value, source)
    return format_color(r, g, b, to_fmt)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Convert among hex, rgb, and hsl colors.")
    parser.add_argument(
        "--from",
        dest="from_fmt",
        choices=("hex", "rgb", "hsl"),
        help="source format (auto-detect if omitted)",
    )
    parser.add_argument(
        "--to",
        dest="to_fmt",
        choices=("hex", "rgb", "hsl"),
        required=True,
        help="target format",
    )
    parser.add_argument("value", nargs="?", help="color value (default: stdin)")
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
        print("color-convert: no input (pass a color or pipe stdin)", file=sys.stderr)
        return 2

    try:
        out = convert_color(value, from_fmt=args.from_fmt, to_fmt=args.to_fmt)
    except ValueError as exc:
        print(f"color-convert: {exc}", file=sys.stderr)
        return 2

    print(out)
    if args.copy:
        try:
            subprocess.run(["pbcopy"], input=out.encode("utf-8"), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"color-convert: could not copy to clipboard: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
