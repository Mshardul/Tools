# Line sort

**Backlog:** T-030 · `line-sort`

Sort, dedupe, or reverse lines from stdin or a file.

## Usage

```bash
cd cli/line-sort
printf 'c\na\nb\n' | python3 line_sort.py
python3 line_sort.py -u words.txt
python3 line_sort.py -r -u words.txt
python3 line_sort.py /path/to/file.txt
```

## Not for

Locale-aware collation, numeric sorting, or field/column-based sorts (use `sort(1)`).
