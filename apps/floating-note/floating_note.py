#!/usr/bin/env python3
"""Always-on-top scratchpad that saves to a local file."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

DEFAULT_NOTE_PATH = Path.home() / ".local" / "share" / "tools" / "floating-note.txt"


def default_path() -> Path:
    return Path.home() / ".local" / "share" / "tools" / "floating-note.txt"


def load_text(path: Path | str) -> str:
    p = Path(path)
    if not p.is_file():
        return ""
    return p.read_text(encoding="utf-8")


def save_text(path: Path | str, text: str) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


def _display_available() -> bool:
    if os.environ.get("TK_SILENT"):
        return False
    # macOS usually has a display in a real session; CI / headless may not.
    if sys.platform == "darwin":
        return True
    return bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


def launch_gui(note_path: Path) -> int:
    if not _display_available():
        print(
            "floating-note: no display (unset TK_SILENT / need a real GUI session)",
            file=sys.stderr,
        )
        return 1

    try:
        import tkinter as tk
        from tkinter import messagebox
    except ImportError as exc:
        print(f"floating-note: tkinter unavailable: {exc}", file=sys.stderr)
        return 1

    root = tk.Tk()
    root.title("Scratch")
    root.attributes("-topmost", True)

    text = tk.Text(root, wrap="word", undo=True)
    text.pack(fill="both", expand=True)
    text.insert("1.0", load_text(note_path))

    def do_save(_event=None) -> str:
        save_text(note_path, text.get("1.0", "end-1c"))
        return "break"

    def on_close() -> None:
        try:
            do_save()
        except OSError as exc:
            messagebox.showerror("floating-note", str(exc))
            return
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", on_close)
    root.bind("<Command-s>", do_save)
    root.bind("<Control-s>", do_save)
    root.mainloop()
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Always-on-top scratchpad saved to a local file.",
    )
    parser.add_argument(
        "--file",
        type=Path,
        default=None,
        help=f"note file (default: {DEFAULT_NOTE_PATH})",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=None,
        help="optional config path (reserved; unused in v1)",
    )
    args = parser.parse_args(argv)

    note_path = args.file if args.file is not None else default_path()

    try:
        return launch_gui(note_path)
    except OSError as exc:
        print(f"floating-note: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
