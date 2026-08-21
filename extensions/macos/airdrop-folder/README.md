# AirDrop folder

**Backlog:** T-091 · `airdrop-folder`

Open AirDrop and select one or more files/folders in Finder so you can share them (CLI + optional Finder Quick Action helper).

Not for: transferring files without AirDrop UI, Bluetooth pairing, or non-macOS platforms.

## Usage

```bash
python3 airdrop_folder.py ~/Desktop/photo.jpg
python3 airdrop_folder.py ./report.pdf ./slides/
python3 airdrop_folder.py --json ~/Downloads/archive.zip
python3 airdrop_folder.py -h
```

Plain success prints each resolved path (one per line). `--json` prints:

```json
{"ok": true, "paths": ["/absolute/path/to/file"]}
```

Errors go to stderr with the `airdrop-folder:` prefix.

## What it does

1. Resolves and validates every path (`~` expanded; missing paths fail).
2. Runs AppleScript to **reveal + select** those items in Finder.
3. Opens `/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app`.

You still pick a nearby device in the AirDrop window and complete the send yourself.

## Install / run

macOS only. Requires `osascript` and `open`.

```bash
cd extensions/macos/airdrop-folder
python3 airdrop_folder.py -h
PYTHONPATH=. python3 -m unittest tests.test_airdrop_folder -v
```

Optional symlink:

```bash
ln -s "$(pwd)/airdrop_folder.py" /usr/local/bin/airdrop-folder
```

## Finder Quick Action (optional)

1. Open **Automator** → **Quick Action**.
2. Workflow receives **files or folders** from **Finder**.
3. Add **Run Shell Script**; pass input **as arguments**.
4. Script body (adjust the path to this repo):

```bash
/usr/bin/python3 /ABS/PATH/TO/Tools/extensions/macos/airdrop-folder/airdrop_folder.py "$@"
```

5. Save as e.g. **AirDrop Selected**.
6. In Finder: select items → right-click → **Quick Actions** → **AirDrop Selected**.

Grant Automation / Finder access if macOS prompts.

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_airdrop_folder -v
```

## Limitations

- Opens AirDrop UI and selects items; it does not auto-send to a named device.
- AirDrop must be enabled (Control Center / Finder AirDrop settings).
- Target devices must be in range with AirDrop receiving allowed.
- Finder selection + AirDrop window is the pragmatic share path; there is no public stable “share sheet” CLI API.
