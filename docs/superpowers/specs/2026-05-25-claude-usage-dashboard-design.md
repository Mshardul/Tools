# Claude Usage Dashboard — Enhanced Design

**Date:** 2026-05-25  
**Status:** Approved  
**Scope:** Add tab navigation + 12 new components to existing single-page dashboard

---

## Summary

Extend the existing `claude-usage/` dashboard from a single scrolling page into a 4-tab layout (Overview · Sessions · Analytics · Cost), adding 12 new components while keeping the zero-server, single-file architecture. All components are modular render functions with no coupling between tabs.

---

## Architecture

### File changes
- `claude-usage/app.js` — data layer additions only (3 new queries/utilities)
- `claude-usage/index.html` — tab shell + all new render functions in existing inline `<script>`

No new files. No schema changes.

### Component model

Every component follows this signature:
```js
renderXxx(data, containerEl)
```
- Takes filtered data and a DOM container
- Renders into that container, destroys/recreates on re-render
- No knowledge of which tab it lives in
- Can be moved to a different tab by changing only the tab render function

### Tab shell

```js
renderTabs()              // builds tab bar + panel DOM
switchTab(name)           // calls renderTab* for active tab with current filtered data
trigger()                 // existing — now calls renderTabActive() instead of renderAll()
```

Filter bar and filter state remain global, applied before any tab renders.

---

## Data Layer (`app.js`)

### New query: `queryTools(db)`
```sql
SELECT tool_name, COUNT(*) AS count
FROM turns
WHERE tool_name IS NOT NULL
GROUP BY tool_name
ORDER BY count DESC
```
Exposed as `CLAUDE_DATA.tools: { tool_name, count }[]`.  
Also built from JSONL entries via `buildToolsFromEntries(entries)`.

### New query: `queryHourly(db)`
```sql
SELECT
  CAST(strftime('%w', timestamp) AS INTEGER) AS dow,
  CAST(strftime('%H', timestamp) AS INTEGER) AS hour,
  SUM(input_tokens + output_tokens) AS tokens
FROM turns
GROUP BY dow, hour
```
Exposed as `CLAUDE_DATA.hourly: { dow, hour, tokens }[]` (dow: 0=Sun…6=Sat).  
Also built from JSONL entries via `buildHourlyFromEntries(entries)`.

### New utility: `computeCost(session) → number`
Pricing per million tokens, keyed by model prefix match:

| Model prefix       | Input  | Output | Cache read | Cache write |
|--------------------|--------|--------|------------|-------------|
| `claude-opus-4`    | $15    | $75    | $1.50      | $18.75      |
| `claude-sonnet-4`  | $3     | $15    | $0.30      | $3.75       |
| `claude-haiku-4`   | $0.80  | $4     | $0.08      | $1.00       |
| default            | $3     | $15    | $0.30      | $3.75       |

```js
cost = (input * p.input + output * p.output + cache_read * p.cache_read + cache_creation * p.cache_write) / 1_000_000
```

### New utility: `contextFillPct(session) → number`
```js
CTX_LIMITS = { 'claude-opus': 200000, 'claude-sonnet': 200000, 'claude-haiku': 200000, default: 200000 }
pct = (total_input_tokens + total_output_tokens) / ctx_limit * 100
```
Proxy metric — cumulative tokens across turns, not a single-turn snapshot.

---

## Tab: Overview

Existing content preserved. Additions:

### `renderStatCards(sessions, daily, prevDaily)`
6 cards replacing current 4:

| Card | Value | Delta |
|------|-------|-------|
| Sessions | count | ↑↓ % vs prior period |
| Turns | sum turn_count | ↑↓ % |
| Input Tokens | sum total_input_tokens | ↑↓ % |
| Output Tokens | sum total_output_tokens | ↑↓ % |
| Cache Read | sum total_cache_read | ↑↓ % |
| Est. Cost | sum computeCost(s) | ↑↓ % |

Delta = `(current - prior) / prior * 100`. Prior period = same duration immediately before `dateFrom`. Hidden when no date filter active.

### `renderStreakCard(daily)`
Single card (not in the 6-card grid, rendered separately below):
- **Current streak** — consecutive days with turns up to today
- **Longest streak** — all-time max consecutive days
- **Active days this month** — count of days in current calendar month with any turns

### `renderMonthlyUsage(daily)`
Vertical bar chart, one bar per calendar month, stacked: input (blue) + output (orange).  
Includes a `// TODO: overlay plan limit % when Anthropic usage API available` comment at the render site.

### Existing components (unchanged)
- `renderTimelineChart` — adds output tokens as 5th dataset (orange)
- `renderHeatmap` — unchanged
- `renderProjectsChart` — unchanged

---

## Tab: Sessions

### `renderSessionTimelineChart(sessions)`
Toggle button above chart: **By Day** / **By Session**.
- **By Day** — existing daily line chart (reuses `renderTimelineChart`)
- **By Session** — horizontal bar chart, one bar per session:
  - Y-axis: session label (`project / date`)
  - X-axis: total tokens (input + output)
  - Bar color: model color (blue=Sonnet, purple=Opus, green=Haiku)
  - Sorted by date descending, max 100 sessions shown

### `renderContextFillBars(sessions)`
Horizontal bar chart, top 20 sessions by fill %, descending.
- Bar = `contextFillPct(session)`
- Color: green <50%, orange 50–80%, red >80%
- Tooltip: session id, project, date, exact %

### `renderSessionsTable(sessions)`
Existing table + 3 new columns:

| New column | Value |
|------------|-------|
| Duration | `last_timestamp - first_timestamp`, formatted as `Xh Ym` |
| Avg tok/turn | `total_input_tokens / turn_count` |
| Context % | `contextFillPct(session)` with color badge |

---

## Tab: Analytics

### `renderToolUsageChart(tools)`
Horizontal bar chart, top 15 tools by count.  
X-axis: call count. Y-axis: tool_name labels. Color: single blue.

### `renderModelDistChart(sessions)`
Doughnut chart. One segment per distinct model.  
Segment size = total tokens (input + output) for that model.  
Colors: blue (Sonnet), purple (Opus), green (Haiku), grey (other).

### `renderHourHeatmap(hourly)`
7 rows (Mon–Sun) × 24 columns (0–23h) SVG grid.  
Cell color intensity = token volume that hour/day combo.  
Uses same 5-level green palette as activity heatmap.  
Tooltip: day name, hour, token count.

### `renderCacheEfficiencyChart(daily)`
Line chart. One point per day.  
Value = `cache_read_tokens / (input_tokens + cache_read_tokens) * 100`.  
Y-axis: 0–100%. Reference line at 50% (dashed, muted).  
Color: green.

---

## Tab: Cost

### `renderCostStatCards(sessions)`
3 stat cards:
- **Total est. cost** — `sum(computeCost(s))` across all filtered sessions
- **This month** — filtered to current calendar month
- **Avg / session** — total / session count

### `renderCacheSavingsCard(sessions)`
Single highlighted card:  
`savings = sum(cache_read_tokens) * (input_rate - cache_read_rate) / 1_000_000`  
Display: "Saved ~$X.XX by reusing context"

### `renderCostTimelineChart(daily)`
Daily bar chart, 3 stacked segments per bar:
- Input cost (blue)
- Output cost (orange)  
- Cache creation cost (purple)  
Cache read cost omitted (negligible, already reflected in savings card).

### `renderCostByProjectChart(sessions)`
Horizontal bar chart, projects sorted by `sum(computeCost(s))` descending.  
Same layout as existing "Usage by project" chart.

---

## Filter Behavior

Filters (date range, project, model) remain global and apply to all tabs.  
On filter change, only the **active tab** re-renders — other tabs render lazily on switch.

---

## Not in scope

- Weekly/monthly plan limit % from Anthropic API (TODO comment added to `renderMonthlyUsage`)
- Branch activity chart (excluded by user)
- Persistence of cost preferences or custom pricing
- Multiple HTML files or a build step
