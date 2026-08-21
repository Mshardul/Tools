const SQL_CDN = 'https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.10.3/sql-wasm.js';
const SQL_WASM = 'https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.10.3/sql-wasm.wasm';

function loadScript(src) {
  return new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = src;
    s.onload = resolve;
    s.onerror = () => reject(new Error(`Failed to load ${src}`));
    document.head.appendChild(s);
  });
}

async function ensureSqlJs() {
  if (window.initSqlJs) return;
  await loadScript(SQL_CDN);
}

// --- DB queries ---

function querySessions(db) {
  const stmt = db.prepare(`
    SELECT session_id, project_name, model, git_branch,
           first_timestamp, last_timestamp, turn_count,
           total_input_tokens, total_output_tokens,
           total_cache_read, total_cache_creation
    FROM sessions ORDER BY first_timestamp ASC
  `);
  const rows = [];
  while (stmt.step()) rows.push(stmt.getAsObject());
  stmt.free();
  return rows;
}

function queryDaily(db) {
  const stmt = db.prepare(`
    SELECT date(timestamp)            AS date,
           COUNT(DISTINCT session_id) AS sessions,
           COUNT(*)                   AS turns,
           SUM(input_tokens)          AS input_tokens,
           SUM(output_tokens)         AS output_tokens,
           SUM(cache_read_tokens)     AS cache_read_tokens,
           SUM(cache_creation_tokens) AS cache_creation_tokens
    FROM turns GROUP BY date(timestamp) ORDER BY date ASC
  `);
  const rows = [];
  while (stmt.step()) rows.push(stmt.getAsObject());
  stmt.free();
  return rows;
}

function queryProcessedPaths(db) {
  const stmt = db.prepare('SELECT path FROM processed_files');
  const paths = [];
  while (stmt.step()) paths.push(stmt.getAsObject().path);
  stmt.free();
  return paths;
}

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

// --- JSONL discovery and parsing ---

async function fetchDirLinks(url) {
  const res = await fetch(url);
  if (!res.ok) return [];
  const html = await res.text();
  return [...html.matchAll(/href="([^"?#]+)"/g)]
    .map(m => m[1])
    .filter(h => h !== '../' && h !== './' && !h.startsWith('/') && !h.startsWith('?'));
}

async function discoverUnprocessedJSONL(processedKeys) {
  const projectDirs = (await fetchDirLinks('/claude-usage/projects/')).filter(l => l.endsWith('/'));
  const unprocessed = [];
  for (const dir of projectDirs) {
    const files = (await fetchDirLinks(`/claude-usage/projects/${dir}`)).filter(f => f.endsWith('.jsonl'));
    for (const file of files) {
      const key = `${dir.replace(/\/$/, '')}/${file}`;
      if (!processedKeys.has(key)) {
        unprocessed.push(`/claude-usage/projects/${key}`);
      }
    }
  }
  return unprocessed;
}

async function parseJSONL(url) {
  const res = await fetch(url);
  if (!res.ok) return [];
  const text = await res.text();
  const entries = [];
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    try {
      const obj = JSON.parse(line);
      if (obj.type !== 'assistant') continue;
      const usage = obj.message?.usage;
      if (!usage) continue;
      entries.push({
        sessionId:             obj.sessionId,
        timestamp:             obj.timestamp,
        model:                 obj.message?.model ?? null,
        cwd:                   obj.cwd ?? null,
        gitBranch:             obj.gitBranch ?? null,
        input_tokens:          usage.input_tokens ?? 0,
        output_tokens:         usage.output_tokens ?? 0,
        cache_read_tokens:     usage.cache_read_input_tokens ?? 0,
        cache_creation_tokens: usage.cache_creation_input_tokens ?? 0,
        toolName: (obj.message?.content ?? []).find(c => c.type === 'tool_use')?.name ?? null,
      });
    } catch {}
  }
  return entries;
}

// --- Build structured data from JSONL entries ---

function buildSessionsFromEntries(entries) {
  const map = new Map();
  for (const e of entries) {
    if (!e.sessionId) continue;
    if (!map.has(e.sessionId)) {
      map.set(e.sessionId, {
        session_id: e.sessionId,
        project_name: e.cwd ? e.cwd.split('/').pop() : null,
        model: e.model,
        git_branch: e.gitBranch,
        first_timestamp: e.timestamp,
        last_timestamp: e.timestamp,
        turn_count: 0,
        total_input_tokens: 0,
        total_output_tokens: 0,
        total_cache_read: 0,
        total_cache_creation: 0,
      });
    }
    const s = map.get(e.sessionId);
    if (e.timestamp < s.first_timestamp) s.first_timestamp = e.timestamp;
    if (e.timestamp > s.last_timestamp) s.last_timestamp = e.timestamp;
    s.turn_count++;
    s.total_input_tokens += e.input_tokens;
    s.total_output_tokens += e.output_tokens;
    s.total_cache_read += e.cache_read_tokens;
    s.total_cache_creation += e.cache_creation_tokens;
  }
  return [...map.values()].sort((a, b) =>
    (a.first_timestamp ?? '').localeCompare(b.first_timestamp ?? '')
  );
}

function buildDailyFromEntries(entries) {
  const map = new Map();
  const sessionsByDate = new Map();
  for (const e of entries) {
    if (!e.timestamp) continue;
    const date = e.timestamp.slice(0, 10);
    if (!map.has(date)) {
      map.set(date, { date, sessions: 0, turns: 0, input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cache_creation_tokens: 0 });
      sessionsByDate.set(date, new Set());
    }
    const d = map.get(date);
    const seen = sessionsByDate.get(date);
    if (e.sessionId && !seen.has(e.sessionId)) {
      seen.add(e.sessionId);
      d.sessions++;
    }
    d.turns++;
    d.input_tokens += e.input_tokens;
    d.output_tokens += e.output_tokens;
    d.cache_read_tokens += e.cache_read_tokens;
    d.cache_creation_tokens += e.cache_creation_tokens;
  }
  return [...map.keys()].sort().map(date => map.get(date));
}

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

function mergeDailyData(a, b) {
  const map = new Map(a.map(d => [d.date, { ...d }]));
  for (const d of b) {
    if (map.has(d.date)) {
      const x = map.get(d.date);
      x.sessions += d.sessions;
      x.turns += d.turns;
      x.input_tokens += d.input_tokens;
      x.output_tokens += d.output_tokens;
      x.cache_read_tokens += d.cache_read_tokens;
      x.cache_creation_tokens += d.cache_creation_tokens;
    } else {
      map.set(d.date, { ...d });
    }
  }
  return [...map.keys()].sort().map(date => map.get(date));
}

// --- Meta ---

function buildMeta(sessions, daily) {
  const models = [...new Set(sessions.map(s => s.model).filter(m => m && !m.startsWith('<')))];
  const fromTs = sessions.map(s => s.first_timestamp).filter(Boolean).sort();
  const toTs = sessions.map(s => s.last_timestamp ?? s.first_timestamp).filter(Boolean).sort();
  const totalTurns = daily.reduce((sum, d) => sum + (d.turns ?? 0), 0);
  return {
    generated_at: new Date().toISOString(),
    date_range: {
      from: fromTs[0]?.slice(0, 10) ?? null,
      to: toTs[toTs.length - 1]?.slice(0, 10) ?? null,
    },
    total_sessions: sessions.length,
    total_turns: totalTurns,
    models,
  };
}

// --- Cost and context utilities ---

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

// --- Main ---

async function openDb() {
  await ensureSqlJs();
  const SQL = await initSqlJs({ locateFile: () => SQL_WASM });

  const res = await fetch('/claude-usage/usage.db');
  if (!res.ok) {
    throw new Error('Cannot fetch usage.db — run: ln -s ~/.claude/usage.db claude-usage/usage.db');
  }

  const buf = await res.arrayBuffer();
  const db = new SQL.Database(new Uint8Array(buf));

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

  const processedKeys = new Set(processedPaths.map(p => {
    const marker = '/.claude/projects/';
    const idx = p.indexOf(marker);
    return idx >= 0 ? p.slice(idx + marker.length) : p;
  }));

  const unprocessedUrls = await discoverUnprocessedJSONL(processedKeys);
  console.log(`Parsing ${unprocessedUrls.length} unprocessed JSONL files…`);

  const allEntries = [];
  for (const url of unprocessedUrls) {
    const entries = await parseJSONL(url);
    allEntries.push(...entries);
  }

  const jsonlSessions = buildSessionsFromEntries(allEntries);
  const jsonlDaily    = buildDailyFromEntries(allEntries);
  const jsonlTools    = buildToolsFromEntries(allEntries);
  const jsonlHourly   = buildHourlyFromEntries(allEntries);

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
}

let loading = false;

window.refresh = function () {
  if (loading) return;
  loading = true;
  openDb()
    .catch(err => {
      console.error(err.message);
      window.dispatchEvent(new CustomEvent('claude-data-error', { detail: err.message }));
    })
    .finally(() => { loading = false; });
};

window.refresh();
