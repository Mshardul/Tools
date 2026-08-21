# Data format convert

**Backlog:** T-034 · `data-convert`

Convert among json, yaml, toml, csv, and env.

## Usage

```bash
cd cli/data-convert
python3 data_convert.py --from json --to env data.json
python3 data_convert.py --from json --to csv -o out.csv <<< '[{"a":1},{"a":2}]'
python3 data_convert.py --from toml --to json config.toml
cat config.yaml | python3 data_convert.py --from yaml --to json
# --from optional when FILE extension is known (.json .yaml .yml .toml .csv .env)
python3 data_convert.py --to json config.toml
```

Formats: `json`, `yaml`/`yml`, `toml`, `csv`, `env`.

YAML needs [PyYAML](https://pyyaml.org/) from the **repo-root** `.venv` (not a leaf venv):

```bash
# once, from Tools/
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

cd cli/data-convert
../../.venv/bin/python data_convert.py --from yaml --to json config.yaml
```

Without PyYAML installed in that venv, json/toml/csv/env still work; yaml conversion errors clearly. Leaf dep list: `requirements.txt` (aggregated at repo root).

## Not for

jq-style path queries (see `json-query`), Excel/spreadsheet files, or schema validation.
