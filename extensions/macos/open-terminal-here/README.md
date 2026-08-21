# Open Terminal here

**Backlog:** T-089 · `open-terminal-here`

Open Terminal (or iTerm) at a folder. macOS only. Stdlib + `open`.

```bash
# from repo root
.venv/bin/python extensions/macos/open-terminal-here/open_terminal_here.py ~/Projects/foo
.venv/bin/python extensions/macos/open-terminal-here/open_terminal_here.py some/file.txt   # opens parent dir
.venv/bin/python extensions/macos/open-terminal-here/open_terminal_here.py -a iTerm .
```

Prints the folder path opened. Errors go to stderr with an `open-terminal-here:` prefix.

## Finder Quick Action

1. Open **Automator** → **Quick Action**.
2. Workflow receives: **folders** (or **files or folders**) in **Finder**.
3. Add **Run Shell Script**; pass input **as arguments**.
4. Script (adjust repo path):

```bash
REPO="/Users/YOU/Documents/Github/Tools"
"$REPO/.venv/bin/python" "$REPO/extensions/macos/open-terminal-here/open_terminal_here.py" "$@"
```

5. Save as **Open Terminal Here**. In Finder: right-click a folder → **Quick Actions**.

**Not for:** Linux/Windows terminals, or replacing `cd` inside an already-open shell.
