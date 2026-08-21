# Trash

**Backlog:** T-046 · `trash`

Move files or folders to the macOS Trash (recoverable), not `rm`.

Not for: secure erase or emptying Trash (see T-052).

## Usage

```bash
python3 trash.py ./old-file.txt
python3 trash.py ./a ./b
python3 trash.py --method finder ./old-file.txt   # optional Finder path
```

Default method is **`home`** (`~/.Trash`). Finder is off unless you ask for it.

## Config (YAML)

Copy [`config.sample.yaml`](config.sample.yaml) to `~/.config/tools/trash.yaml`, or set `TOOLS_TRASH_CONFIG` to a file path.

```yaml
method: home    # or finder
```

CLI `--method` overrides the config file.

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_trash -v
```
