# Mic mute toggle

**Backlog:** T-049 · `mic-mute`

Mute, unmute, or toggle the macOS microphone by setting input volume via AppleScript (`osascript`). No Input Monitoring permission.

Not for: per-app mute, Control Center UI automation, or non-macOS systems.

## Usage

```bash
python3 mic_mute.py mute
python3 mic_mute.py unmute
python3 mic_mute.py toggle
python3 mic_mute.py status
python3 mic_mute.py toggle --notify
python3 mic_mute.py status --json
python3 mic_mute.py mute --config ~/.config/tools/mic-mute.yaml
```

- **mute** — set input volume to `0`; save previous volume to state file
- **unmute** — restore saved volume (default `50` if none)
- **toggle** — unmute if volume is `0`, else mute
- **status** — print muted/unmuted and current input volume

State file (`~/.config/tools/mic-mute.yaml` by default):

```yaml
last_input_volume: 75
```

`--notify` posts a macOS notification after mute/unmute/toggle.

## Install / run

macOS only. Requires `osascript`.

```bash
cd extensions/macos/mic-mute
python3 mic_mute.py -h
PYTHONPATH=. python3 -m unittest tests.test_mic_mute -v
```

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_mic_mute -v
```
