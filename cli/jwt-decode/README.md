# JWT decode

**Backlog:** T-011 · `jwt-decode`

Decode JWT header and payload without verifying the signature.

## Usage

```bash
cd cli/jwt-decode
python3 jwt_decode.py 'eyJhbGciOiJub25lIn0.eyJzdWIiOiIxMjMifQ.x'
python3 jwt_decode.py --json "$TOKEN"
pbpaste | python3 jwt_decode.py
```

## Not for

Signature verification, creating tokens, or refreshing OAuth sessions.
