# URL encode/decode

**Backlog:** T-022 · `url-encode`

Percent-encode or decode a string (mode select).

## Usage

```bash
cd cli/url-encode
python3 url_encode.py -m encode 'a b'
python3 url_encode.py -m decode 'a%20b'
echo -n 'hello world' | python3 url_encode.py -m encode
python3 url_encode.py -m encode 'x' -c
```

## Not for

Parsing full URLs into components, or HTML entity encoding (see `html-entities`).
