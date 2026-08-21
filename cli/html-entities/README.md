# HTML entities

**Backlog:** T-023 · `html-entities`

Encode or decode HTML entities (mode select).

## Usage

```bash
cd cli/html-entities
python3 html_entities.py -m encode '<a href="x">&</a>'
python3 html_entities.py -m decode '&lt;hello&gt;'
echo 'Say "hi"' | python3 html_entities.py -m encode
python3 html_entities.py -m encode 'x' -c
```

## Not for

URL percent-encoding (see `url-encode`), or sanitizing untrusted HTML for safe display in a browser.
