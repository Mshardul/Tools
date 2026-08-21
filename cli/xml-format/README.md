# XML format

**Backlog:** T-068 · `xml-format`

Pretty-print or minify XML from stdin or a file.

## Usage

```bash
cd cli/xml-format
echo '<root><a>1</a></root>' | python3 xml_format.py
python3 xml_format.py -m minify data.xml
python3 xml_format.py -m pretty data.xml
```

Default mode is pretty (2-space indent). `-m minify` strips ignorable whitespace between elements.

## Not for

XPath / querying XML trees, or converting XML to JSON/YAML (use other leaves).
