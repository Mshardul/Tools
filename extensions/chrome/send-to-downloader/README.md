# Send tab to downloader

**Backlog:** T-006 · `send-to-downloader`

Chrome extension + Python CLI: right-click or toolbar queues the tab URL into a local JSONL file that `cli/youtube-downloader` (T-002) can consume via `drain`.

Not for: rewriting youtube-downloader, cloud sync, or non-http(s) schemes.

## How it connects

```
Chrome (context menu / popup)
    → Native Messaging host (native/native_host.py)
        → send_to_downloader.add_entry(...)
            → ~/.config/tools/send-to-downloader/queue.jsonl

CLI: list / drain
    → pipe URLs into your existing downloader workflow
```

Queue line shape (one JSON object per line):

```json
{"ts":"2026-08-22T00:00:00+00:00","title":"Optional","url":"https://youtu.be/…"}
```

## CLI

```bash
cd extensions/chrome/send-to-downloader
python3 send_to_downloader.py -h
python3 send_to_downloader.py add 'https://youtu.be/dQw4w9WgXcQ' --title 'Example'
python3 send_to_downloader.py list
python3 send_to_downloader.py list --json
python3 send_to_downloader.py drain          # print URLs, clear queue
python3 send_to_downloader.py drain --keep   # print without clearing
```

Overrides:

| Flag / env | Effect |
|---|---|
| `--queue PATH` | Queue JSONL path |
| `--config PATH` | YAML with optional `queue:` key |
| `$TOOLS_SEND_TO_DOWNLOADER_CONFIG` | Default config path |

Default queue: `~/.config/tools/send-to-downloader/queue.jsonl`  
Default config: `~/.config/tools/send-to-downloader.yaml`

Pipe into the downloader (example):

```bash
python3 send_to_downloader.py drain | while read -r url _; do
  # hand each URL to your T-002 youtube-downloader entrypoint
  echo "$url"
done
```

## Install — CLI

No venv. Python 3.10+ stdlib only.

```bash
cd extensions/chrome/send-to-downloader
python3 send_to_downloader.py -h
PYTHONPATH=. python3 -m unittest tests.test_send_to_downloader -v
```

## Install — unpacked Chrome extension

1. Open `chrome://extensions`, enable **Developer mode**.
2. **Load unpacked** → select this folder (`extensions/chrome/send-to-downloader`).
3. Copy the extension **ID** from the card.

## Install — Native Messaging host (macOS)

Preferred path for the extension to write the queue without manual CLI.

1. Make the host executable:

   ```bash
   chmod +x native/native_host.py
   ```

2. Copy the sample manifest and edit absolute paths + extension ID:

   ```bash
   cp native/com.tools.send_to_downloader.json.sample \
     ~/Library/Application\ Support/Google/Chrome/NativeMessagingHosts/com.tools.send_to_downloader.json
   ```

   Set:

   - `"path"` → absolute path to `native/native_host.py` in this leaf
   - `"allowed_origins"` → `["chrome-extension://<YOUR_EXTENSION_ID>/"]`

3. Reload the extension. Use the toolbar popup or right-click **Send to Tools downloader**.

Chromium / Brave use a different `NativeMessagingHosts` directory under their Application Support folder; same JSON shape.

### Fallback without Native Messaging

If the host is not installed:

1. Copy the tab URL manually, then:

   ```bash
   python3 send_to_downloader.py add 'https://…' --title '…'
   ```

2. Or save a one-line `.url.txt` from Downloads into the queue later with `add`.

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_send_to_downloader -v
python3 send_to_downloader.py -h
```

## Limitations

- Native Messaging requires a one-time host manifest install with the real extension ID; unpacked IDs change if you move the folder.
- Extension only queues `http`/`https` tab/link URLs.
- Does not invoke youtube-downloader; `drain` is the integration point.
- No Windows/Linux host install docs in this MVP (manifest location differs).
