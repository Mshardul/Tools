# Unix timestamp

**Backlog:** T-012 · `unix-timestamp`

Convert between unix time and ISO-8601 UTC dates.

## Usage

```bash
cd cli/unix-timestamp
python3 unix_timestamp.py 0
python3 unix_timestamp.py '1970-01-01T00:00:00Z'
python3 unix_timestamp.py -m from-unix 1700000000
python3 unix_timestamp.py -m to-unix '2023-11-14T22:13:20+00:00'
```

Default mode is `auto`: numeric → date, otherwise → unix.

## Not for

Timezone math across named zones (see `timezone-convert`) or calendar UI.
