# Claude Usage Dashboard

Browser-based dashboard showing token usage from Claude Code sessions. Reads data directly from local Claude files — no server, no API, no cloud.

## Setup

One-time setup (run from this directory):

```bash
ln -s ~/.claude/usage.db usage.db
ln -s ~/.claude/projects projects
python3 -m http.server 8080
```

Open **http://localhost:8080/claude-usage/**

## How it works

Data comes from two sources:

| Source | What | When |
|---|---|---|
| `~/.claude/usage.db` | SQLite — sessions + turns up to last indexed date | Fast, pre-aggregated |
| `~/.claude/projects/**/*.jsonl` | Raw conversation files — everything after DB cutoff | Parsed on load |

On page load, `app.js` reads the DB for historical data, then scans for any JSONL files not yet indexed and parses them. Both sources are merged into `window.CLAUDE_DATA`.

## Dashboard sections

- **Stats bar** — sessions, turns, input tokens, cache tokens
- **Token usage over time** — area chart, daily breakdown by token type
- **Usage by project** — horizontal bar chart sorted by total tokens
- **Activity heatmap** — GitHub-style calendar, intensity = daily token volume
- **Sessions table** — sortable list of all sessions with project, model, token counts

## Filters

Filters appear as dismissible pills at the top. Click **+ Date**, **+ Project**, or **+ Model** to add. Active filters apply to all charts and the table.

| Filter | Options |
|---|---|
| Date | 7d · 30d · 90d · All · custom range |
| Project | Any project from your sessions |
| Model | Any model seen in sessions |

Click **↺ Refresh** to re-read from disk (picks up new sessions since last load).

## Data shape (`window.CLAUDE_DATA`)

```js
{
  meta: {
    generated_at,           // ISO timestamp of last load
    date_range: { from, to },
    total_sessions,
    total_turns,
    models: []              // unique model names
  },
  sessions: [{
    session_id, project_name, model, git_branch,
    first_timestamp, last_timestamp, turn_count,
    total_input_tokens, total_output_tokens,
    total_cache_read, total_cache_creation
  }],
  daily: [{
    date, sessions, turns,
    input_tokens, output_tokens,
    cache_read_tokens, cache_creation_tokens
  }]
}
```

Available in browser console — useful for ad-hoc queries.

## Files

```
claude-usage/
├── index.html     # dashboard UI
├── app.js         # data layer (reads DB + JSONL, exposes window.CLAUDE_DATA)
├── usage.db -> ~/.claude/usage.db        # symlink
└── projects -> ~/.claude/projects        # symlink
```
