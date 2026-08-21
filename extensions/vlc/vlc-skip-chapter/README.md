# VLC skip chapter by name

**Backlog:** T-005 · `vlc-skip-chapter`

Auto-skip MKV (and other chapter-aware) titles named Intro, Credits, and similar — via a VLC Lua extension, with a small Python helper to test names and install the script.

Standalone: does **not** require `vlc-file-memory` (T-003).

Not for: AI / silence-based intro detection, editing chapter markers, or controlling VLC remotely beyond this extension.

## Install (macOS)

From this directory:

```bash
python3 vlc_skip_chapter.py install
# preview only:
python3 vlc_skip_chapter.py install --dry-run
```

This copies `skip_chapter.lua` into VLC’s user Lua **extensions** folder (creates parents if needed):

`~/Library/Application Support/org.videolan.vlc/lua/extensions/`

(Some older notes mention `…/lua/intf/` for interface scripts; this tool installs an **extension**, so use `extensions/`.)

Then restart VLC (or reload extensions) and enable:

**View → Extensions → Skip Intro/Credits Chapters**

Keep the extension enabled while watching; it reacts to input/metadata (chapter) changes and jumps to the next chapter when the current title matches the skip list.

## Defaults

Skip patterns (case-insensitive): `intro`, `credits`, `opening`, `ending`, `outro`.

A title matches if it equals a pattern, starts with a pattern plus a common separator (` `, `-`, `_`, `:`, `.`, `/`, `()`, `[]`), or contains the pattern as a whole word (e.g. `Opening Credits`, `The Intro`).

## Python helper

```bash
# print skip|keep — exit 0 = skip, 1 = keep
python3 vlc_skip_chapter.py check "Intro"
python3 vlc_skip_chapter.py check "Chapter 01"
python3 vlc_skip_chapter.py check "Preview" --pattern preview --json
```

`--pattern` is repeatable and replaces the default list when provided.

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_vlc_skip_chapter -v
```
