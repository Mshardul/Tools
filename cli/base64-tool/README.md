# Base64 encode/decode

**Backlog:** T-010 · `base64-tool`

Encode or decode Base64 from an argument or stdin.

## Usage

```bash
cd cli/base64-tool
python3 base64_tool.py -m encode 'hi'
python3 base64_tool.py -m decode 'aGk='
echo -n 'hi' | python3 base64_tool.py -m encode
python3 base64_tool.py -m encode 'hi' -c   # copy (macOS pbcopy)
```

## Not for

Verifying JWT signatures, URL-safe Base64 variants as a separate mode, or binary file tooling beyond stdin/stdout pipes.
