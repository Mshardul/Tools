# Clipboard CLI

**Backlog:** T-043 · `pb`

Read or write the macOS clipboard via `pbpaste` / `pbcopy`.

Not for: clipboard *history* (see T-018).

## Usage

```bash
python3 pb.py                  # print clipboard
python3 pb.py -w 'hello'       # write text
echo 'hello' | python3 pb.py -w
echo 'hello' | python3 pb.py   # pipe write
```
