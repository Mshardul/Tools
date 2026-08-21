# Slugify

**Backlog:** T-031 · `slugify`

Turn a title into a kebab-case slug (ASCII).

## Usage

```bash
cd cli/slugify
python3 slugify.py 'Hello, World!'
echo 'My Blog Post' | python3 slugify.py
python3 slugify.py 'Café Menu' -c
```

## Not for

Identifier case conversion (see `case-transform`) or preserving non-ASCII characters.
