# Ticket backlog — mic-mute

**Root id:** T-049  
**Publish:** github  
**License:** MIT (repo root)

Mute/unmute/toggle macOS mic input volume via AppleScript.

## Tickets

| id | title | status | notes |
|---|---|---|---|
| T-049-1 | Parse volume settings + decide toggle | done | `parse_volume_settings`, `decide_toggle` |
| T-049-2 | Load/save last input volume state | done | `~/.config/tools/mic-mute.yaml` |
| T-049-3 | mute / unmute / toggle / status via osascript | done | mocked in tests |
| T-049-4 | CLI (`--json`, `--notify`, macOS check) | done | `mic_mute.py` |
| T-049-5 | Unit tests (mock osascript) | done | `tests/test_mic_mute.py` |
| T-049-6 | README + this backlog | done | usage, install, Not for |
