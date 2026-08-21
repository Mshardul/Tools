# JSON format

**Backlog:** T-014 · `json-format`

Pretty-print or minify JSON from stdin or a file.

## Usage

```bash
cd cli/json-format
echo '{"a":1}' | python3 json_format.py
python3 json_format.py -m minify data.json
python3 json_format.py -m pretty data.json
```

## Not for

Querying JSON paths (see `json-query`) or converting to YAML/TOML (see `data-convert`).
