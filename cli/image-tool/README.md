# Image tool

**Backlog:** T-054 · `image-tool`

Resize, compress, or convert images with Pillow.

```bash
# from repo root (shared .venv)
.venv/bin/pip install -r requirements.txt   # once

.venv/bin/python cli/image-tool/image_tool.py -m resize in.png -o out.png --width 800
.venv/bin/python cli/image-tool/image_tool.py -m compress photo.png -o photo.jpg -q 60
.venv/bin/python cli/image-tool/image_tool.py -m convert in.png -o out.webp --to webp
```

Modes:

| Mode | Flags | Notes |
|---|---|---|
| `resize` | `--width` and/or `--height` | Aspect preserved if only one is set |
| `compress` | `-q` / `--quality` (1–100) | Defaults to JPEG when output has no extension |
| `convert` | `--to` or output extension | jpeg, png, webp, gif, tiff, bmp |

`--json` prints `{path,width,height,format,bytes}`.

**Not for:** stripping EXIF only (use `strip-exif`), or batch gallery GUIs.
