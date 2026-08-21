# Floating scratch note

**Backlog:** T-017 · `floating-note`

Always-on-top scratchpad (tkinter) that loads/saves a local text file. Title is **Scratch**. Saves on window close and Cmd/Ctrl-S.

Not for: synced notes, rich text, or multi-window layouts.

## Usage

```bash
python3 floating_note.py
python3 floating_note.py --file ~/Desktop/scratch.txt
```

Default file: `~/.local/share/tools/floating-note.txt` (parent dirs created on save).

`--config PATH` is accepted for future use; v1 ignores it.

### GUI / headless notes

The GUI needs a real desktop session. Unit tests cover only file helpers (`default_path`, `load_text`, `save_text`) and do not open a window.

- Set `TK_SILENT=1` to refuse launching the GUI (useful in scripts).
- If tkinter is missing or there is no display, the CLI exits non-zero with a `floating-note:` error on stderr.

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_floating_note -v
```
