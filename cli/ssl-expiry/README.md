# SSL expiry

**Backlog:** T-075 · `ssl-expiry`

Days until a host's TLS certificate expires.

Not for: full certificate chain validation reports, OCSP/CRL checks, or non-TLS ports.

## Usage

```bash
python3 ssl_expiry.py example.com
python3 ssl_expiry.py example.com -p 443
python3 ssl_expiry.py example.com --json
```

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_ssl_expiry -v
```

Live smoke (needs network):

```bash
python3 ssl_expiry.py example.com
```
