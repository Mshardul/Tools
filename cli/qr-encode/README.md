# QR encode

**Backlog:** T-028 · `qr-encode`

Encode text as a QR PNG or terminal ASCII art.

Status: active

## Setup

Needs the **repo-root** `.venv` (not a leaf venv) with deps installed:

```bash
# once, from Tools/
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Leaf pin: `requirements.txt` (`qrcode[pil]`). Parent aggregates it into the root requirements file.

## Usage

```bash
cd cli/qr-encode
../../.venv/bin/python qr_encode.py "hello world"
../../.venv/bin/python qr_encode.py --ascii "hello"
../../.venv/bin/python qr_encode.py -o out.png "https://example.com"
echo -n "piped" | ../../.venv/bin/python qr_encode.py -
../../.venv/bin/python qr_encode.py -   # read stdin
```

- Default (no `-o`): ASCII QR on stdout (same as `--ascii` / `-a`).
- `-o PATH.png`: write a PNG (needs pillow via `qrcode[pil]`).
- Empty text → stderr `qr-encode: …`, exit 2.

## Tests

```bash
cd cli/qr-encode
../../.venv/bin/python -m unittest discover -s tests -v
```

## Not for

Decoding QR images, styling/branding QR codes, or batch gallery UIs.
