# ID generator

**Backlog:** T-009 · `id-gen`

Generate ids; choose type (`uuid` or `nanoid`).

Not for: cryptographic key material or sequential database ids.

## Usage

```bash
python3 id_gen.py                 # uuid
python3 id_gen.py -t nanoid
python3 id_gen.py -t nanoid -l 12 -n 3
python3 id_gen.py -c              # copy last id (macOS)
```

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_id_gen -v
```
