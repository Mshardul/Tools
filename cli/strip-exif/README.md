# Strip EXIF

**Backlog:** T-057 · `strip-exif`

Remove EXIF/GPS and text metadata from JPEG and PNG images (Python 3 stdlib only — no Pillow).

## Usage

```bash
cd cli/strip-exif
python3 strip_exif.py photo.jpg                 # overwrite in place
python3 strip_exif.py photo.jpg -o clean.jpg    # write to OUT
python3 strip_exif.py photo.png --json          # JSON summary on stdout
python3 strip_exif.py -h
```

## Behavior

| Format | Stripped | Kept |
|--------|----------|------|
| JPEG | APP1 (EXIF / XMP) | APP0 JFIF, SOS→EOI image data, other markers |
| PNG | `eXIf`, `tEXt`, `zTXt`, `iTXt`, `tIME` | IHDR, PLTE, IDAT, IEND, pHYs, sRGB, gAMA, cHRM, iCCP, … |

Non-JPEG/PNG inputs are refused with `strip-exif: …` on stderr (exit 2).

## API

```python
from pathlib import Path
from strip_exif import strip_image, strip_file

clean = strip_image(Path("photo.jpg").read_bytes())
strip_file(Path("photo.jpg"))  # in place
strip_file(Path("in.png"), Path("out.png"))  # to dest
```

## Test

```bash
cd cli/strip-exif
PYTHONPATH=. python3 -m unittest tests.test_strip_exif -v
```

## Not for

Batch folder walks, HEIC/WebP, or re-encoding / resizing images (use a dedicated image tool).
