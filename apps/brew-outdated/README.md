# Brew outdated

**Backlog:** T-092 · `brew-outdated`

CLI that runs `brew outdated --json=v2` and prints a structured count plus package names (formulae and casks). Nursery shape is **CLI-first** for launcher friendliness; a menu-bar host can call this later via subprocess/`--json`.

Not for: installing/upgrading packages, brew doctor, or non-Homebrew package managers.

## Usage

```bash
python3 brew_outdated.py
python3 brew_outdated.py --json
python3 brew_outdated.py --formulae-only
python3 brew_outdated.py --casks-only --json
```

- Default: `N outdated` then one package name per line
- `--json`: `{"count","formulae","casks"}`
- `--formulae-only` / `--casks-only`: filter (mutually exclusive)
- Inject fixture JSON for tests via `BREW_OUTDATED_JSON` or `fetch_brew_outdated_json(json_text=...)`

Errors are prefixed with `brew-outdated:` on stderr. Exit `1` if brew is missing or fails; `2` for bad flag combinations.

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_brew_outdated -v
```

Parsing and CLI paths use fixture JSON / mocked subprocess — no live Homebrew required in unit tests.

## Future

Menu-bar host that polls this CLI — out of scope for this leaf.
