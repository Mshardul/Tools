# Port tool

**Backlog:** T-037 · `port-tool`

Show which process listens on a TCP port, or kill it.

Not for: firewall rules or UDP-only sockets.

## Usage

```bash
python3 port_tool.py 3000           # who (default)
python3 port_tool.py 3000 who
python3 port_tool.py 3000 kill
python3 port_tool.py 3000 kill -f   # SIGKILL
```

## Test

```bash
PYTHONPATH=. python3 -m unittest tests.test_port_tool -v
```
