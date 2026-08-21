# Focus toggle

**Backlog:** T-050 · `focus-toggle`

Turn macOS Focus / Do Not Disturb on, off, or toggle by running user-named Shortcuts (no Accessibility click-hacking).

Not for: detecting live Focus state via undocumented `defaults`, or controlling Focus without Shortcuts you create in the Shortcuts app.

## Usage

```bash
python3 focus_toggle.py on
python3 focus_toggle.py off
python3 focus_toggle.py toggle
python3 focus_toggle.py status
python3 focus_toggle.py status --json
python3 focus_toggle.py toggle --shortcut "Toggle Focus"
python3 focus_toggle.py on --config ~/.config/tools/focus-toggle.yaml
```

Create three Shortcuts (or one toggle) in the Shortcuts app with names matching config defaults:

| key | default name |
|---|---|
| `shortcut_on` | `Focus On` |
| `shortcut_off` | `Focus Off` |
| `shortcut_toggle` | `Toggle Focus` |

Example `~/.config/tools/focus-toggle.yaml`:

```yaml
shortcut_on: Focus On
shortcut_off: Focus Off
shortcut_toggle: Toggle Focus
```

`status` reports whether the `shortcuts` binary exists and the configured names (it does not claim live Focus state).

## Install / run

macOS only. Requires the `shortcuts` CLI (Shortcuts app).

```bash
cd extensions/macos/focus-toggle
python3 focus_toggle.py -h
PYTHONPATH=. python3 -m unittest tests.test_focus_toggle -v
```

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_focus_toggle -v
```
