# Claude Usage Dashboard Enhancement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 4-tab navigation (Overview · Sessions · Analytics · Cost) and 12 new components to the claude-usage dashboard.

**Architecture:** Tab shell in `index.html` dispatches to modular `renderTab*` functions. Each section is a self-contained `render*(data, containerEl)` — takes filtered data and a DOM node, no global ID lookups. Data layer (`app.js`) gains two new DB queries (tools, hourly) plus cost/context utilities.

**Tech Stack:** Vanilla JS, Chart.js 4.x, sql.js 1.10.3, Python http.server

> **DOM safety rule (enforced throughout):** Never use `innerHTML` with template literals or variable interpolation. `container.innerHTML = ''` for clearing is the only allowed `innerHTML` usage. All data goes through `textContent` or `setAttribute`. Use the `el(tag, cls, text)` helper defined in Task 2.

> **No git commit steps** — user manages git manually.
> **Verify each task** at `http://localhost:8080/claude-usage/`.

---

## File Map

| File | Changes |
|------|---------|
| `claude-usage/app.js` | Add `queryTools`, `queryHourly`, `buildToolsFromEntries`, `buildHourlyFromEntries`, `mergeTools`, `mergeHourly`, `PRICING`, `computeCost`, `contextFillPct`; extend `parseJSONL` and `openDb`; update `applyFilters` |
| `claude-usage/index.html` | Add tab CSS; replace static HTML with tab shell; refactor existing render functions to accept `containerEl`; add 12 new render functions |

---

## Task 1: Data Layer (`app.js`)

**Files:** Modify `claude-usage/app.js`

### Step 1.1 — Add `queryTools` and `queryHourly` after `queryProcessedPaths` (~line 58)

- [ ] Add:

```js
function queryTools(db) {
  const stmt = db.prepare(`
    SELECT tool_name, COUNT(*) AS count
    FROM turns
    WHERE tool_name IS NOT NULL AND tool_name != ''
    GROUP BY tool_name
    ORDER BY count DESC
  `);
  const rows = [];
  while (stmt.step()) rows.push(stmt.getAsObject());
  stmt.free();
  return rows;
}

function queryHourly(db) {
  const stmt = db.prepare(`
    SELECT
      CAST(strftime('%w', timestamp) AS INTEGER) AS dow,
      CAST(strftime('%H', timestamp) AS INTEGER) AS hour,
      SUM(input_tokens + output_tokens)          AS tokens
    FROM turns
    GROUP BY dow, hour
  `);
  const rows = [];
  while (stmt.step()) rows.push(stmt.getAsObject());
  stmt.free();
  return rows;
}
```

### Step 1.2 — Extend `parseJSONL` to extract `toolName`

- [ ] In `parseJSONL`, find the `entries.push({...})` call (~line 98). Replace the entire push with:

```js
entries.push({
  sessionId:            obj.sessionId,
  timestamp:            obj.timestamp,
  model:                obj.message?.model ?? null,
  cwd:                  obj.cwd ?? null,
  gitBranch:            obj.gitBranch ?? null,
  input_tokens:         usage.input_tokens ?? 0,
  output_tokens:        usage.output_tokens ?? 0,
  cache_read_tokens:    usage.cache_read_input_tokens ?? 0,
  cache_creation_tokens:usage.cache_creation_input_tokens ?? 0,
  toolName: (obj.message?.content ?? []).find(c => c.type === 'tool_use')?.name ?? null,
});
```

### Step 1.3 — Add JSONL build helpers and merge functions after `mergeDailyData` (~line 190)

- [ ] Add:

```js
function buildToolsFromEntries(entries) {
  const map = new Map();
  for (const e of entries) {
    if (!e.toolName) continue;
    map.set(e.toolName, (map.get(e.toolName) || 0) + 1);
  }
  return [...map.entries()]
    .map(([tool_name, count]) => ({ tool_name, count }))
    .sort((a, b) => b.count - a.count);
}

function buildHourlyFromEntries(entries) {
  const map = new Map();
  for (const e of entries) {
    if (!e.timestamp) continue;
    const d    = new Date(e.timestamp);
    const key  = `${d.getDay()}-${d.getHours()}`;
    const prev = map.get(key);
    map.set(key, {
      dow:    d.getDay(),
      hour:   d.getHours(),
      tokens: (prev?.tokens || 0) + (e.input_tokens || 0) + (e.output_tokens || 0),
    });
  }
  return [...map.values()];
}

function mergeTools(a, b) {
  const map = new Map(a.map(t => [t.tool_name, t.count]));
  for (const t of b) map.set(t.tool_name, (map.get(t.tool_name) || 0) + t.count);
  return [...map.entries()]
    .map(([tool_name, count]) => ({ tool_name, count }))
    .sort((a, b) => b.count - a.count);
}

function mergeHourly(a, b) {
  const map = new Map(a.map(h => [`${h.dow}-${h.hour}`, { ...h }]));
  for (const h of b) {
    const key = `${h.dow}-${h.hour}`;
    if (map.has(key)) map.get(key).tokens += h.tokens;
    else map.set(key, { ...h });
  }
  return [...map.values()];
}
```

### Step 1.4 — Add cost and context utilities after `buildMeta` (~line 209)

- [ ] Add:

```js
const PRICING = {
  'claude-opus-4':   { input: 15,   output: 75,  cache_read: 1.50,  cache_write: 18.75 },
  'claude-sonnet-4': { input: 3,    output: 15,  cache_read: 0.30,  cache_write: 3.75  },
  'claude-haiku-4':  { input: 0.80, output: 4,   cache_read: 0.08,  cache_write: 1.00  },
};
const PRICING_DEFAULT = { input: 3, output: 15, cache_read: 0.30, cache_write: 3.75 };

function getPrice(model) {
  if (!model) return PRICING_DEFAULT;
  for (const [prefix, p] of Object.entries(PRICING)) {
    if (model.startsWith(prefix)) return p;
  }
  return PRICING_DEFAULT;
}

function computeCost(session) {
  const p = getPrice(session.model);
  return (
    (session.total_input_tokens   || 0) * p.input       +
    (session.total_output_tokens  || 0) * p.output      +
    (session.total_cache_read     || 0) * p.cache_read  +
    (session.total_cache_creation || 0) * p.cache_write
  ) / 1_000_000;
}

const CTX_LIMITS = {
  'claude-opus':   200000,
  'claude-sonnet': 200000,
  'claude-haiku':  200000,
};
const CTX_DEFAULT = 200000;

function getCtxLimit(model) {
  if (!model) return CTX_DEFAULT;
  for (const [prefix, limit] of Object.entries(CTX_LIMITS)) {
    if (model.includes(prefix)) return limit;
  }
  return CTX_DEFAULT;
}

// Returns avg input tokens per turn as % of the model's context window.
// Proxy metric — actual peak context per turn may be higher.
function contextFillPct(session) {
  if (!session.turn_count) return 0;
  const avgInput = (session.total_input_tokens || 0) / session.turn_count;
  return (avgInput / getCtxLimit(session.model)) * 100;
}
```

### Step 1.5 — Update `openDb` to call new queries (~line 224)

- [ ] Find the `let dbSessions, dbDaily, processedPaths;` line. Replace with:

```js
let dbSessions, dbDaily, processedPaths, dbTools, dbHourly;
try {
  dbSessions     = querySessions(db);
  dbDaily        = queryDaily(db);
  processedPaths = queryProcessedPaths(db);
  dbTools        = queryTools(db);
  dbHourly       = queryHourly(db);
} finally {
  db.close();
}
```

- [ ] Find where `jsonlSessions` and `jsonlDaily` are built (~line 249). Add two more lines:

```js
const jsonlSessions = buildSessionsFromEntries(allEntries);
const jsonlDaily    = buildDailyFromEntries(allEntries);
const jsonlTools    = buildToolsFromEntries(allEntries);
const jsonlHourly   = buildHourlyFromEntries(allEntries);
```

- [ ] Find the `window.CLAUDE_DATA = { ... }` assignment (~line 258). Replace with:

```js
const sessions = [...dbSessions, ...jsonlSessions].sort((a, b) =>
  (a.first_timestamp ?? '').localeCompare(b.first_timestamp ?? '')
);
const daily  = mergeDailyData(dbDaily, jsonlDaily);
const tools  = mergeTools(dbTools, jsonlTools);
const hourly = mergeHourly(dbHourly, jsonlHourly);
const meta   = buildMeta(sessions, daily);

window.CLAUDE_DATA = { meta, sessions, daily, tools, hourly };
console.log('CLAUDE_DATA ready:', meta);
window.dispatchEvent(new CustomEvent('claude-data-ready'));
```

### Step 1.6 — Update `applyFilters` return value (~line 376)

- [ ] Find `return { sessions, daily };` at the end of `applyFilters`. Replace with:

```js
return { sessions, daily, tools: data.tools || [], hourly: data.hourly || [] };
```

### Step 1.7 — Verify data layer

- [ ] Start server: `python3 -m http.server 8080` from the `Tools/` directory
- [ ] Open `http://localhost:8080/claude-usage/`, open DevTools console
- [ ] Run: `CLAUDE_DATA.tools` — expect array of `{ tool_name, count }` sorted descending
- [ ] Run: `CLAUDE_DATA.hourly` — expect array of `{ dow, hour, tokens }`
- [ ] Run: `computeCost(CLAUDE_DATA.sessions[0])` — expect a small positive number (dollars)
- [ ] Run: `contextFillPct(CLAUDE_DATA.sessions[0])` — expect a number between 0 and 100

---

## Task 2: Tab Shell + Refactor Existing Render Functions (`index.html`)

**Files:** Modify `claude-usage/index.html`

### Step 2.1 — Add tab and utility CSS to the `<style>` block (after `#load-more-btn:hover` ~line 250)

- [ ] Add:

```css
/* Tab bar */
.tab-bar {
  display: flex;
  padding: 0 24px;
  border-bottom: 1px solid var(--border);
  background: var(--bg);
  position: sticky;
  top: 49px;
  z-index: 9;
}
.tab-item {
  padding: 10px 18px;
  font-size: 13px;
  font-weight: 500;
  color: var(--muted);
  cursor: pointer;
  border-bottom: 2px solid transparent;
  user-select: none;
  white-space: nowrap;
}
.tab-item:hover { color: var(--text); }
.tab-item.active { color: var(--blue); border-bottom-color: var(--blue); }

/* Tab panels */
.tab-panel { display: none; }
.tab-panel.active { display: block; }

/* Stat card delta */
.stat-delta { font-size: 11px; font-weight: 500; margin-top: 2px; }
.stat-delta.up   { color: var(--green); }
.stat-delta.down { color: #f47067; }
.stat-delta.flat { color: var(--muted); }

/* Stats grid — 6 columns */
.stats-grid {
  display: grid;
  grid-template-columns: repeat(6, 1fr);
  gap: 16px;
  margin-bottom: 24px;
}
@media (max-width: 1100px) { .stats-grid { grid-template-columns: repeat(3, 1fr); } }
@media (max-width: 768px)  { .stats-grid { grid-template-columns: repeat(2, 1fr); } }
```

### Step 2.2 — Replace static `<main>` block with tab shell (~lines 281–309)

- [ ] Replace the entire `<main class="content">...</main>` block (everything from `<main` to `</main>`) with:

```html
<div class="tab-bar" id="tab-bar">
  <div class="tab-item active" data-tab="overview">Overview</div>
  <div class="tab-item" data-tab="sessions">Sessions</div>
  <div class="tab-item" data-tab="analytics">Analytics</div>
  <div class="tab-item" data-tab="cost">Cost</div>
</div>

<main class="content">
  <div id="tab-panel-overview" class="tab-panel active"></div>
  <div id="tab-panel-sessions" class="tab-panel"></div>
  <div id="tab-panel-analytics" class="tab-panel"></div>
  <div id="tab-panel-cost" class="tab-panel"></div>
</main>
```

### Step 2.3 — Add DOM helper utilities after the `sum` function (~line 329)

- [ ] Add:

```js
function el(tag, cls, text) {
  const node = document.createElement(tag);
  if (cls)  node.className   = cls;
  if (text !== undefined) node.textContent = text;
  return node;
}

function emptyState(msg) {
  return el('div', 'empty-state', msg);
}

function makeSection(title) {
  const card = el('div', 'section-card');
  card.appendChild(el('div', 'section-title', title));
  return card;
}

function fmtCost(n) {
  if (!n || n < 0.001) return '$0.00';
  if (n < 0.01) return '<$0.01';
  if (n < 1)    return '$' + n.toFixed(2);
  if (n < 100)  return '$' + n.toFixed(1);
  return '$' + Math.round(n);
}

function fmtDuration(first, last) {
  if (!first || !last) return '';
  const ms   = new Date(last) - new Date(first);
  if (ms <= 0) return '';
  const mins = Math.floor(ms / 60000);
  if (mins < 1)  return '<1m';
  if (mins < 60) return mins + 'm';
  return Math.floor(mins / 60) + 'h ' + (mins % 60) + 'm';
}
```

### Step 2.4 — Add tab state and switching logic after `filterState` (~line 337)

- [ ] Add:

```js
let activeTab = 'overview';

function switchTab(name) {
  document.querySelectorAll('.tab-item').forEach(t =>
    t.classList.toggle('active', t.dataset.tab === name)
  );
  document.querySelectorAll('.tab-panel').forEach(p =>
    p.classList.toggle('active', p.id === 'tab-panel-' + name)
  );
  activeTab = name;
  if (rawData) renderActiveTab(applyFilters(filterState, rawData));
}

function renderActiveTab(filtered) {
  const panel = document.getElementById('tab-panel-' + activeTab);
  if (activeTab === 'overview')  renderTabOverview(filtered, panel);
  if (activeTab === 'sessions')  renderTabSessions(filtered, panel);
  if (activeTab === 'analytics') renderTabAnalytics(filtered, panel);
  if (activeTab === 'cost')      renderTabCost(filtered, panel);
}
```

### Step 2.5 — Update `trigger()` (~line 588)

- [ ] Replace the `trigger` function body:

```js
function trigger() {
  if (!rawData) return;
  const filtered = applyFilters(filterState, rawData);
  renderFilterBar();
  renderActiveTab(filtered);
}
```

### Step 2.6 — Refactor `renderTimeline` → `renderTimelineChart(daily, container)`

- [ ] Delete the existing `renderTimeline` function and `let timelineChart = null` global. Replace with:

```js
let timelineChart = null;

function renderTimelineChart(daily, container) {
  container.innerHTML = '';
  if (timelineChart) { timelineChart.destroy(); timelineChart = null; }

  if (!daily || daily.length === 0) {
    container.appendChild(emptyState('No data for selected filters'));
    return;
  }

  const canvas = document.createElement('canvas');
  canvas.height = 120;
  container.appendChild(canvas);

  function ds(label, key, color) {
    return { label, data: daily.map(d => d[key] || 0),
      borderColor: color, backgroundColor: color + '26',
      fill: true, tension: 0.3, pointRadius: 2 };
  }

  timelineChart = new Chart(canvas, {
    type: 'line',
    data: { labels: daily.map(d => d.date), datasets: [
      ds('Input',          'input_tokens',          '#58a6ff'),
      ds('Output',         'output_tokens',         '#e3b341'),
      ds('Cache Read',     'cache_read_tokens',     '#3fb950'),
      ds('Cache Creation', 'cache_creation_tokens', '#bc8cff'),
    ]},
    options: {
      responsive: true,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { labels: { color: '#8b949e', boxWidth: 12 } },
        tooltip: { callbacks: { label: ctx => ' ' + ctx.dataset.label + ': ' + fmt(ctx.raw) } }
      },
      scales: {
        x: { ticks: { color: '#8b949e', maxTicksLimit: 10 }, grid: { color: '#21262d' } },
        y: { ticks: { color: '#8b949e', callback: fmt }, grid: { color: '#21262d' } }
      }
    }
  });
}
```

### Step 2.7 — Refactor `renderProjects` → `renderProjectsChart(sessions, container)`

- [ ] Delete existing `renderProjects` and `let projectsChart = null`. Replace with:

```js
let projectsChart = null;

function renderProjectsChart(sessions, container) {
  container.innerHTML = '';
  if (projectsChart) { projectsChart.destroy(); projectsChart = null; }

  if (!sessions || sessions.length === 0) {
    container.appendChild(emptyState('No data for selected filters'));
    return;
  }

  const byProject = {};
  for (const s of sessions) {
    const p = s.project_name || '(unknown)';
    byProject[p] = (byProject[p] || 0) + (s.total_input_tokens || 0) + (s.total_output_tokens || 0);
  }
  const entries = Object.entries(byProject).sort((a, b) => b[1] - a[1]);

  const canvas = document.createElement('canvas');
  canvas.height = Math.max(80, entries.length * 28);
  container.appendChild(canvas);

  projectsChart = new Chart(canvas, {
    type: 'bar',
    data: {
      labels: entries.map(([p]) => p),
      datasets: [{ label: 'Total Tokens', data: entries.map(([, v]) => v),
        backgroundColor: '#58a6ff66', borderColor: '#58a6ff', borderWidth: 1, borderRadius: 3 }]
    },
    options: {
      indexAxis: 'y', responsive: true,
      plugins: { legend: { display: false },
        tooltip: { callbacks: { label: ctx => ' ' + fmt(ctx.raw) + ' tokens' } } },
      scales: {
        x: { ticks: { color: '#8b949e', callback: fmt }, grid: { color: '#21262d' } },
        y: { ticks: { color: '#e6edf3' }, grid: { color: '#21262d' } }
      }
    }
  });
}
```

### Step 2.8 — Refactor `renderHeatmap(daily, container)`

- [ ] Delete existing `renderHeatmap`. Replace with a version that takes `container` instead of looking up IDs:

```js
function renderHeatmap(daily, container) {
  container.innerHTML = '';

  if (!daily || daily.length === 0) {
    container.appendChild(emptyState('No data for selected filters'));
    return;
  }

  const tokensByDate = {};
  for (const d of daily) tokensByDate[d.date] = d.input_tokens || 0;

  const dates = daily.map(d => d.date).sort();
  const start = new Date(dates[0] + 'T00:00:00');
  const end   = new Date(dates[dates.length - 1] + 'T00:00:00');
  const startSunday = new Date(start);
  startSunday.setDate(start.getDate() - start.getDay());

  const allDays = [];
  const cur = new Date(startSunday);
  while (cur <= end) { allDays.push(new Date(cur)); cur.setDate(cur.getDate() + 1); }

  const weeks  = Math.ceil(allDays.length / 7);
  const values = Object.values(tokensByDate).filter(v => v > 0).sort((a, b) => a - b);

  function getColor(tokens) {
    if (!tokens) return HEAT_COLORS[0];
    const rank = values.filter(v => v <= tokens).length / values.length;
    if (rank <= 0.25) return HEAT_COLORS[1];
    if (rank <= 0.50) return HEAT_COLORS[2];
    if (rank <= 0.75) return HEAT_COLORS[3];
    return HEAT_COLORS[4];
  }

  const CELL = 14, GAP = 2, LABEL_W = 28;
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('width',  String(LABEL_W + weeks * (CELL + GAP)));
  svg.setAttribute('height', String(7 * (CELL + GAP)));
  svg.style.display = 'block';

  const DAY_LABELS = ['', 'Mon', '', 'Wed', '', 'Fri', ''];
  for (let row = 0; row < 7; row++) {
    if (!DAY_LABELS[row]) continue;
    const t = document.createElementNS('http://www.w3.org/2000/svg', 'text');
    t.setAttribute('x', String(LABEL_W - 4));
    t.setAttribute('y', String(row * (CELL + GAP) + CELL - 3));
    t.setAttribute('text-anchor', 'end');
    t.setAttribute('fill', '#8b949e');
    t.setAttribute('font-size', '10');
    t.textContent = DAY_LABELS[row];
    svg.appendChild(t);
  }

  const monthsEl = document.createElement('div');
  monthsEl.className = 'heatmap-months';
  let lastMonth = -1;

  for (let week = 0; week < weeks; week++) {
    const day0 = allDays[week * 7];
    if (day0 && day0.getMonth() !== lastMonth) {
      lastMonth = day0.getMonth();
      const span = document.createElement('span');
      span.textContent = day0.toLocaleString('default', { month: 'short' });
      span.style.minWidth = (CELL + GAP) + 'px';
      monthsEl.appendChild(span);
    }
    for (let row = 0; row < 7; row++) {
      const idx = week * 7 + row;
      if (idx >= allDays.length) break;
      const dateStr = allDays[idx].toISOString().slice(0, 10);
      const tokens  = tokensByDate[dateStr] || 0;
      const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
      rect.setAttribute('x',      String(LABEL_W + week * (CELL + GAP)));
      rect.setAttribute('y',      String(row * (CELL + GAP)));
      rect.setAttribute('width',  String(CELL));
      rect.setAttribute('height', String(CELL));
      rect.setAttribute('rx', '2');
      rect.setAttribute('fill', getColor(tokens));
      if (tokens > 0) rect.setAttribute('title', dateStr + ': ' + fmt(tokens) + ' tokens');
      svg.appendChild(rect);
    }
  }

  container.appendChild(monthsEl);
  container.appendChild(svg);
}
```

### Step 2.9 — Refactor sessions table into `renderSessionsTable(sessions, container)`

- [ ] Delete `renderTable`, `renderTablePage`, `PAGE_SIZE`, `tableState`, `tableSessions` globals. Replace with:

```js
const PAGE_SIZE   = 50;
let tableState    = { sortKey: 'first_timestamp', sortDir: 'desc', page: 1 };
let tableSessions = [];
let tableContainer = null;

function renderSessionsTable(sessions, container) {
  tableSessions  = sessions;
  tableState.page = 1;
  tableContainer  = container;
  _renderTablePage();
}

function _renderTablePage() {
  const container = tableContainer;
  if (!container) return;
  container.innerHTML = '';

  if (!tableSessions || tableSessions.length === 0) {
    container.appendChild(emptyState('No data for selected filters'));
    return;
  }

  const cols = [
    { key: 'first_timestamp',    label: 'Date' },
    { key: 'project_name',       label: 'Project' },
    { key: 'model',              label: 'Model' },
    { key: 'turn_count',         label: 'Turns' },
    { key: 'total_input_tokens', label: 'Input' },
    { key: 'total_cache_read',   label: 'Cache Read' },
    { key: '_duration',          label: 'Duration' },
    { key: '_avg_tok_turn',      label: 'Avg tok/turn' },
    { key: '_ctx_pct',           label: 'Context %' },
  ];

  const augmented = tableSessions.map(s => ({
    ...s,
    _duration:    fmtDuration(s.first_timestamp, s.last_timestamp),
    _avg_tok_turn: s.turn_count ? Math.round((s.total_input_tokens || 0) / s.turn_count) : 0,
    _ctx_pct:     contextFillPct(s),
  }));

  const sorted = [...augmented].sort((a, b) => {
    const av = a[tableState.sortKey] ?? '';
    const bv = b[tableState.sortKey] ?? '';
    const cmp = av < bv ? -1 : av > bv ? 1 : 0;
    return tableState.sortDir === 'asc' ? cmp : -cmp;
  });

  const visible = sorted.slice(0, tableState.page * PAGE_SIZE);
  const table   = document.createElement('table');
  const thead   = document.createElement('thead');
  const hRow    = document.createElement('tr');

  for (const col of cols) {
    const th = el('th', null, col.label);
    if (tableState.sortKey === col.key)
      th.className = tableState.sortDir === 'asc' ? 'sort-asc' : 'sort-desc';
    th.addEventListener('click', () => {
      if (tableState.sortKey === col.key)
        tableState.sortDir = tableState.sortDir === 'asc' ? 'desc' : 'asc';
      else { tableState.sortKey = col.key; tableState.sortDir = 'desc'; }
      tableState.page = 1;
      _renderTablePage();
    });
    hRow.appendChild(th);
  }
  thead.appendChild(hRow);
  table.appendChild(thead);

  const tbody = document.createElement('tbody');
  for (const s of visible) {
    const tr = document.createElement('tr');

    function td(text, muted) {
      const cell = el('td', muted ? 'muted' : null, text ?? '');
      return cell;
    }

    const ctxTd = el('td');
    ctxTd.textContent = s._ctx_pct.toFixed(1) + '%';
    ctxTd.style.color = s._ctx_pct > 80 ? '#f47067' : s._ctx_pct > 50 ? '#e3b341' : '#3fb950';

    tr.append(
      td(fmtDate(s.first_timestamp)),
      td(s.project_name || ''),
      td(s.model || '', true),
      td(String(s.turn_count || 0)),
      td(fmt(s.total_input_tokens)),
      td(fmt(s.total_cache_read)),
      td(s._duration, true),
      td(fmt(s._avg_tok_turn), true),
      ctxTd,
    );
    tbody.appendChild(tr);
  }
  table.appendChild(tbody);
  container.appendChild(table);

  if (visible.length < sorted.length) {
    const btn = el('button', null, '+ Load more (' + (sorted.length - visible.length) + ' remaining)');
    btn.id = 'load-more-btn';
    btn.addEventListener('click', () => { tableState.page++; _renderTablePage(); });
    container.appendChild(btn);
  }
}
```

### Step 2.10 — Delete `renderAll` and `renderStats`

- [ ] Delete the `renderAll` function entirely (it called the old render functions)
- [ ] Delete the `renderStats` function entirely (replaced by new `renderStatCards` in Task 3)

### Step 2.11 — Add `renderTabOverview` (wires existing + new components together)

- [ ] Add before the `<script>` closing tag area:

```js
function renderTabOverview({ sessions, daily }, panel) {
  panel.innerHTML = '';

  const statsGrid = el('div', 'stats-grid');
  panel.appendChild(statsGrid);
  renderStatCards(sessions, daily, statsGrid);

  const twoCol = document.createElement('div');
  twoCol.style.cssText = 'display:grid;grid-template-columns:1fr 2fr;gap:16px;margin-bottom:24px';
  panel.appendChild(twoCol);
  renderStreakCard(daily, twoCol);
  renderMonthlyUsage(daily, twoCol);

  const tlCard = makeSection('Token Usage Over Time');
  const tlWrap = el('div', 'chart-wrap');
  tlCard.appendChild(tlWrap);
  panel.appendChild(tlCard);
  renderTimelineChart(daily, tlWrap);

  const projCard = makeSection('Usage by Project');
  const projWrap = el('div', 'chart-wrap');
  projCard.appendChild(projWrap);
  panel.appendChild(projCard);
  renderProjectsChart(sessions, projWrap);

  const heatCard = makeSection('Activity Heatmap');
  const heatWrap = el('div', 'heatmap-scroll');
  heatCard.appendChild(heatWrap);
  panel.appendChild(heatCard);
  renderHeatmap(daily, heatWrap);
}
```

### Step 2.12 — Update `claude-data-ready` event handler

- [ ] Replace the existing `window.addEventListener('claude-data-ready', ...)` handler:

```js
window.addEventListener('claude-data-ready', () => {
  rawData = window.CLAUDE_DATA;
  document.getElementById('loading').classList.remove('show');

  const from = new Date();
  from.setDate(from.getDate() - 30);
  filterState.dateFrom = from.toISOString().slice(0, 10);
  filterState.dateTo   = null;
  filterState.projects.clear();
  filterState.models.clear();

  document.querySelectorAll('.tab-item').forEach(t =>
    t.addEventListener('click', () => switchTab(t.dataset.tab))
  );

  renderFilterBar();
  renderActiveTab(applyFilters(filterState, rawData));
});
```

### Step 2.13 — Verify tab shell

- [ ] Reload `http://localhost:8080/claude-usage/`
- [ ] Tab bar visible: Overview · Sessions · Analytics · Cost
- [ ] Overview tab shows all existing charts (timeline now includes Output dataset)
- [ ] Sessions/Analytics/Cost tabs show empty panels (not yet implemented)
- [ ] Date filter, project filter, refresh all work on Overview tab
- [ ] DevTools console: no errors

---

## Task 3: Overview Tab — New Components

**Files:** Modify `claude-usage/index.html` (add before `renderTabOverview`)

### Step 3.1 — Add `renderStatCards` (6 cards + delta %)

- [ ] Add before `renderTabOverview`:

```js
function _prevSessions(dateFrom, dateTo) {
  if (!dateFrom || !rawData) return [];
  const from = new Date(dateFrom + 'T00:00:00');
  const to   = dateTo ? new Date(dateTo + 'T23:59:59') : new Date();
  const ms   = to - from;
  const prevTo   = new Date(from - 1);
  const prevFrom = new Date(prevTo - ms);
  const pf = prevFrom.toISOString().slice(0, 10);
  const pt = prevTo.toISOString().slice(0, 10);
  return (rawData.sessions || []).filter(s =>
    s.first_timestamp >= pf && s.first_timestamp <= pt + 'T23:59:59'
  );
}

function renderStatCards(sessions, daily, container) {
  container.innerHTML = '';
  const prev = _prevSessions(filterState.dateFrom, filterState.dateTo);

  function deltaEl(curr, prevVal) {
    if (!filterState.dateFrom || prevVal === 0) return null;
    const pct  = ((curr - prevVal) / prevVal) * 100;
    const node = el('div', 'stat-delta ' + (pct > 0 ? 'up' : pct < 0 ? 'down' : 'flat'));
    node.textContent = (pct >= 0 ? '+' : '') + pct.toFixed(0) + '%';
    return node;
  }

  const totalInput  = sessions.reduce((t, s) => t + (s.total_input_tokens   || 0), 0);
  const totalOutput = sessions.reduce((t, s) => t + (s.total_output_tokens  || 0), 0);
  const totalCache  = sessions.reduce((t, s) => t + (s.total_cache_read     || 0), 0);
  const totalTurns  = sessions.reduce((t, s) => t + (s.turn_count           || 0), 0);
  const totalCost   = sessions.reduce((t, s) => t + computeCost(s),                0);

  const pInput  = prev.reduce((t, s) => t + (s.total_input_tokens  || 0), 0);
  const pOutput = prev.reduce((t, s) => t + (s.total_output_tokens || 0), 0);
  const pCache  = prev.reduce((t, s) => t + (s.total_cache_read    || 0), 0);
  const pTurns  = prev.reduce((t, s) => t + (s.turn_count          || 0), 0);
  const pCost   = prev.reduce((t, s) => t + computeCost(s),               0);

  const cards = [
    { label: 'Sessions',      value: String(sessions.length), color: 'var(--text)',   curr: sessions.length, p: prev.length  },
    { label: 'Turns',         value: fmt(totalTurns),         color: 'var(--text)',   curr: totalTurns,      p: pTurns       },
    { label: 'Input Tokens',  value: fmt(totalInput),         color: 'var(--blue)',   curr: totalInput,      p: pInput       },
    { label: 'Output Tokens', value: fmt(totalOutput),        color: '#e3b341',       curr: totalOutput,     p: pOutput      },
    { label: 'Cache Read',    value: fmt(totalCache),         color: 'var(--green)',  curr: totalCache,      p: pCache       },
    { label: 'Est. Cost',     value: fmtCost(totalCost),      color: 'var(--purple)', curr: totalCost,       p: pCost        },
  ];

  for (const c of cards) {
    const card  = el('div', 'stat-card');
    const lbl   = el('div', 'stat-label', c.label);
    const val   = el('div', 'stat-value', c.value);
    val.style.color = c.color;
    card.appendChild(lbl);
    card.appendChild(val);
    const d = deltaEl(c.curr, c.p);
    if (d) card.appendChild(d);
    container.appendChild(card);
  }
}
```

### Step 3.2 — Add `renderStreakCard`

- [ ] Add after `renderStatCards`:

```js
function renderStreakCard(daily, container) {
  const dateSet = new Set(daily.map(d => d.date));
  const today   = new Date().toISOString().slice(0, 10);

  let streak = 0;
  const c = new Date(today + 'T12:00:00');
  while (dateSet.has(c.toISOString().slice(0, 10))) {
    streak++;
    c.setDate(c.getDate() - 1);
  }

  const sorted = [...dateSet].sort();
  let longest = 0, run = 0;
  for (let i = 0; i < sorted.length; i++) {
    if (i === 0) { run = 1; longest = 1; continue; }
    const prev = new Date(sorted[i - 1] + 'T12:00:00');
    prev.setDate(prev.getDate() + 1);
    run = prev.toISOString().slice(0, 10) === sorted[i] ? run + 1 : 1;
    longest = Math.max(longest, run);
  }

  const thisMonth  = today.slice(0, 7);
  const activeDays = sorted.filter(d => d.startsWith(thisMonth)).length;

  const card  = el('div', 'section-card');
  const title = el('div', 'section-title', 'Activity Streak');
  const grid  = document.createElement('div');
  grid.style.cssText = 'display:grid;grid-template-columns:repeat(3,1fr);gap:16px';

  function streakItem(label, value, color) {
    const wrap = document.createElement('div');
    const lbl  = el('div', 'stat-label', label);
    const val  = el('div', 'stat-value', value);
    if (color) val.style.color = color;
    wrap.appendChild(lbl);
    wrap.appendChild(val);
    return wrap;
  }

  grid.appendChild(streakItem('Current',    streak + 'd',    'var(--orange)'));
  grid.appendChild(streakItem('Longest',    longest + 'd',   null));
  grid.appendChild(streakItem('This month', activeDays + 'd','var(--green)'));
  card.appendChild(title);
  card.appendChild(grid);
  container.appendChild(card);
}
```

### Step 3.3 — Add `renderMonthlyUsage`

- [ ] Add after `renderStreakCard`:

```js
let monthlyChart = null;

function renderMonthlyUsage(daily, container) {
  if (monthlyChart) { monthlyChart.destroy(); monthlyChart = null; }

  const byMonth = {};
  for (const d of daily) {
    const m = d.date.slice(0, 7);
    if (!byMonth[m]) byMonth[m] = { input: 0, output: 0 };
    byMonth[m].input  += d.input_tokens  || 0;
    byMonth[m].output += d.output_tokens || 0;
  }
  const months = Object.keys(byMonth).sort();

  const card  = el('div', 'section-card');
  const title = el('div', 'section-title', 'Monthly Usage');
  card.appendChild(title);

  if (months.length === 0) {
    card.appendChild(emptyState('No data'));
    container.appendChild(card);
    return;
  }

  // TODO: overlay plan limit % when Anthropic usage API available
  const wrap   = el('div', 'chart-wrap');
  const canvas = document.createElement('canvas');
  canvas.height = 120;
  wrap.appendChild(canvas);
  card.appendChild(wrap);
  container.appendChild(card);

  monthlyChart = new Chart(canvas, {
    type: 'bar',
    data: {
      labels: months,
      datasets: [
        { label: 'Input',  data: months.map(m => byMonth[m].input),
          backgroundColor: '#58a6ff66', borderColor: '#58a6ff', borderWidth: 1 },
        { label: 'Output', data: months.map(m => byMonth[m].output),
          backgroundColor: '#e3b34166', borderColor: '#e3b341', borderWidth: 1 },
      ]
    },
    options: {
      responsive: true,
      plugins: {
        legend: { labels: { color: '#8b949e', boxWidth: 12 } },
        tooltip: { callbacks: { label: ctx => ' ' + ctx.dataset.label + ': ' + fmt(ctx.raw) } }
      },
      scales: {
        x: { stacked: true, ticks: { color: '#8b949e' }, grid: { color: '#21262d' } },
        y: { stacked: true, ticks: { color: '#8b949e', callback: fmt }, grid: { color: '#21262d' } },
      }
    }
  });
}
```

### Step 3.4 — Verify Overview tab

- [ ] Reload `http://localhost:8080/claude-usage/`
- [ ] 6 stat cards visible (Sessions / Turns / Input / Output / Cache / Cost)
- [ ] Apply 30d filter — stat cards show ↑↓ % deltas
- [ ] Streak card shows current streak, longest, active days this month
- [ ] Monthly usage stacked bar chart shows months on x-axis
- [ ] Token timeline has Output as a 4th dataset (orange line)

---

## Task 4: Sessions Tab

**Files:** Modify `claude-usage/index.html`

### Step 4.1 — Add `renderSessionTimelineChart`

- [ ] Add before `renderTabOverview`:

```js
let sessionBarChart = null;
let sessionViewMode = 'day';

function renderSessionTimelineChart(sessions, daily, container) {
  container.innerHTML = '';
  if (sessionBarChart) { sessionBarChart.destroy(); sessionBarChart = null; }

  const toggleRow = document.createElement('div');
  toggleRow.style.cssText = 'display:flex;gap:8px;margin-bottom:12px';

  function toggleBtn(label, mode) {
    const btn = el('button', null, label);
    btn.style.cssText = 'padding:4px 12px;border-radius:4px;font-size:12px;cursor:pointer;' +
      'border:1px solid var(--border);background:var(--card);color:var(--muted);';
    if (sessionViewMode === mode) {
      btn.style.borderColor = 'var(--blue)';
      btn.style.color       = 'var(--blue)';
    }
    btn.addEventListener('click', () => {
      sessionViewMode = mode;
      renderSessionTimelineChart(sessions, daily, container);
    });
    return btn;
  }
  toggleRow.appendChild(toggleBtn('By Day',     'day'));
  toggleRow.appendChild(toggleBtn('By Session', 'session'));
  container.appendChild(toggleRow);

  const wrap = el('div', 'chart-wrap');
  container.appendChild(wrap);

  if (sessionViewMode === 'day') {
    renderTimelineChart(daily, wrap);
    return;
  }

  const visible = [...sessions]
    .sort((a, b) => (b.first_timestamp ?? '').localeCompare(a.first_timestamp ?? ''))
    .slice(0, 100);

  if (visible.length === 0) {
    wrap.appendChild(emptyState('No sessions'));
    return;
  }

  function modelColor(model) {
    if (!model) return '#8b949e';
    if (model.includes('sonnet')) return '#58a6ff';
    if (model.includes('opus'))   return '#bc8cff';
    if (model.includes('haiku'))  return '#3fb950';
    return '#8b949e';
  }

  const canvas = document.createElement('canvas');
  canvas.height = Math.max(80, visible.length * 22);
  wrap.appendChild(canvas);

  sessionBarChart = new Chart(canvas, {
    type: 'bar',
    data: {
      labels: visible.map(s => (s.project_name || '?') + ' · ' + fmtDate(s.first_timestamp)),
      datasets: [{
        label: 'Total Tokens',
        data:            visible.map(s => (s.total_input_tokens || 0) + (s.total_output_tokens || 0)),
        backgroundColor: visible.map(s => modelColor(s.model) + '99'),
        borderColor:     visible.map(s => modelColor(s.model)),
        borderWidth: 1, borderRadius: 2,
      }]
    },
    options: {
      indexAxis: 'y', responsive: true,
      plugins: { legend: { display: false },
        tooltip: { callbacks: {
          label:       ctx => ' ' + fmt(ctx.raw) + ' tokens',
          afterLabel:  ctx => ' turns: ' + (visible[ctx.dataIndex].turn_count || 0),
        }}
      },
      scales: {
        x: { ticks: { color: '#8b949e', callback: fmt }, grid: { color: '#21262d' } },
        y: { ticks: { color: '#e6edf3', font: { size: 11 } }, grid: { color: '#21262d' } }
      }
    }
  });
}
```

### Step 4.2 — Add `renderContextFillBars`

- [ ] Add after `renderSessionTimelineChart`:

```js
let ctxFillChart = null;

function renderContextFillBars(sessions, container) {
  container.innerHTML = '';
  if (ctxFillChart) { ctxFillChart.destroy(); ctxFillChart = null; }

  const top20 = [...sessions]
    .map(s => ({ ...s, _pct: contextFillPct(s) }))
    .sort((a, b) => b._pct - a._pct)
    .slice(0, 20);

  if (top20.length === 0) {
    container.appendChild(emptyState('No sessions'));
    return;
  }

  const canvas = document.createElement('canvas');
  canvas.height = Math.max(80, top20.length * 28);
  container.appendChild(canvas);

  ctxFillChart = new Chart(canvas, {
    type: 'bar',
    data: {
      labels: top20.map(s => (s.project_name || '?') + ' · ' + fmtDate(s.first_timestamp)),
      datasets: [{
        label: 'Avg context fill %',
        data:            top20.map(s => +s._pct.toFixed(1)),
        backgroundColor: top20.map(s => s._pct > 80 ? '#f4706799' : s._pct > 50 ? '#e3b34199' : '#3fb95099'),
        borderColor:     top20.map(s => s._pct > 80 ? '#f47067'   : s._pct > 50 ? '#e3b341'   : '#3fb950'),
        borderWidth: 1, borderRadius: 2,
      }]
    },
    options: {
      indexAxis: 'y', responsive: true,
      plugins: { legend: { display: false },
        tooltip: { callbacks: { label: ctx => ' ' + ctx.raw + '% avg context fill' } }
      },
      scales: {
        x: { min: 0, max: 100, ticks: { color: '#8b949e', callback: v => v + '%' }, grid: { color: '#21262d' } },
        y: { ticks: { color: '#e6edf3', font: { size: 11 } }, grid: { color: '#21262d' } }
      }
    }
  });
}
```

### Step 4.3 — Add `renderTabSessions`

- [ ] Add after `renderContextFillBars`:

```js
function renderTabSessions({ sessions, daily }, panel) {
  panel.innerHTML = '';

  const tlCard = makeSection('Session Timeline');
  const tlWrap = document.createElement('div');
  tlCard.appendChild(tlWrap);
  panel.appendChild(tlCard);
  renderSessionTimelineChart(sessions, daily, tlWrap);

  const ctxCard = makeSection('Context Fill % — Top 20 Sessions');
  const ctxWrap = el('div', 'chart-wrap');
  ctxCard.appendChild(ctxWrap);
  panel.appendChild(ctxCard);
  renderContextFillBars(sessions, ctxWrap);

  const tblCard = makeSection('Sessions');
  const tblWrap = document.createElement('div');
  tblCard.appendChild(tblWrap);
  panel.appendChild(tblCard);
  renderSessionsTable(sessions, tblWrap);
}
```

### Step 4.4 — Verify Sessions tab

- [ ] Click Sessions tab
- [ ] "By Day" shows daily line chart matching Overview timeline
- [ ] "By Session" shows horizontal bars (blue=Sonnet, purple=Opus, green=Haiku), newest first
- [ ] Context fill bars: top 20 sessions, green/orange/red color-coded
- [ ] Sessions table has 9 columns including Duration, Avg tok/turn, Context %

---

## Task 5: Analytics Tab

**Files:** Modify `claude-usage/index.html`

### Step 5.1 — Add `renderToolUsageChart`

- [ ] Add before `renderTabOverview`:

```js
let toolChart = null;

function renderToolUsageChart(tools, container) {
  container.innerHTML = '';
  if (toolChart) { toolChart.destroy(); toolChart = null; }

  const top15 = (tools || []).slice(0, 15);
  if (top15.length === 0) {
    container.appendChild(emptyState('No tool data'));
    return;
  }

  const canvas = document.createElement('canvas');
  canvas.height = Math.max(80, top15.length * 28);
  container.appendChild(canvas);

  toolChart = new Chart(canvas, {
    type: 'bar',
    data: {
      labels:   top15.map(t => t.tool_name),
      datasets: [{ label: 'Calls', data: top15.map(t => t.count),
        backgroundColor: '#58a6ff66', borderColor: '#58a6ff', borderWidth: 1, borderRadius: 2 }]
    },
    options: {
      indexAxis: 'y', responsive: true,
      plugins: { legend: { display: false },
        tooltip: { callbacks: { label: ctx => ' ' + ctx.raw + ' calls' } } },
      scales: {
        x: { ticks: { color: '#8b949e' }, grid: { color: '#21262d' } },
        y: { ticks: { color: '#e6edf3' }, grid: { color: '#21262d' } }
      }
    }
  });
}
```

### Step 5.2 — Add `renderModelDistChart`

- [ ] Add after `renderToolUsageChart`:

```js
let modelChart = null;

function renderModelDistChart(sessions, container) {
  container.innerHTML = '';
  if (modelChart) { modelChart.destroy(); modelChart = null; }

  const byModel = {};
  for (const s of sessions) {
    const m = s.model || 'unknown';
    byModel[m] = (byModel[m] || 0) + (s.total_input_tokens || 0) + (s.total_output_tokens || 0);
  }
  const entries = Object.entries(byModel).sort((a, b) => b[1] - a[1]);

  if (entries.length === 0) {
    container.appendChild(emptyState('No model data'));
    return;
  }

  const PALETTE = ['#58a6ff', '#bc8cff', '#3fb950', '#e3b341', '#f47067', '#8b949e'];
  const canvas  = document.createElement('canvas');
  canvas.height = 200;
  container.appendChild(canvas);

  modelChart = new Chart(canvas, {
    type: 'doughnut',
    data: {
      labels:   entries.map(([m]) => m),
      datasets: [{
        data:            entries.map(([, v]) => v),
        backgroundColor: entries.map((_, i) => PALETTE[i % PALETTE.length] + 'cc'),
        borderColor:     entries.map((_, i) => PALETTE[i % PALETTE.length]),
        borderWidth: 1,
      }]
    },
    options: {
      responsive: true,
      plugins: {
        legend: { labels: { color: '#8b949e', boxWidth: 12 } },
        tooltip: { callbacks: { label: ctx => ' ' + ctx.label + ': ' + fmt(ctx.raw) + ' tokens' } }
      }
    }
  });
}
```

### Step 5.3 — Add `renderHourHeatmap`

- [ ] Add after `renderModelDistChart`:

```js
function renderHourHeatmap(hourly, container) {
  container.innerHTML = '';

  if (!hourly || hourly.length === 0) {
    container.appendChild(emptyState('No hourly data'));
    return;
  }

  const lookup = {};
  for (const h of hourly) lookup[h.dow + '-' + h.hour] = h.tokens || 0;

  const allVals = Object.values(lookup).filter(v => v > 0).sort((a, b) => a - b);
  function getColor(tokens) {
    if (!tokens) return HEAT_COLORS[0];
    const rank = allVals.filter(v => v <= tokens).length / allVals.length;
    if (rank <= 0.25) return HEAT_COLORS[1];
    if (rank <= 0.50) return HEAT_COLORS[2];
    if (rank <= 0.75) return HEAT_COLORS[3];
    return HEAT_COLORS[4];
  }

  const CELL = 14, GAP = 2, DAY_W = 32;
  const DOW  = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const svgW = DAY_W + 24 * (CELL + GAP);
  const svgH = 20 + 7 * (CELL + GAP);

  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('width',  String(svgW));
  svg.setAttribute('height', String(svgH));
  svg.style.display = 'block';

  for (const h of [0, 6, 12, 18, 23]) {
    const t = document.createElementNS('http://www.w3.org/2000/svg', 'text');
    t.setAttribute('x', String(DAY_W + h * (CELL + GAP)));
    t.setAttribute('y', '12');
    t.setAttribute('fill', '#8b949e');
    t.setAttribute('font-size', '10');
    t.textContent = h + 'h';
    svg.appendChild(t);
  }

  for (let dow = 0; dow < 7; dow++) {
    const tl = document.createElementNS('http://www.w3.org/2000/svg', 'text');
    tl.setAttribute('x', String(DAY_W - 4));
    tl.setAttribute('y', String(20 + dow * (CELL + GAP) + CELL - 3));
    tl.setAttribute('text-anchor', 'end');
    tl.setAttribute('fill', '#8b949e');
    tl.setAttribute('font-size', '10');
    tl.textContent = DOW[dow];
    svg.appendChild(tl);

    for (let hour = 0; hour < 24; hour++) {
      const tokens = lookup[dow + '-' + hour] || 0;
      const rect   = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
      rect.setAttribute('x',      String(DAY_W + hour * (CELL + GAP)));
      rect.setAttribute('y',      String(20 + dow * (CELL + GAP)));
      rect.setAttribute('width',  String(CELL));
      rect.setAttribute('height', String(CELL));
      rect.setAttribute('rx', '2');
      rect.setAttribute('fill', getColor(tokens));
      if (tokens > 0)
        rect.setAttribute('title', DOW[dow] + ' ' + hour + 'h: ' + fmt(tokens) + ' tokens');
      svg.appendChild(rect);
    }
  }

  container.appendChild(svg);
}
```

### Step 5.4 — Add `renderCacheEfficiencyChart`

- [ ] Add after `renderHourHeatmap`:

```js
let cacheEffChart = null;

function renderCacheEfficiencyChart(daily, container) {
  container.innerHTML = '';
  if (cacheEffChart) { cacheEffChart.destroy(); cacheEffChart = null; }

  const points = daily.map(d => {
    const denom = (d.input_tokens || 0) + (d.cache_read_tokens || 0);
    return denom > 0
      ? { date: d.date, pct: (d.cache_read_tokens || 0) / denom * 100 }
      : null;
  }).filter(Boolean);

  if (points.length === 0) {
    container.appendChild(emptyState('No cache data'));
    return;
  }

  const canvas = document.createElement('canvas');
  canvas.height = 120;
  container.appendChild(canvas);

  cacheEffChart = new Chart(canvas, {
    type: 'line',
    data: {
      labels: points.map(p => p.date),
      datasets: [{
        label: 'Cache hit %',
        data: points.map(p => +p.pct.toFixed(1)),
        borderColor: '#3fb950', backgroundColor: '#3fb95026',
        fill: true, tension: 0.3, pointRadius: 2,
      }]
    },
    options: {
      responsive: true,
      plugins: {
        legend: { display: false },
        tooltip: { callbacks: { label: ctx => ' Cache hit: ' + ctx.raw + '%' } }
      },
      scales: {
        x: { ticks: { color: '#8b949e', maxTicksLimit: 10 }, grid: { color: '#21262d' } },
        y: { min: 0, max: 100, ticks: { color: '#8b949e', callback: v => v + '%' }, grid: { color: '#21262d' } }
      }
    }
  });
}
```

### Step 5.5 — Add `renderTabAnalytics`

- [ ] Add after `renderCacheEfficiencyChart`:

```js
function renderTabAnalytics({ sessions, daily, tools, hourly }, panel) {
  panel.innerHTML = '';

  const twoCol = document.createElement('div');
  twoCol.style.cssText = 'display:grid;grid-template-columns:2fr 1fr;gap:16px;margin-bottom:24px';
  panel.appendChild(twoCol);

  const toolCard = makeSection('Tool Usage');
  const toolWrap = el('div', 'chart-wrap');
  toolCard.appendChild(toolWrap);
  twoCol.appendChild(toolCard);
  renderToolUsageChart(tools, toolWrap);

  const modelCard = makeSection('Model Distribution');
  const modelWrap = el('div', 'chart-wrap');
  modelCard.appendChild(modelWrap);
  twoCol.appendChild(modelCard);
  renderModelDistChart(sessions, modelWrap);

  const hourCard = makeSection('Activity by Hour of Day');
  const hourWrap = document.createElement('div');
  hourWrap.style.overflowX = 'auto';
  hourCard.appendChild(hourWrap);
  panel.appendChild(hourCard);
  renderHourHeatmap(hourly, hourWrap);

  const cacheCard = makeSection('Cache Efficiency %');
  const cacheWrap = el('div', 'chart-wrap');
  cacheCard.appendChild(cacheWrap);
  panel.appendChild(cacheCard);
  renderCacheEfficiencyChart(daily, cacheWrap);
}
```

### Step 5.6 — Verify Analytics tab

- [ ] Click Analytics tab
- [ ] Tool usage horizontal bar chart shows tools sorted by call count
- [ ] Model distribution doughnut chart shows proportional segments per model
- [ ] Hour-of-day heatmap: 7 rows (Sun–Sat) × 24 columns, green-intensity cells
- [ ] Cache efficiency line chart: y-axis 0–100%, green line

---

## Task 6: Cost Tab

**Files:** Modify `claude-usage/index.html`

### Step 6.1 — Add `renderCostStatCards`

- [ ] Add before `renderTabOverview`:

```js
function renderCostStatCards(sessions, container) {
  const total    = sessions.reduce((t, s) => t + computeCost(s), 0);
  const thisMonth = new Date().toISOString().slice(0, 7);
  const monthly  = sessions
    .filter(s => s.first_timestamp?.startsWith(thisMonth))
    .reduce((t, s) => t + computeCost(s), 0);
  const avg = sessions.length ? total / sessions.length : 0;

  const grid = document.createElement('div');
  grid.style.cssText = 'display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-bottom:24px';

  function costCard(label, value, color) {
    const card = el('div', 'stat-card');
    const lbl  = el('div', 'stat-label', label);
    const val  = el('div', 'stat-value', value);
    val.style.color = color;
    card.appendChild(lbl);
    card.appendChild(val);
    return card;
  }

  grid.appendChild(costCard('Total Est. Cost', fmtCost(total),   'var(--purple)'));
  grid.appendChild(costCard('This Month',      fmtCost(monthly), 'var(--blue)'));
  grid.appendChild(costCard('Avg / Session',   fmtCost(avg),     'var(--muted)'));
  container.appendChild(grid);
}
```

### Step 6.2 — Add `renderCacheSavingsCard`

- [ ] Add after `renderCostStatCards`:

```js
function renderCacheSavingsCard(sessions, container) {
  let savings = 0;
  for (const s of sessions) {
    const p = getPrice(s.model);
    savings += (s.total_cache_read || 0) * (p.input - p.cache_read) / 1_000_000;
  }

  const card   = el('div', 'stat-card');
  card.style.marginBottom = '24px';
  const lbl    = el('div', 'stat-label', 'Cache Savings');
  const val    = el('div', 'stat-value', fmtCost(savings));
  val.style.color = 'var(--green)';
  const note   = el('div', 'stat-delta flat', 'saved by reusing context vs re-sending as input');
  card.appendChild(lbl);
  card.appendChild(val);
  card.appendChild(note);
  container.appendChild(card);
}
```

### Step 6.3 — Add `renderCostTimelineChart`

- [ ] Add after `renderCacheSavingsCard`:

```js
let costTimelineChart = null;

function renderCostTimelineChart(sessions, container) {
  container.innerHTML = '';
  if (costTimelineChart) { costTimelineChart.destroy(); costTimelineChart = null; }

  const byDate = {};
  for (const s of sessions) {
    if (!s.first_timestamp) continue;
    const date = s.first_timestamp.slice(0, 10);
    const p    = getPrice(s.model);
    if (!byDate[date]) byDate[date] = { input: 0, output: 0, cache: 0 };
    byDate[date].input  += (s.total_input_tokens   || 0) * p.input       / 1_000_000;
    byDate[date].output += (s.total_output_tokens  || 0) * p.output      / 1_000_000;
    byDate[date].cache  += (s.total_cache_creation || 0) * p.cache_write / 1_000_000;
  }

  const dates = Object.keys(byDate).sort();
  if (dates.length === 0) {
    container.appendChild(emptyState('No cost data'));
    return;
  }

  const canvas = document.createElement('canvas');
  canvas.height = 120;
  container.appendChild(canvas);

  costTimelineChart = new Chart(canvas, {
    type: 'bar',
    data: {
      labels: dates,
      datasets: [
        { label: 'Input',          data: dates.map(d => +byDate[d].input.toFixed(4)),
          backgroundColor: '#58a6ff99', borderColor: '#58a6ff', borderWidth: 1 },
        { label: 'Output',         data: dates.map(d => +byDate[d].output.toFixed(4)),
          backgroundColor: '#e3b34199', borderColor: '#e3b341', borderWidth: 1 },
        { label: 'Cache creation', data: dates.map(d => +byDate[d].cache.toFixed(4)),
          backgroundColor: '#bc8cff99', borderColor: '#bc8cff', borderWidth: 1 },
      ]
    },
    options: {
      responsive: true,
      plugins: {
        legend: { labels: { color: '#8b949e', boxWidth: 12 } },
        tooltip: { callbacks: { label: ctx => ' ' + ctx.dataset.label + ': $' + ctx.raw.toFixed(3) } }
      },
      scales: {
        x: { stacked: true, ticks: { color: '#8b949e', maxTicksLimit: 10 }, grid: { color: '#21262d' } },
        y: { stacked: true, ticks: { color: '#8b949e', callback: v => '$' + v.toFixed(2) }, grid: { color: '#21262d' } }
      }
    }
  });
}
```

### Step 6.4 — Add `renderCostByProjectChart`

- [ ] Add after `renderCostTimelineChart`:

```js
let costProjectChart = null;

function renderCostByProjectChart(sessions, container) {
  container.innerHTML = '';
  if (costProjectChart) { costProjectChart.destroy(); costProjectChart = null; }

  const byProject = {};
  for (const s of sessions) {
    const p = s.project_name || '(unknown)';
    byProject[p] = (byProject[p] || 0) + computeCost(s);
  }
  const entries = Object.entries(byProject).sort((a, b) => b[1] - a[1]);

  if (entries.length === 0) {
    container.appendChild(emptyState('No cost data'));
    return;
  }

  const canvas = document.createElement('canvas');
  canvas.height = Math.max(80, entries.length * 28);
  container.appendChild(canvas);

  costProjectChart = new Chart(canvas, {
    type: 'bar',
    data: {
      labels:   entries.map(([p]) => p),
      datasets: [{ label: 'Est. Cost', data: entries.map(([, v]) => +v.toFixed(4)),
        backgroundColor: '#bc8cff66', borderColor: '#bc8cff', borderWidth: 1, borderRadius: 3 }]
    },
    options: {
      indexAxis: 'y', responsive: true,
      plugins: { legend: { display: false },
        tooltip: { callbacks: { label: ctx => ' $' + ctx.raw.toFixed(3) } } },
      scales: {
        x: { ticks: { color: '#8b949e', callback: v => '$' + v.toFixed(2) }, grid: { color: '#21262d' } },
        y: { ticks: { color: '#e6edf3' }, grid: { color: '#21262d' } }
      }
    }
  });
}
```

### Step 6.5 — Add `renderTabCost`

- [ ] Add after `renderCostByProjectChart`:

```js
function renderTabCost({ sessions, daily }, panel) {
  panel.innerHTML = '';

  renderCostStatCards(sessions, panel);
  renderCacheSavingsCard(sessions, panel);

  const tlCard = makeSection('Daily Cost Breakdown');
  const tlWrap = el('div', 'chart-wrap');
  tlCard.appendChild(tlWrap);
  panel.appendChild(tlCard);
  renderCostTimelineChart(sessions, tlWrap);

  const projCard = makeSection('Cost by Project');
  const projWrap = el('div', 'chart-wrap');
  projCard.appendChild(projWrap);
  panel.appendChild(projCard);
  renderCostByProjectChart(sessions, projWrap);
}
```

### Step 6.6 — Verify Cost tab

- [ ] Click Cost tab
- [ ] 3 stat cards: Total / This Month / Avg per session — all show dollar values
- [ ] Cache savings card shows a positive dollar amount
- [ ] Daily cost stacked bar: 3 segments (input/output/cache creation) per day
- [ ] Cost by project: horizontal bars sorted descending by cost

---

## Task 7: Final Integration Check

### Step 7.1 — Test filter interactions across tabs

- [ ] Apply 7d date filter — switch through all 4 tabs, each should reflect the filter
- [ ] Apply a project filter — Overview and Sessions filter; Analytics shows global tool/hourly data (by design)
- [ ] Clear all filters — all tabs should show full data

### Step 7.2 — Check for chart instance leaks

- [ ] Switch between tabs 5+ times rapidly in the browser
- [ ] Open DevTools console — confirm no "Canvas is already in use" errors
- [ ] If errors appear: find the chart global variable for the leaking function, confirm `destroy()` is called before `container.innerHTML = ''`

### Step 7.3 — Verify responsive layout

- [ ] At full width (>1100px): 6 stat cards in one row
- [ ] At 768–1100px: 3 cards per row
- [ ] At <768px: 2 cards per row

### Step 7.4 — Add `.superpowers/` to `.gitignore`

- [ ] Add to root `.gitignore` (create if missing):

```
.superpowers/
```
