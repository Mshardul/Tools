# Timezone convert

**Backlog:** T-081 · `timezone-convert`

Convert a datetime across IANA timezones.

## Usage

```bash
cd cli/timezone-convert
python3 timezone_convert.py --to Asia/Kolkata '2026-08-21T10:00:00'
python3 timezone_convert.py --from UTC --to America/New_York '2026-08-21 10:00:00'
python3 timezone_convert.py --to Europe/London now
echo -n '2026-08-21T10:00:00+00:00' | python3 timezone_convert.py --to Asia/Kolkata -c
```

## Not for

Recurring rules (DST policy changes over history are handled by zoneinfo, but not RRULE scheduling).
