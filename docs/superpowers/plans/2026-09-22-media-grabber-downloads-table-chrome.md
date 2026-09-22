# MediaGrabber — Downloads table chrome: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the SwiftUI `LazyVStack` Downloads body with an AppKit `NSTableView` grid that owns selection, column resize/reorder, and scrolling; add multi-select + batch bar; persist column widths — matching the locked design.

**Architecture:** Bottom-up: `ColumnConfig.columnWidths` + pure selection/batch/width helpers first; `RowStore` selection state next; SwiftUI `SelectionBar` + `AppModel` batch handlers; then one `NSViewRepresentable` AppKit island (`DownloadsGridView`) that draws headers/cells with shared design tokens (no default `NSHostingView` cells). `DownloadsTable` keeps Columns menu + batch bar in SwiftUI and embeds the grid. Retire the SwiftUI `DownloadRow` stack once the grid is feature-complete.

**Tech Stack:** Swift 6, SwiftUI shell, AppKit `NSTableView`, XCTest, Tuist, `mise`-pinned swiftformat/swiftlint. Deployment target macOS 14.

**Spec:** `docs/superpowers/specs/2026-09-22-media-grabber-downloads-table-chrome-design.md` (primary). Also parent `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §5.3/§5.4/§12.1 Phase 12; product contract `apps/media-grabber/docs/job-status-and-actions.md` §8; mockups `apps/media-grabber/docs/mockups/screens/{home,column-interactions}.html`; design-system `apps/media-grabber/docs/design-system.md` §4.2.

## Global Constraints

- No phase/ticket/epic references in source or UI copy (comments, identifiers, tooltips — nothing).
- Comments: single-line only, WHY only, max 120 chars. No `///` doc comments.
- No git commands unless the user explicitly asks in that turn. File moves use plain `mv`.
- Framework seam: **inside Downloads grid bounds = AppKit; outside = SwiftUI.** Cells and headers are **AppKit-drawn** with shared palette/type/spacing tokens. Default `NSHostingView` per cell is forbidden without an explicit design amendment.
- Flat `NSTableView` + synthetic playlist group header rows from `RowStore.visibleItems` — not `NSOutlineView`.
- Checkbox column is not a `ColumnID` — fixed width, not in `columnWidths`.
- Actions column: not resizable, pinned last, not reordered. Title always visible, may reorder.
- Live width readout while dragging → not this work (Phase 13).
- Queue-row drag-reorder → not this work (Phase 14).
- Selection is session-only (not persisted).
- After adding/removing files: `mise exec -- tuist generate --no-open`.
- Test: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`. Single suite: `-only-testing:GrabberKitTests/<Suite>` or `-only-testing:AppUnitTests/<Suite>`.
- Lint: `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict` from `apps/media-grabber`.
- `GrabberKit` must not import SwiftUI/AppKit UI frameworks beyond what it already uses (Foundation). Selection/batch UI helpers that need `RowModel` live in the App target; pure `ColumnConfig` width storage lives in GrabberKit.

---

## File Structure

**New — GrabberKit:**
| File | Responsibility |
|---|---|
| *(none required beyond ColumnConfig edits)* | Widths live on `ColumnConfig` |

**New — App target:**
| File | Responsibility |
|---|---|
| `Sources/App/Table/RowSelection.swift` | Pure selection helpers: prune ∩ visible, Shift-range over visible child order, toggle |
| `Sources/App/Table/BatchEligibility.swift` | Pure: which batch verbs to offer / which selected IDs each verb applies to |
| `Sources/App/Table/SelectionBar.swift` | SwiftUI batch bar (`N selected` + verbs + clear) |
| `Sources/App/Table/DownloadsGridView.swift` | `NSViewRepresentable` wrapper |
| `Sources/App/Table/DownloadsGridController.swift` | `NSTableView` data source/delegate, column sync, selection sync, resize/reorder, AppKit cell/header drawing |
| `Sources/App/Table/DownloadsGridTokens.swift` | Bridge: read current `PaletteTokens` / fonts / spacing into AppKit `NSColor`/`NSFont` for cell drawing |
| `Sources/App/Table/DownloadsGridColumns.swift` | Checkbox + `ColumnID` column identifiers, min widths, resize eligibility |
| `Sources/App/AppModelBatchActions.swift` | `handleBatchAction(_:)` — confirms + loops eligible IDs via existing row handlers / engine |

**New — Tests:**
| File | Responsibility |
|---|---|
| `Tests/AppUnitTests/RowSelectionTests.swift` | Prune, toggle, Shift-range |
| `Tests/AppUnitTests/BatchEligibilityTests.swift` | Verb offer + apply sets; Force start single-eligible rule |
| `Tests/AppUnitTests/ColumnWidthTests.swift` | Resolve / clamp / (optional) autofit measure helpers |
| `Tests/AppUnitTests/RowStoreSelectionTests.swift` | Selection prune on chip/filter/collapse |
| `Tests/AppUnitTests/AppModelBatchActionTests.swift` | Batch remove confirm / force-start gate |

**Modified:**
| File | Change |
|---|---|
| `Sources/GrabberKit/Model/ColumnConfig.swift` | `columnWidths: [ColumnID: Double]`; Codable; `setColumnWidth` |
| `Sources/App/Table/ColumnMetrics.swift` | `resolvedWidth(for:config:)`, `minWidth(for:)`, `clamped(_:for:)`, `isResizable(_:)` |
| `Sources/App/Rows/RowStore.swift` | `selectedJobIDs`, `selectionAnchorID`, mutation APIs, prune in `recomputeVisible` / `applyGroups` |
| `Sources/App/Table/DownloadsTable.swift` | Embed `SelectionBar` + `DownloadsGridView`; remove LazyVStack/`DownloadRow` body |
| `Sources/App/AppModel.swift` | Persist widths via existing `saveColumns` on config change; batch entry points if needed |
| `Sources/App/Home/HomeView.swift` | Pass any new bindings into `DownloadsTable` if required |
| `Tests/AppUnitTests/ColumnConfigTests.swift` | Width round-trip + unknown ID drop |
| `apps/media-grabber/docs/design-system.md` | §4.2 selection column, batch bar, AppKit grid note |
| Parent design §5.3/§5.4 | Reverse “no row selection”; AppKit seam |
| `apps/media-grabber/CLAUDE.md` | Point at Phase 12 design + plan |
| `apps/media-grabber/README.md` | Already notes Phase 12 chrome — keep accurate |
| Mockups | Add batch-bar fragment to `home.html` if missing |

**Retire when grid is complete:**
| File | Fate |
|---|---|
| `Sources/App/Table/DownloadRow.swift` | Delete once AppKit cells cover the same columns/actions (or slim to shared string formatters moved elsewhere first) |
| `Sources/App/Table/PlaylistGroupHeader.swift` | Delete once group header row is drawn in AppKit |

---

## Task 1: `ColumnConfig.columnWidths` persistence

**Status:** done (2026-09-22)

**Files:**
- Modify: `Sources/GrabberKit/Model/ColumnConfig.swift`
- Modify: `Tests/AppUnitTests/ColumnConfigTests.swift`

**Interfaces:**
- Produces: `public var columnWidths: [ColumnID: Double]` on `ColumnConfig` (default `[:]`).
- Produces: `public mutating func setColumnWidth(_ column: ColumnID, _ width: Double)` — ignores `.actions`; stores finite positive values only.
- Codable: encode/decode under key `columnWidths` as `[String: Double]`; unknown column keys dropped (same pattern as `columnFilters`).

- [ ] **Step 1: Write the failing tests**

Append to `ColumnConfigTests.swift`:

```swift
func test_columnWidthsRoundTrip() throws {
    var original = ColumnConfig.default
    original.setColumnWidth(.title, 320)
    original.setColumnWidth(.site, 120)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ColumnConfig.self, from: data)
    XCTAssertEqual(decoded.columnWidths[.title], 320)
    XCTAssertEqual(decoded.columnWidths[.site], 120)
}

func test_setColumnWidthIgnoresActions() {
    var config = ColumnConfig.default
    config.setColumnWidth(.actions, 400)
    XCTAssertNil(config.columnWidths[.actions])
}

func test_unknownWidthKeyDroppedOnLoad() throws {
    let json = """
    {
      "visibleColumns": ["title", "actions"],
      "columnOrder": ["title", "actions"],
      "columnWidths": { "title": 280, "bogus": 99 }
    }
    """
    let config = try JSONDecoder().decode(ColumnConfig.self, from: Data(json.utf8))
    XCTAssertEqual(config.columnWidths[.title], 280)
    XCTAssertEqual(config.columnWidths.count, 1)
}
```

- [ ] **Step 2: Run tests — expect FAIL** (property missing)

```bash
cd apps/media-grabber && xcodebuild -workspace MediaGrabber.xcworkspace \
  -scheme MediaGrabber-Workspace -destination 'platform=macOS' \
  -only-testing:AppUnitTests/ColumnConfigTests test
```

- [ ] **Step 3: Implement**

Add `columnWidths` to the struct, init (default `[:]`), `CodingKeys`, decode/encode maps, `setColumnWidth`, and include `columnWidths` in `Equatable` synthesis (stored property).

- [ ] **Step 4: Run tests — expect PASS**; lint GrabberKit + AppUnitTests touch paths.

---

## Task 2: `ColumnMetrics` resolve / clamp / resizable

**Status:** done (2026-09-22)

**Files:**
- Modify: `Sources/App/Table/ColumnMetrics.swift`
- Create: `Tests/AppUnitTests/ColumnWidthTests.swift`

**Interfaces:**
- Produces:
  - `static func resolvedWidth(for column: ColumnID, config: ColumnConfig) -> CGFloat`
  - `static func minWidth(for column: ColumnID) -> CGFloat` — use 48 for compact cols (speed/eta/attempt), 80 default, 120 title minimum, checkbox handled outside
  - `static func clamped(_ width: CGFloat, for column: ColumnID) -> CGFloat` — `max(minWidth, width)`
  - `static func isResizable(_ column: ColumnID) -> Bool` — `column != .actions`
  - Keep existing `width(for:)` as the **default** map used when `config.columnWidths[column] == nil`

- [ ] **Step 1: Failing tests**

```swift
@testable import MediaGrabber
@testable import GrabberKit
import XCTest

final class ColumnWidthTests: XCTestCase {
    func test_resolvedUsesOverride() {
        var config = ColumnConfig.default
        config.setColumnWidth(.title, 333)
        XCTAssertEqual(ColumnMetrics.resolvedWidth(for: .title, config: config), 333)
    }

    func test_resolvedFallsBackToDefault() {
        let config = ColumnConfig.default
        XCTAssertEqual(
            ColumnMetrics.resolvedWidth(for: .title, config: config),
            ColumnMetrics.width(for: .title)
        )
    }

    func test_clampEnforcesMinimum() {
        let min = ColumnMetrics.minWidth(for: .title)
        XCTAssertEqual(ColumnMetrics.clamped(10, for: .title), min)
    }

    func test_actionsNotResizable() {
        XCTAssertFalse(ColumnMetrics.isResizable(.actions))
        XCTAssertTrue(ColumnMetrics.isResizable(.title))
    }
}
```

(If `@testable import MediaGrabber` is wrong for this target’s module name, match whatever `DownloadsTableTests` uses.)

- [ ] **Step 2: Run — FAIL**
- [ ] **Step 3: Implement** the four helpers on `ColumnMetrics`
- [ ] **Step 4: Run — PASS**; lint

---

## Task 3: Pure `RowSelection` helpers

**Status:** done (2026-09-22)

**Files:**
- Create: `Sources/App/Table/RowSelection.swift`
- Create: `Tests/AppUnitTests/RowSelectionTests.swift`

**Interfaces:**
- Produces:

```swift
enum RowSelection {
    static func prune(_ selected: Set<UUID>, visibleChildIDs: Set<UUID>) -> Set<UUID>
    static func toggle(_ id: UUID, in selected: Set<UUID>) -> Set<UUID>
    /// Shift-click: select inclusive range between anchor and target in visibleChildOrder.
    /// If anchor is nil or not in order, result is `{ target }` only.
    static func rangeSelecting(
        from anchor: UUID?,
        to target: UUID,
        visibleChildOrder: [UUID],
        replacing selected: Set<UUID>
    ) -> Set<UUID>
}
```

Range replaces selection with the inclusive slice (standard macOS table Shift behavior), not union — unless product later amends; **lock replace** for this plan.

- [ ] **Step 1: Failing tests** covering prune drops invisible; toggle add/remove; range with/without anchor; anchor missing from order
- [ ] **Step 2: Run — FAIL**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run — PASS**; lint

---

## Task 4: Pure `BatchEligibility`

**Status:** done (2026-09-22)

**Files:**
- Create: `Sources/App/Table/BatchEligibility.swift`
- Create: `Tests/AppUnitTests/BatchEligibilityTests.swift`

**Interfaces:**
- Consumes: `JobSnapshot.availableActions`, `RowAction`
- Produces:

```swift
enum BatchEligibility {
    /// Verbs shown on the bar, in `RowAction.displayOrder`, excluding
    /// reveal / openInBrowser / showLog / retryWithCookies (batch bar follows
    /// job-status-and-actions.md §8: Pause, Resume, Cancel, Restart, Remove,
    /// Force start). Restart == `.retry`.
    static func offeredVerbs(snapshots: [JobSnapshot]) -> [RowAction]

    /// IDs among `snapshots` for which `verb` is in `availableActions`.
    static func applicableIDs(verb: RowAction, snapshots: [JobSnapshot]) -> [UUID]
}
```

Force start rule: include `.forceStart` in `offeredVerbs` **only when** `applicableIDs(forceStart).count == 1`.

- [ ] **Step 1: Failing tests** — mixed states offer Pause only for running; Force start hidden when 0 or 2+ eligible; Restart maps to `.retry`
- [ ] **Step 2–4:** implement TDD; lint

---

## Task 5: `RowStore` selection state + prune

**Status:** done (2026-09-22) — selection APIs live in `RowStore+Selection.swift`

**Files:**
- Modify: `Sources/App/Rows/RowStore.swift`
- Create: `Tests/AppUnitTests/RowStoreSelectionTests.swift`
- Modify: `Sources/App/Rows/RowStore+Groups.swift` if `applyGroups` / `recomputeVisible` need an explicit prune call site

**Interfaces:**
- Produces on `RowStore`:
  - `var selectedJobIDs: Set<UUID> = []`
  - `var selectionAnchorID: UUID? = nil`
  - `func visibleChildIDs() -> Set<UUID>`
  - `func visibleChildOrder() -> [UUID]`
  - `func setSelectedJobIDs(_ ids: Set<UUID>, anchor: UUID?)`
  - `func clearSelection()`
  - `func selectAllVisibleChildren()`
  - Private/shared: after `visibleItems` is rebuilt, `selectedJobIDs = RowSelection.prune(...)`; clear anchor if pruned out

- [ ] **Step 1: Failing tests** — select two IDs, switch `activeChip` so one leaves visible set → one remains; collapse group drops hidden children from selection; `selectAllVisibleChildren` ignores headers
- [ ] **Step 2–4:** implement; ensure every path that assigns `visibleItems` prunes (grep `visibleItems =`)
- [ ] Lint + `RowStoreTests` / `RowStoreGroupTests` still pass

---

## Task 6: `AppModel` batch actions

**Status:** done (2026-09-22)

**Files:**
- Create: `Sources/App/AppModelBatchActions.swift`
- Create: `Tests/AppUnitTests/AppModelBatchActionTests.swift`
- Modify: `Project.swift` / Tuist sources only if new file not auto-globbed (this repo usually globs — verify)

**Interfaces:**
- Produces:

```swift
extension AppModel {
    func handleBatchAction(_ action: RowAction) async
    func clearTableSelection()
}
```

Behavior:
- Resolve snapshots for `rowStore.selectedJobIDs`
- `ids = BatchEligibility.applicableIDs(verb:action, snapshots:)`
- `.remove`: if any selected snapshot `needsRemoveConfirm`, one confirm for the batch; on confirm remove all applicable (or all selected per §8 — **applicable only**)
- `.forceStart`: only when applicable count == 1; reuse `confirmedForceStart`
- `.cancel` / `.pause` / `.resume` / `.retry`: loop `handleRowAction` / engine calls without per-row confirms except where single-row already confirms (Cancel all batch uses existing cancel confirm policy from `job-status-and-actions.md` — if single Cancel needs confirm for active jobs, one batch confirm covering the set)
- Read `AppModelDialogs` and §8 confirms table; mirror playlist group cancel/remove patterns in `AppModelRowActions`

- [ ] **Step 1: Failing tests** with fake engine / existing AppModel test harness (match `AppModelRowActionTests`)
- [ ] **Step 2–4:** implement; lint

---

## Task 7: SwiftUI `SelectionBar`

**Status:** done (2026-09-22)

**Files:**
- Create: `Sources/App/Table/SelectionBar.swift`
- Modify: `Sources/App/Table/DownloadsTable.swift` — show bar above grid when selection non-empty (can sit above the still-SwiftUI body until Task 8 swaps the body)

**Interfaces:**
- `struct SelectionBar: View` — inputs: `selectedCount: Int`, `verbs: [RowAction]`, `onAction: (RowAction) -> Void`, `onClear: () -> Void`
- Copy: `"\(selectedCount) selected"`; verb buttons use existing `RowAction` display titles from `Icon` / accessibility labels already used in `DownloadRow`
- Hidden when `selectedCount == 0` (caller may also conditionally omit)

- [ ] **Step 1:** Implement view + wire into `DownloadsTable` reading `store.selectedJobIDs` and `BatchEligibility.offeredVerbs`
- [ ] **Step 2:** Manual smoke via `make` later; no UI snapshot required
- [ ] **Step 3:** Lint

---

## Task 8: AppKit grid scaffolding — representable + text cells

**Status:** done (2026-09-22)

**Files:**
- Create: `Sources/App/Table/DownloadsGridView.swift`
- Create: `Sources/App/Table/DownloadsGridController.swift`
- Create: `Sources/App/Table/DownloadsGridColumns.swift`
- Modify: `Sources/App/Table/DownloadsTable.swift` — replace LazyVStack/`DownloadRow`/`PlaylistGroupHeader` with `DownloadsGridView`
- Run: `mise exec -- tuist generate --no-open` if needed

**Interfaces:**
- `DownloadsGridView: NSViewRepresentable` — binds/observes `RowStore`, `ColumnConfig` binding, action closures matching current `DownloadsTable` (`onAction`, `onPlaylistGroupAction`, `onTogglePlaylistGroupCollapsed`)
- Controller builds `NSScrollView` + `NSTableView` (or table inside scroll), one row per `visibleItems` entry
- Columns: leading checkbox column (fixed id `"sel"`) + one `NSTableColumn` per `orderedVisibleColumns()`
- **Temporary cells:** `NSTextField` cell values from existing `TablePresentation` / `RowModel` string helpers — enough to prove data sync
- Group header rows: full-width style (or first cell spanning), non-selectable
- Do **not** use `NSHostingView` for cells

- [ ] **Step 1:** Implement controller + representable; wire into `DownloadsTable`
- [ ] **Step 2:** Build app (`make` or xcodebuild build-only); empty queue + queued rows render
- [ ] **Step 3:** Lint; fix `DownloadsTableTests` that assumed SwiftUI row structure

**Note:** Keep `DownloadRow.swift` on disk until Task 12–13 so formatters can be moved deliberately.

---

## Task 9: Selection sync (checkbox, ⌘-click, Shift-click, select-all)

**Status:** done (2026-09-22)

**Files:**
- Modify: `DownloadsGridController.swift`
- Relies on: Task 3–5

**Behavior:**
- Checkbox column toggles membership via `RowSelection.toggle` + `setSelectedJobIDs`
- Row click: without modifiers → select only that child (and set anchor); ⌘ → toggle; Shift → `rangeSelecting`
- Header checkbox → `selectAllVisibleChildren` / clear all visible
- Group header rows ignore selection clicks
- Table highlight mirrors `selectedJobIDs` (programmatic selection updates must not loop)

- [ ] **Step 1:** Implement delegate hooks
- [ ] **Step 2:** Manual verify against mockup behaviors; unit tests already cover pure helpers
- [ ] **Step 3:** Lint

---

## Task 10: Column resize → `columnWidths` + persist

**Status:** done (2026-09-22)

**Files:**
- Modify: `DownloadsGridController.swift`
- Modify: `ColumnMetrics` / `DownloadsGridColumns` for min widths
- `AppModel.columnConfig` didSet already calls `persistence?.saveColumns` — ensure width mutations go through the same binding

**Behavior:**
- User resize of a resizable column writes `config.setColumnWidth` + `clamped`
- Actions + checkbox: `NSTableColumn` not user-resizable (`isResizable = false` / no resize divider)
- Table total width = sum of resolved widths + checkbox

- [ ] **Step 1:** Implement `tableViewColumnDidResize` (or column resize notification) → update binding
- [ ] **Step 2:** Relaunch app — width survives restart via `columns.json`
- [ ] **Step 3:** Lint

---

## Task 11: Column drag-reorder → `moveColumn`

**Status:** done (2026-09-22)

**Files:**
- Modify: `DownloadsGridController.swift`

**Behavior:**
- Enable column reordering on the table; on reorder, map identifiers to `ColumnID`s and call `columnConfig.moveColumn(from:to:)` then rebuild columns if needed
- Actions column must remain last (enforce after drop; reject moves involving actions)
- Checkbox column stays first and is not a `ColumnID` reorder target

- [x] **Step 1–3:** implement, manual verify, lint

---

## Task 12: Double-click divider auto-fit

**Status:** done (2026-09-22)

**Files:**
- Modify: `DownloadsGridController.swift`
- Optionally add pure helper `ColumnMetrics.autoFitWidth(sampleStrings:min:)` in App + test in `ColumnWidthTests`

**Behavior:**
- Double-click resize region on a resizable column → measure widest string among **currently visible** child rows for that column (use the same display string the cell shows) → `clamped` → `setColumnWidth`
- One-shot (not continuous binding to content)

- [x] **Step 1:** Helper + unit test with sample strings
- [x] **Step 2:** Wire double-click
- [x] **Step 3:** Lint

---

## Task 13: AppKit-drawn skinned cells + headers

**Status:** done (2026-09-22)

**Files:**
- Create: `Sources/App/Table/DownloadsGridTokens.swift`
- Modify: `DownloadsGridController.swift` (custom `NSTableCellView` / `NSView` subclasses as needed)
- Modify: design tokens access from existing `Theme` / `PaletteTokens`

**Behavior:**
- Body cells match Aurora/Tape Deck: title, progress bar, speed/ETA text, Actions icon buttons calling `onAction`
- Group header: disclosure, title, rollup, group actions (parity with `PlaylistGroupHeader`)
- Header cells: title + sort affordance + filter affordance where `ColumnMetrics.supportsFilter`; grip visual optional; resize edges native
- Sort click → `columnConfig.cycleSort` via binding
- Filter → present existing filter UI (reuse `ColumnsMenu` filter presentation pattern or `NSMenu` built from current filter values) — must call into same `columnFilters` model
- Remark: show on hover/focus in AppKit (tooltip or overlay) matching Phase 11 behavior if already present in SwiftUI row — port that behavior

- [x] **Step 1:** Token bridge
- [x] **Step 2:** Cell view classes per column kind (start with title/progress/actions; then remaining)
- [x] **Step 3:** Headers
- [x] **Step 4:** Visual pass against `home.html` / `column-interactions.html` (no live readout)
- [x] **Step 5:** Lint; full AppUnitTests

---

## Task 14: Retire SwiftUI row stack

**Status:** done (2026-09-22)

**Files:**
- Delete: `DownloadRow.swift`, `PlaylistGroupHeader.swift` if fully replaced
- Move any still-needed formatters into `TablePresentation` / small helpers first
- Fix tests that imported deleted types
- `tuist generate` if project lists files explicitly

- [x] **Step 1:** Grep for `DownloadRow` / `PlaylistGroupHeader` — zero references
- [x] **Step 2:** Delete; fix compile
- [x] **Step 3:** Full test suite + lint

---

## Task 15: Documentation

**Status:** done (2026-09-22)

**Files:**
- Modify: parent design §5.3 / §5.4 (row selection + AppKit seam)
- Modify: `apps/media-grabber/docs/design-system.md` §4.2
- Modify: `apps/media-grabber/docs/mockups/screens/home.html` — add one fragment for batch bar if missing
- Modify: `apps/media-grabber/CLAUDE.md` — Phase 12 design + plan paths; Next: Phase 13 when shipped
- Modify: `apps/media-grabber/ticket-backlog.md` — leave Phase 12 unmarked shipped until implementation finishes
- Update design spec status line if needed

- [x] **Step 1:** Doc edits only — no behavior changes
- [x] **Step 2:** Grep parent for “no row selection” / “no per-row expansion” contradictions; fix

---

## Spec coverage checklist (self-review)

| Spec item | Task |
|---|---|
| AppKit entire grid + SwiftUI shell | 8–13 |
| No default NSHostingView cells | 8, 13 |
| Flat table + synthetic group rows | 8, 13 |
| Selection SoT on RowStore + prune | 3, 5, 9 |
| ⌘ / Shift / checkbox / select-all visible | 3, 5, 9 |
| Batch bar above table | 7, 6 |
| Per-row actions stay | 13 |
| columnWidths persist | 1, 2, 10 |
| Resize except Actions + checkbox | 2, 10 |
| Double-click autofit | 12 |
| moveColumn reorder | 11 |
| No live readout | (explicit non-goal) |
| No row drag-reorder | (explicit non-goal) |
| Docs | 15 |

---

## Execution notes for agents

- Prefer logic tasks 1–6 before AppKit 8+ so reviews stay small.
- Do not commit unless the user asks.
- When Task 8 lands, the app must still build even if cells are plain text.
- Skin parity is Task 13’s job — do not block Task 8–12 on perfect visuals.
