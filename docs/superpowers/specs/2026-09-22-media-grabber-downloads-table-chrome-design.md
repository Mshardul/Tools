# Downloads table chrome — design

**Status:** implemented — plan:
`docs/superpowers/plans/2026-09-22-media-grabber-downloads-table-chrome.md`.
Review this file as the single source for Phase 12 design.

**Owner phase:** Phase 12 (Downloads table chrome).  
**Parent:** `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §5.3/§5.4, §12.1 Phase 12.  
**Product contract (selection / batch verbs):** `apps/media-grabber/docs/job-status-and-actions.md` §8.  
**Visual target:** `apps/media-grabber/docs/mockups/screens/{home,column-interactions}.html`.  
**Leaf backlog:** `apps/media-grabber/ticket-backlog.md` Phase 12.

---

## Intent

Ship Downloads **table chrome** on a durable substrate: column header
drag-reorder, resizable widths (with double-click auto-fit), multi-select +
batch actions, matching the locked manager Home (status rail; Status hidden
by default). Progress / Speed / ETA stay separate columns.

Long-term: **AppKit owns the entire Downloads table surface**; **SwiftUI owns
the app chrome around it** (and the rest of the app). Phase 14 queue-row
drag-reorder lands on the same AppKit grid — not in this phase.

## Not this phase

- Queue-row drag-reorder → **Phase 14**
- Merged Progress/Speed/ETA column — never (locked)
- Reintroducing top filter chips — never (rail owns that)
- Pure SwiftUI `Table` as the grid
- Keeping today’s `LazyVStack` row stack as the long-term engine
- `NSHostingView` per cell as the default cell path (see §1)
- First-run empty Home copy redesign / Aurora body-face swap → Phase 13
- Live column-width readout while dragging → Phase 13
- Full a11y sweep beyond what this chrome needs to ship correctly → Phase 13

---

## Locked product decisions (2026-09-22 and earlier)

| Topic | Decision |
|---|---|
| Row drag-reorder | Park Phase 14 |
| Batch chrome | Bar **above** the table when selection non-empty (`N selected` + eligible verbs); hide when empty. Not a floating footer. |
| Per-row Actions | Stay visible while selection active; batch bar is additive; row action targets that row only |
| Header select-all | Currently **visible** child rows only (after rail + column filters); not collapsed-away playlist children |
| Selection vs rail/filters | Keep selected job IDs that remain visible; drop the rest. No off-screen batch. |
| Resize targets | Every data column **except** Actions + checkbox column; min-width clamp |
| Auto-fit | Double-click divider → one-shot width to widest visible cell content |
| Width persistence | In `ColumnConfig` (existing `columns.json` debounce path) |
| Multi-select input | Checkboxes + ⌘-click toggle + Shift-click range over visible-row order |
| Batch verbs | Same as §8 of `job-status-and-actions.md`; Force start only when exactly one selected row is eligible |
| Progress / Speed / ETA | Stay separate columns |
| Framework seam | **Table edge:** AppKit = entire Downloads grid; SwiftUI = shell outside that rect |
| Cell rendering | **AppKit-drawn** cells (shared palette/spacing tokens). SwiftUI hosting in a cell is an exception, not the default |
| Playlist groups in grid | Flat `NSTableView` + synthetic group header rows from `visibleItems` (not `NSOutlineView`) |
| Live width readout | Phase 13 polish — not Phase 12 |
| Header chrome | AppKit-drawn (same island as body); sort/filter invoke existing `ColumnConfig` / UI intents |
| `columnWidths` persistence | On `ColumnConfig` → `columns.json`; absent key → `ColumnMetrics` default |
| Selection persistence | Session only — not saved across launches |

---

## §1 Architecture — boundaries *(decided)*

### Why a second framework (justification)

Two frameworks are allowed only when long-term gains beat the cost.

**AppKit buys for Downloads:** native manager UX (selection, column
resize/reorder, keyboard feel), virtualized scale for playlist-sized queues,
and a substrate Phase 14 row-reorder can reuse — without reimplementing that
machinery in SwiftUI.

**Cost we accept:** one maintained AppKit island (the Downloads grid),
including AppKit-drawn headers and cells skinned via shared tokens.

**Cost we refuse:** hybrid rendering inside the grid (`NSHostingView` per
row/header as the default path) — that pays dual-framework cost without a
clean gain.

**Why not AppKit for the whole app:** Home / Preferences / About / dialogs /
skins are already SwiftUI and fit that stack; rewriting them is not justified.

**Why not SwiftUI-only for Downloads:** would mean owning a full table engine
forever; we choose native grid capability over stack purity for this surface.

### The seam (locked)

```text
SwiftUI:  Home chrome · rail · batch bar · Columns menu · dialogs · HealthStrip · …
          └─ embeds one AppKit Downloads grid ─┘
AppKit:   headers · rows · checkbox · selection · column resize/reorder · scroll
          (Phase 14: queue-row drag-reorder on this same grid)
```

One thick boundary: **inside the grid view’s bounds = AppKit; outside = SwiftUI.**

### SwiftUI owns

- Home layout (paste field, runway, rail, empty states)
- Batch bar (`N selected` + verbs)
- Columns menu, dialogs, HealthStrip, theme / palette **resolution**
- `RowStore` / `ColumnConfig` / `AppModel` as source of truth
- Shared design tokens (colors, fonts, spacing) consumed by both sides

### AppKit owns (entire Downloads table surface)

- `NSTableView` (flat list; synthetic playlist group header rows)
- Headers (grip affordance, title, sort/filter controls, resize edges) —
  **drawn in AppKit**, not hosted SwiftUI headers
- Body cells (Title, Progress, Actions, Remark, …) — **drawn in AppKit**
  using the same palette / type / spacing tokens as SwiftUI skins
- Selection (checkbox column, highlight, ⌘/Shift, header select-all)
- Column resize, reorder, width notifications
- Vertical scroll; header ↔ body horizontal sync
- Later (Phase 14): queue-row drag-reorder

### Bridge

- One `NSViewRepresentable` wrapper (working name: `DownloadsGridView`) in the
  slot today’s `DownloadsTable` body occupies
- Data in: `RowStore.visibleItems` (and related presentation state)
- Intents out: selection edits, `ColumnConfig.moveColumn`, width writes,
  row / playlist-group actions → existing `AppModel` handlers
- **No default `NSHostingView` cell path.** Exceptional hosting of a single
  complex control requires an explicit design amendment — not a shortcut for
  “reuse `DownloadRow` as-is.”

### Explicit non-goals for the substrate

- SwiftUI `Table` as the Downloads engine
- `LazyVStack` as the long-term row engine (retire once the grid ships)
- AppKit headers + SwiftUI body (width-sync tax without full gains)
- Default SwiftUI-hosted cells inside AppKit rows

---

## §2 Selection + batch bar *(decided)*

### Source of truth — `RowStore`

- `selectedJobIDs: Set<UUID>` — **child jobs only** (never playlist group IDs)
- `selectionAnchorID: UUID?` — Shift-range anchor
- After every `visibleItems` rebuild (rail, column filter, collapse):

  `selectedJobIDs = selectedJobIDs ∩ visibleChildIDs`

  Clear `selectionAnchorID` if it left the set.

- **Visible child IDs** = `.child` entries in `visibleItems` only
  (collapsed playlist children are already absent from `visibleItems`)

### AppKit grid mirrors selection

- Checkbox column + highlight driven from `selectedJobIDs`
- Gestures update that set (checkbox, ⌘-click toggle, Shift-click range over
  visible child order, header select-all = all visible children)
- Grid must not keep a divergent selection model

### Batch bar (SwiftUI, above the grid)

- Visible iff `!selectedJobIDs.isEmpty`
- Label: `N selected`
- Verb offered if **any** selected row is eligible; click applies only to
  eligible selected rows (`job-status-and-actions.md` §8)
- Force start: only when exactly one selected row is Force-start–eligible
- Confirms (Cancel / Remove / Force-start eviction): same policies as
  single-row / playlist group; one confirm for the batch
- Esc / explicit clear deselects all when appropriate

### Per-row Actions

- Unchanged intent path: `handleRowAction(id, action)` for that row only
- Remain visible while selection is non-empty
- Affordances drawn in AppKit cells; still call the same App handlers

### Playlist group headers (selection)

- **No** group-header checkbox this phase
- Select children individually or via header select-all (visible children)
- Existing group actions stay on the header (AppKit-drawn)

---

## §3 Columns — resize, reorder, persist *(decided)*

- Drag-reorder wires existing `ColumnConfig.moveColumn`; Actions pinned last
  and immovable; Title always visible but movable (parent §5.4)
- Resize: all data columns except Actions + checkbox; min-width clamp
- Double-click divider: one-shot auto-fit to widest **visible** cell
- Widths stored on `ColumnConfig` and persisted with existing debounce to
  `columns.json`
- Default widths today live in `ColumnMetrics` — become defaults when a
  column has no persisted override
- **Playlist groups:** flat `NSTableView` + synthetic non-selectable group
  header rows from `visibleItems` (collapse = children omitted). Not
  `NSOutlineView`.
- **Live width readout:** not in Phase 12 — Phase 13 polish. Resize + autofit
  + persist still ship now.
- **Header chrome:** AppKit-drawn inside the same island; sort / filter
  controls call into existing `ColumnConfig` / filter presentation (popovers
  or menus may be presented from the AppKit header without making the whole
  header a SwiftUI hosting view)

---

## §4 Data / persistence shape *(decided)*

`ColumnConfig` gains:

```text
columnWidths: [ColumnID: Double]   // points; absent → ColumnMetrics default
```

- Encode/decode with existing `columns.json` keys; unknown IDs dropped via
  existing invariant helpers
- Checkbox column is **not** a `ColumnID` — fixed width in the grid, not in
  `columnWidths`
- `enforceInvariants` unchanged for Actions/Title visibility + order

Selection is **not** persisted across launches (session UI state only).

---

## §5 Testing posture *(decided)*

- Pure logic: selection ∩ visible, Shift-range over visible child order,
  batch eligibility aggregation, width clamp / auto-fit measurement helpers
- `ColumnConfig` Codable round-trip including `columnWidths`
- UI / AppKit bridge: thin representable + focused tests where practical;
  prefer logic outside the view

---

## Doc pointers to update when this design is approved for planning

- Parent §5.3 / §5.4 — reverse “no row selection”; describe AppKit grid seam +
  batch bar
- `apps/media-grabber/docs/design-system.md` §4.2 — selection column, batch
  bar, resize/reorder chrome; note AppKit-drawn table cells use shared tokens
- Mockup batch-bar screen if missing (checkbox column already in Home /
  column-interactions)
- Phase 12 implementation plan (after this spec is approved)
