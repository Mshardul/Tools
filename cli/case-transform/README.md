# Case transform

**Backlog:** T-024 · `case-transform`

Convert among camel, snake, kebab, and Pascal case.

## Usage

```bash
cd cli/case-transform
python3 case_transform.py -t snake 'HelloWorld'
python3 case_transform.py -t camel 'hello_world'
python3 case_transform.py -t pascal 'hello-world'
python3 case_transform.py -t kebab 'HelloWorld' -c
```

## Not for

Full sentence title-casing, locale-aware Unicode case folding, or slugify (see `slugify`).
