# Color convert

**Backlog:** T-027 · `color-convert`

Convert among hex, rgb, and hsl color formats.

## Usage

```bash
cd cli/color-convert
python3 color_convert.py --to rgb '#ff8000'
python3 color_convert.py --to hex '255,128,0'
python3 color_convert.py --from hsl --to rgb 'hsl(120, 50%, 40%)'
echo -n '#339933' | python3 color_convert.py --to hsl
python3 color_convert.py --to hex 'rgb(255, 128, 0)' -c
```

## Not for

Color picking from images, palette generation, or named CSS colors (e.g. `rebeccapurple`).
