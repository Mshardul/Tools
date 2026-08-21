# Cron explain

**Backlog:** T-033 · `cron-explain`

Explain a standard 5-field cron expression in plain English.

Not for: 6-field (seconds) cron, Quartz/`?` syntax, or scheduling jobs.

## Usage

```bash
cd cli/cron-explain
python3 cron_explain.py '*/15 * * * *'
python3 cron_explain.py 0 22 '*' '*' 1-5
python3 cron_explain.py '5 4 * jan sun'
```

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_cron_explain -v
```
