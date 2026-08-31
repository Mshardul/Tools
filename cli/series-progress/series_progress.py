#!/usr/bin/env python3
"""Sidecar progress for which episode to resume in a folder."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SIDE_CAR = ".series-progress"
VIDEO_SUFFIXES = frozenset(
    {".mkv", ".mp4", ".avi", ".m4v", ".mov", ".wmv", ".webm", ".ts", ".m2ts"}
)


def list_episodes(folder: Path | str) -> list[str]:
    root = Path(folder)
    if not root.is_dir():
        raise NotADirectoryError(f"not a directory: {root}")
    names = [p.name for p in root.iterdir() if p.is_file() and p.suffix.lower() in VIDEO_SUFFIXES]
    return sorted(names, key=lambda s: s.casefold())


def load_progress(folder: Path | str) -> str | None:
    path = Path(folder) / SIDE_CAR
    if not path.is_file():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    current = data.get("current")
    if current is None or current == "":
        return None
    return str(current)


def save_progress(folder: Path | str, current: str) -> None:
    root = Path(folder)
    if not root.is_dir():
        raise NotADirectoryError(f"not a directory: {root}")
    payload = {"current": current}
    (root / SIDE_CAR).write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def next_episode(folder: Path | str) -> str | None:
    episodes = list_episodes(folder)
    if not episodes:
        return None
    current = load_progress(folder)
    if current is None:
        return episodes[0]
    try:
        idx = episodes.index(current)
    except ValueError:
        return episodes[0]
    if idx + 1 >= len(episodes):
        return None
    return episodes[idx + 1]


def mark_done(folder: Path | str) -> str | None:
    """Advance progress past the current episode. Return new current, or None at end."""
    episodes = list_episodes(folder)
    if not episodes:
        return None
    current = load_progress(folder)
    if current is None:
        # Unset: treat first as in-progress; advance to second (or stay on sole episode).
        if len(episodes) == 1:
            save_progress(folder, episodes[0])
            return None
        save_progress(folder, episodes[1])
        return episodes[1]
    try:
        idx = episodes.index(current)
    except ValueError:
        save_progress(folder, episodes[0])
        return episodes[0]
    if idx + 1 >= len(episodes):
        return None
    nxt = episodes[idx + 1]
    save_progress(folder, nxt)
    return nxt


def resume_target(folder: Path | str) -> str | None:
    """Episode to play now: saved current, else first episode."""
    current = load_progress(folder)
    if current is not None:
        return current
    return next_episode(folder)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Track which episode to resume in a folder (.series-progress).",
    )
    parser.add_argument(
        "folder",
        nargs="?",
        default=".",
        help="series folder (default: .)",
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--set", metavar="FILE", help="set current episode filename")
    group.add_argument(
        "--next",
        action="store_true",
        dest="show_next",
        help="print the next episode after current (or first if unset)",
    )
    group.add_argument(
        "--mark-done",
        action="store_true",
        help="advance progress to the next episode",
    )
    group.add_argument(
        "--list",
        action="store_true",
        dest="list_eps",
        help="list video episodes in the folder",
    )
    parser.add_argument("--json", action="store_true", help="print JSON summary")
    args = parser.parse_args(argv)

    folder = Path(args.folder).expanduser()

    try:
        if not folder.exists():
            raise FileNotFoundError(folder)
        if not folder.is_dir():
            raise NotADirectoryError(f"not a directory: {folder}")

        if args.set is not None:
            save_progress(folder, args.set)

        if args.mark_done:
            advanced = mark_done(folder)
            if advanced is None and load_progress(folder) is not None:
                # Already at last episode
                if args.json:
                    print(
                        json.dumps(
                            {
                                "folder": str(folder),
                                "current": load_progress(folder),
                                "next": None,
                                "advanced": False,
                            },
                            ensure_ascii=False,
                        )
                    )
                    return 0
                print("series-progress: already at last episode", file=sys.stderr)
                return 1
            if advanced is None:
                print("series-progress: no video episodes found", file=sys.stderr)
                return 1
            if args.json:
                print(
                    json.dumps(
                        {
                            "folder": str(folder),
                            "current": advanced,
                            "next": next_episode(folder),
                            "advanced": True,
                        },
                        ensure_ascii=False,
                    )
                )
            else:
                print(advanced)
            return 0

        if args.list_eps:
            episodes = list_episodes(folder)
            if args.json:
                print(json.dumps({"folder": str(folder), "episodes": episodes}))
            else:
                for name in episodes:
                    print(name)
            return 0

        current = load_progress(folder)
        nxt = next_episode(folder)
        resume = resume_target(folder)

        if args.show_next:
            if nxt is None:
                print("series-progress: no next episode", file=sys.stderr)
                return 1
            if args.json:
                print(
                    json.dumps(
                        {"folder": str(folder), "current": current, "next": nxt},
                        ensure_ascii=False,
                    )
                )
            else:
                print(nxt)
            return 0

        if args.json:
            print(
                json.dumps(
                    {
                        "folder": str(folder),
                        "current": current,
                        "next": nxt,
                        "resume": resume,
                        "sidecar": str(folder / SIDE_CAR),
                    },
                    ensure_ascii=False,
                )
            )
            return 0

        if resume is None:
            print("series-progress: no video episodes found", file=sys.stderr)
            return 1
        print(resume)
        return 0

    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"series-progress: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
