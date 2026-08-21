# Number base convert

**Backlog:** T-095 · `number-base`

Convert integers among binary, octal, decimal, and hex.

## Usage

```bash
cd cli/number-base
python3 number_base.py --to hex 255
python3 number_base.py --to dec 0xFF
python3 number_base.py --from bin --to oct 0b1010
echo -n '1_000' | python3 number_base.py --to hex
python3 number_base.py --to bin -42 -c
```

## Not for

Floating-point radix conversion or arbitrary-precision math beyond Python int.
