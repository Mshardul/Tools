# JSON query

**Backlog:** T-069 · `json-query`

Tiny path query on JSON (jq-lite). Select a value by dot keys and array indexes from a file or stdin.

## Usage

```bash
cd cli/json-query
echo '{"items":[{"name":"a"}]}' | python3 json_query.py 'items[0].name'
python3 json_query.py foo.bar data.json
python3 json_query.py .foo.bar data.json
```

## Path syntax

| Form | Meaning |
|---|---|
| `foo.bar` or `.foo.bar` | Nested object keys (leading `.` optional) |
| `items[0]` | Array index (0-based) |
| `items[0].name` | Mix keys and indexes |
| `.` or empty | Whole document |

v1 does not require escaping; keys are simple identifiers (`[A-Za-z_][A-Za-z0-9_]*`).

## Output

All results use `json.dumps` (`ensure_ascii=False`): compact for scalars (so strings are quoted), `indent=2` plus a trailing newline for objects and arrays.

Errors (invalid JSON, bad path, missing key) print `json-query: …` on stderr and exit `2`.

## Not for

Pretty-print/minify only (see `json-format`) or format conversion (see `data-convert`).
