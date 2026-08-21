# File snippets

**Backlog:** T-015 · `file-snippets`

List and show text snippets from a git-friendly folder of files (name = filename stem).

## Usage

```bash
cd cli/file-snippets

# list names (one per line), or as JSON
python3 file_snippets.py list
python3 file_snippets.py list --json

# print a snippet; optional clipboard copy (macOS pbcopy)
python3 file_snippets.py show greet
python3 file_snippets.py show greet -c

# override snippets directory (CLI wins over env over config)
python3 file_snippets.py --dir ~/my-snips list
TOOLS_FILE_SNIPPETS_DIR=~/my-snips python3 file_snippets.py list
```

Default directory is `./snippets` relative to the current working directory.

Optional config `~/.config/tools/file-snippets.yaml`:

```yaml
snippets_dir: ~/Documents/snippets
```

Priority: `--dir` > `$TOOLS_FILE_SNIPPETS_DIR` > config `snippets_dir` > `./snippets`.

Hidden files and directories are ignored. Missing directory or unknown name exits `2` with `file-snippets: …` on stderr.

## Not for

In-app keyword expansion (see `snippet-expand` / T-019) or clipboard history (see T-018).
