# VLC per-file memory

**Backlog:** T-003 · `vlc-file-memory`

Remember audio track, subtitle track, and A/V delay **per file** when playing in VLC; restore on the next open of that file.

Not for: remembering playlist position / chapter, cloud sync, remote/HTTP streams with unstable URIs, or editing VLC preferences globally. Track restore is best-effort across VLC builds (player APIs vs `audio-es` / `spu-es` vars).

## Install (macOS)

From this directory:

```bash
python3 vlc_file_memory.py install
# preview only:
python3 vlc_file_memory.py install --dry-run
```

Copies `file_memory.lua` into VLC’s user Lua **extensions** folder:

`~/Library/Application Support/org.videolan.vlc/lua/extensions/`

Uninstall:

```bash
python3 vlc_file_memory.py uninstall
```

Restart VLC (or reload extensions) and enable:

**View → Extensions → Per-File Audio/Subtitle Memory**

Keep the extension enabled while watching. On input change it loads any saved settings for that file; on meta changes / deactivate it saves the current audio track, subtitle track, audio delay, and subtitle delay.

## Store

JSON file written by the Lua extension (same directory as the installed script):

`~/Library/Application Support/org.videolan.vlc/lua/extensions/file_memory_store.json`

- **Keys:** normalized filesystem paths (`file:///…` URIs are decoded; trailing slashes stripped).
- **Values:** `path`, `audio_track`, `spu_track`, `audio_delay`, `subtitle_delay` (delays in seconds).

## Python helper

```bash
python3 vlc_file_memory.py install
python3 vlc_file_memory.py uninstall --dry-run
# diagnostic: SHA-256 of the normalized path
python3 vlc_file_memory.py hash "file:///Movies/My%20Show.mkv"
```

Errors on stderr are prefixed with `vlc-file-memory:`.

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_vlc_file_memory -v
```
