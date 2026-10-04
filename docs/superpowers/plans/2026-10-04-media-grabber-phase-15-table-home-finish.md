# MediaGrabber Phase 15 — Table & Home Finish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship session-only Downloads row drag-reorder as view order (not engine priority), then swap Aurora’s body face off Inter and finish the first-run Home creative pass after visual picks.

**Architecture:** `RowStore` owns a session `manualOrder: [UUID]?`. When column sort is nil, visible blocks / children follow that permutation; starting a column sort clears it. AppKit `NSTableView` row drag proposes a move; if sort is active, `AppModel.confirm` asks to clear sorting, then applies the move. Engine job list / schedule stay untouched. Body-face and first-run tasks are gated on explicit visual picks after reorder DoD.

**Tech Stack:** Swift 6, SwiftUI + AppKit (`NSTableView` row drag), XCTest, Tuist-generated Xcode project.

**Spec:** `docs/superpowers/specs/2026-10-04-media-grabber-phase-15-table-home-finish-design.md` (read both together — spec carries locked decisions; this plan carries files/code).

## Global Constraints

- Working name stays `MediaGrabber`. No product-name / icon / Sparkle — Phase 17.
- Row drag = **view order only**. Do **not** add an engine `reorder` intent or mutate `QueueSnapshot.jobs` order for priority.
- Manual order is **session only** — not `columns.json`, not `queue.json`, not AppStorage.
- Banner → footer is **already shipped** — do not touch `WarningBanner` / MainWindow dock as Phase 15 work.
- Filters stay on drag; no filter-chip clear prompt.
- Group **headers** are not draggable. Cross-group child drops are refused (children reorder only within their group; ungrouped singles reorder among top-level blocks, including before/after a group via drop on the header row).
- New job IDs absent from `manualOrder` append at the **end** of `manualOrder` on the next recompute after snapshot apply (when manual order is active).
- Default `ColumnConfig` still has `sortColumn: .addedAt` — first drag with default prefs **must** hit the sort-overwrite confirm path.
- Visual picks (body face, first-run) are **blocking**: Task 5 records the picks; Tasks 6–7 must not invent a face/layout without that record.
- No git commands in this plan or its execution — the user commits later.
- Comments: single-line only, only for non-obvious *why*. No `///` doc comments, no stacked `//` blocks.
- Every source file path below is relative to `apps/media-grabber/` unless stated otherwise.
- Lint after every task: from `apps/media-grabber/`, `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict`.
- Test after every task: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:<Suite>` (never bare `tuist test` while debugging).
- After adding/removing files: `mise exec -- tuist generate --no-open`.

## File structure

| File | Responsibility |
|---|---|
| `Sources/App/Rows/RowStore.swift` | Own `manualOrder`; clear on sort; append new IDs; expose move API |
| `Sources/App/Rows/RowStore+Groups.swift` | Apply manual order when sorting blocks / group children with sort nil |
| `Sources/App/AppModelDialogs.swift` | `sortOverwriteConfirmation()` copy |
| `Sources/App/AppModelRowActions.swift` (or small `AppModel+RowReorder.swift`) | `handleRowReorder(from:to:)` confirm + clear sort + move |
| `Sources/App/Table/DownloadsGridController.swift` (+ new `+RowDrag.swift` if file grows) | NSTableView drag source/destination for child rows |
| `Sources/App/Table/DownloadsGridView.swift` / `DownloadsTable.swift` / `HomeView.swift` | Wire `onRowReorder` up to AppModel |
| `Sources/App/Theme/Theme.swift` | Aurora `bodyFont` family string after pick |
| `Resources/Fonts/<Chosen>/` | OFL + font file(s); remove unused Inter if nothing references it |
| `Sources/App/Home/HomeView.swift` | First-run layout/copy after pick |
| `Tests/AppUnitTests/RowStoreManualOrderTests.swift` | Manual-order unit coverage |
| `Tests/AppUnitTests/AppModelRowReorderTests.swift` | Confirm / cancel / clear-sort path |
| `Tests/AppUnitTests/ThemeTests.swift` | Chosen body face resolves (where testable) |

## Review Focus

- Default prefs (`sortColumn == .addedAt`) + drag → confirm shows; Cancel leaves sort and visible order unchanged.
- Proceed on confirm → `sortColumn` becomes nil, `manualOrder` set, columns.json persistence still saves the cleared sort (via existing `columnConfig` didSet).
- Header row drag / drop onto another group’s child → refused; no crash; order unchanged.
- New job arrives while `manualOrder` active → appears at end of visible list (not scrambled into the middle).
- User cycles header sort on after a manual order → `manualOrder` clears immediately; visible order follows the new sort.

---

### Task 1: `RowStore` session `manualOrder`

**Files:**
- Modify: `Sources/App/Rows/RowStore.swift`
- Modify: `Sources/App/Rows/RowStore+Groups.swift`
- Create: `Tests/AppUnitTests/RowStoreManualOrderTests.swift`

**Interfaces:**
- Consumes: existing `recomputeVisible()`, `VisibleItem`, `columnConfig.sortColumn`, snapshot apply path that rebuilds `rows`.
- Produces:
  - `private(set) var manualOrder: [UUID]?` on `RowStore`
  - `func clearManualOrder()`
  - `func setManualOrder(_ ids: [UUID])`
  - `@discardableResult func moveVisibleItem(from fromIndex: Int, to toIndex: Int) -> Bool`
  - `setColumnConfig` clears `manualOrder` when `config.sortColumn != nil`
  - On snapshot apply after models update: if `manualOrder != nil`, drop missing IDs and append any new row IDs at the end, then recompute

- [ ] **Step 1: Write the failing tests**

Create `Tests/AppUnitTests/RowStoreManualOrderTests.swift`. Reuse the `snap` / `queueSnapshot` helpers pattern from `RowStoreTests.swift` (copy the private helpers into this file — do not share via a new harness unless one already exists for RowStore).

```swift
@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class RowStoreManualOrderTests: XCTestCase {
    private var revision: UInt64 = 0

    // …snap / queueSnapshot helpers matching RowStoreTests (ids 1,2,3…)…

    func test_setManualOrder_reordersVisibleChildrenWhenSortNil() {
        var config = ColumnConfig.default
        config.sortColumn = nil
        config.sortDirection = nil
        let store = RowStore(columnConfig: config)
        store.apply(.snapshot(queueSnapshot([snap(1), snap(2), snap(3)])))
        XCTAssertEqual(store.visibleRows.map(\.id.uuidString.suffix(1)), ["1", "2", "3"])

        let ids = store.rows.map(\.id)
        store.setManualOrder([ids[2], ids[0], ids[1]])

        XCTAssertEqual(store.visibleRows.map(\.id), [ids[2], ids[0], ids[1]])
        XCTAssertEqual(
            store.visibleItems.compactMap { item -> UUID? in
                if case let .child(row) = item { return row.id }
                return nil
            },
            [ids[2], ids[0], ids[1]]
        )
    }

    func test_setColumnConfig_withSort_clearsManualOrder() {
        var config = ColumnConfig.default
        config.sortColumn = nil
        let store = RowStore(columnConfig: config)
        store.apply(.snapshot(queueSnapshot([snap(1), snap(2)])))
        let ids = store.rows.map(\.id)
        store.setManualOrder([ids[1], ids[0]])
        XCTAssertNotNil(store.manualOrder)

        var sorted = config
        sorted.sortColumn = .addedAt
        sorted.sortDirection = .ascending
        store.setColumnConfig(sorted)

        XCTAssertNil(store.manualOrder)
    }

    func test_moveVisibleItem_swapsUngroupedChildren() {
        var config = ColumnConfig.default
        config.sortColumn = nil
        let store = RowStore(columnConfig: config)
        store.apply(.snapshot(queueSnapshot([snap(1), snap(2), snap(3)])))
        let ids = store.rows.map(\.id)
        // visibleItems are all .child — move index 0 to before index 2
        XCTAssertTrue(store.moveVisibleItem(from: 0, to: 2))
        XCTAssertEqual(store.visibleRows.map(\.id), [ids[1], ids[0], ids[2]])
    }

    func test_moveVisibleItem_refusesHeaderSource() {
        // Build a playlist group with 2 children (copy pattern from RowStoreGroupTests).
        // Attempt moveVisibleItem from the header row index → false; order unchanged.
    }

    func test_newJob_appendsToEndOfManualOrder() {
        var config = ColumnConfig.default
        config.sortColumn = nil
        let store = RowStore(columnConfig: config)
        store.apply(.snapshot(queueSnapshot([snap(1), snap(2)])))
        let ids = store.rows.map(\.id)
        store.setManualOrder([ids[1], ids[0]])
        store.apply(.snapshot(queueSnapshot([snap(1), snap(2), snap(3)])))
        let id3 = store.rows.first { $0.snapshot.url.hasSuffix("/3") }!.id
        XCTAssertEqual(store.manualOrder?.last, id3)
        XCTAssertEqual(store.visibleRows.last?.id, id3)
    }
}
```

Fill `test_moveVisibleItem_refusesHeaderSource` using the existing group fixture style in `RowStoreGroupTests.swift` (playlistGroupID + `applyGroupSnapshots` / registry). Assert `moveVisibleItem(from: headerIndex, to: childIndex) == false`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild … test -only-testing:AppUnitTests/RowStoreManualOrderTests`  
Expected: FAIL (missing API / compile).

- [ ] **Step 3: Implement `manualOrder` + move**

In `RowStore.swift`:

```swift
private(set) var manualOrder: [UUID]?

func clearManualOrder() {
    guard manualOrder != nil else { return }
    manualOrder = nil
    recomputeVisible()
}

func setManualOrder(_ ids: [UUID]) {
    manualOrder = ids
    recomputeVisible()
}

func setColumnConfig(_ config: ColumnConfig) {
    columnConfig = config
    if config.sortColumn != nil {
        manualOrder = nil
    }
    recomputeVisible()
}
```

After snapshot apply rebuilds `rows` / `modelsByID`, call:

```swift
func reconcileManualOrderWithRows() {
    guard var order = manualOrder else { return }
    let live = Set(rows.map(\.id))
    order.removeAll { !live.contains($0) }
    let known = Set(order)
    for id in rows.map(\.id) where !known.contains(id) {
        order.append(id)
    }
    manualOrder = order.isEmpty ? nil : order
}
```

`moveVisibleItem(from:to:)`:

1. Guard both indices in `visibleItems`.
2. Guard source is `.child`; destination may be `.child` or `.header` (header = insert before that group block for ungrouped source only).
3. If source child has `playlistGroupID`, destination must be a child with the **same** group id (header destination inside same group allowed = move before first visible child). Else refuse.
4. If source is ungrouped, destination must be ungrouped child **or** any header (place the single before that group in block order) **or** end.
5. Build full base order = `manualOrder ?? rows.map(\.id)`.
6. Reorder the relevant subsequence; `setManualOrder`.
7. Return `true` on success.

In `RowStore+Groups.swift`, change `sorted(_ blocks:)`:

```swift
private func sorted(_ blocks: [VisibleBlock]) -> [VisibleBlock] {
    if let column = activeSortColumn {
        return blocks.sorted { compare($0, $1, column: column) }
    }
    if let order = manualOrder {
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return blocks.sorted {
            blockManualRank($0, rank: rank) < blockManualRank($1, rank: rank)
        }
    }
    return blocks.sorted { originalIndex($0) < originalIndex($1) }
}

private func blockManualRank(_ block: VisibleBlock, rank: [UUID: Int]) -> Int {
    switch block {
    case let .single(row, _):
        return rank[row.id] ?? Int.max
    case let .group(groupBlock):
        return groupBlock.allChildren.map { rank[$0.id] ?? Int.max }.min() ?? Int.max
    }
}
```

When emitting group `visibleChildren`, if `manualOrder != nil` and sort is nil, sort children by rank (keep `playlistIndexSort` only when manual order is nil).

Also update `sorted(_ input: [RowModel])` in `RowStore.swift` so `visibleRows` matches:

```swift
private func sorted(_ input: [RowModel]) -> [RowModel] {
    if let column = columnConfig.sortColumn {
        // existing sort
    }
    if let order = manualOrder {
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return input.sorted { (rank[$0.id] ?? Int.max) < (rank[$1.id] ?? Int.max) }
    }
    return input
}
```

- [ ] **Step 4: Run `RowStoreManualOrderTests` + existing `RowStoreTests` / `RowStoreGroupTests`**

Expected: PASS.

- [ ] **Step 5: Lint**

---

### Task 2: Sort-overwrite confirm + AppModel reorder handler

**Files:**
- Modify: `Sources/App/AppModelDialogs.swift`
- Modify: `Sources/App/AppModelRowActions.swift` (or create `Sources/App/AppModelRowReorder.swift` if preferred for file size)
- Create: `Tests/AppUnitTests/AppModelRowReorderTests.swift`
- Modify: `Tests/AppUnitTests/Support/AppFakes.swift` only if confirmer wiring needs a hook (prefer existing `FakeConfirmer` / model helpers)

**Interfaces:**
- Consumes: `AppModel.confirm(_:)`, `columnConfig`, `rowStore.moveVisibleItem`, `ConfirmationRequest`
- Produces:
  - `AppModelDialogs.sortOverwriteConfirmation() -> ConfirmationRequest`
  - `AppModel.handleRowReorder(from:to:) async` — Boolean success not required for UI

- [ ] **Step 1: Write failing tests**

```swift
@MainActor
final class AppModelRowReorderTests: XCTestCase {
    func test_handleRowReorder_whenSorted_cancel_leavesSortAndOrder() async {
        // Build AppModel with FakeConfirmer returning false.
        // Ensure columnConfig.sortColumn != nil (default .addedAt is fine).
        // Seed rowStore with 3 jobs via snapshot event / helper.
        // Record visible order before.
        // await model.handleRowReorder(from: 0, to: 2)
        // XCTAssertEqual(model.columnConfig.sortColumn, .addedAt) // or whatever was set
        // XCTAssertNil(model.rowStore.manualOrder)
        // XCTAssertEqual(visible order, before)
    }

    func test_handleRowReorder_whenSorted_proceed_clearsSortAndMoves() async {
        // FakeConfirmer returns true.
        // await handleRowReorder(from: 0, to: 2)
        // XCTAssertNil(model.columnConfig.sortColumn)
        // XCTAssertNotNil(model.rowStore.manualOrder)
        // visible child order reflects move
    }

    func test_handleRowReorder_whenSortNil_movesWithoutConfirm() async {
        // Set sortColumn nil first.
        // Confirmer should receive zero requests.
        // Move succeeds.
    }
}
```

Wire confirmer the same way existing `ConfirmationTests` / AppModel helpers do (`AppModelTestHelpers`).

- [ ] **Step 2: Run to verify fail**

- [ ] **Step 3: Implement dialog + handler**

```swift
// AppModelDialogs.swift
static func sortOverwriteConfirmation() -> ConfirmationRequest {
    ConfirmationRequest(
        title: "Clear sorting?",
        message: "Moving rows turns off column sorting for this session.",
        confirmTitle: "Move Rows",
        cancelTitle: "Cancel",
        isDestructive: false,
        suppressionKey: nil
    )
}
```

```swift
// AppModel
func handleRowReorder(from fromIndex: Int, to toIndex: Int) async {
    if columnConfig.sortColumn != nil {
        let ok = await confirm(AppModelDialogs.sortOverwriteConfirmation())
        guard ok else { return }
        var config = columnConfig
        config.sortColumn = nil
        config.sortDirection = nil
        columnConfig = config // didSet → setColumnConfig; clears manualOrder — OK, we set order next
    }
    _ = rowStore.moveVisibleItem(from: fromIndex, to: toIndex)
}
```

**Important:** `setColumnConfig` with `sortColumn == nil` must **not** clear an existing manual order. Only clear when `sortColumn != nil`. After clearing sort in the handler, `manualOrder` is nil; `moveVisibleItem` then establishes it.

When user activates sort via header `cycleSort`, `columnConfig` didSet → `setColumnConfig` with non-nil sort → clears `manualOrder` (Task 1).

- [ ] **Step 4: Run `AppModelRowReorderTests` + `ConfirmationTests`**

Expected: PASS.

- [ ] **Step 5: Lint**

---

### Task 3: AppKit row drag on Downloads grid

**Files:**
- Modify: `Sources/App/Table/DownloadsGridController.swift`
- Create: `Sources/App/Table/DownloadsGridController+RowDrag.swift` (preferred if controller is already large)
- Modify: `Sources/App/Table/DownloadsGridCells.swift` (`GridTableView` only if needed for drag start)

**Interfaces:**
- Consumes: `items: [VisibleItem]`
- Produces: `var onRowReorder: ((Int, Int) -> Void)?` called with visible-item indices after a successful drop validation; controller does **not** mutate `RowStore` itself

- [ ] **Step 1: Enable dragging**

In `configureTableView()`:

```swift
tableView.draggingDestinationFeedbackStyle = .gap
tableView.registerForDraggedTypes([.init(Self.rowDragType)])
// rowDragType = "app.mediagrabber.downloads-row-id" (or UTI-style reverse DNS already used elsewhere)
```

- [ ] **Step 2: Implement data source drag methods**

On `DownloadsGridController`:

```swift
static let rowDragType = "app.mediagrabber.downloads.row"

func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
    guard items.indices.contains(row), case .child = items[row] else { return nil }
    let item = NSPasteboardItem()
    item.setString(String(row), forType: .init(Self.rowDragType))
    return item
}

func tableView(
    _ tableView: NSTableView,
    validateDrop info: any NSDraggingInfo,
    proposedRow row: Int,
    proposedDropOperation dropOperation: NSTableView.DropOperation
) -> NSDragOperation {
    guard dropOperation == .above else { return [] }
    guard
        let from = draggedFromRow(info),
        items.indices.contains(from),
        case .child = items[from]
    else { return [] }
    // Refuse dropping "into" a header as .on — only .above
    // Allow row == items.count (end)
    return .move
}

func tableView(
    _ tableView: NSTableView,
    acceptDrop info: any NSDraggingInfo,
    row: Int,
    dropOperation: NSTableView.DropOperation
) -> Bool {
    guard dropOperation == .above, let from = draggedFromRow(info) else { return false }
    var to = row
    // NSTableView: when dragging down, proposed row is the index after removal semantics —
    // normalize so onRowReorder gets indices suitable for moveVisibleItem (document the
    // normalization: if to > from { to -= 1 } before calling, matching NSTableView convention,
    // OR have moveVisibleItem accept "destination index in pre-move array with .above meaning").
    onRowReorder?(from, to)
    return true
}
```

Lock the index convention in `moveVisibleItem` docs via tests: dragging row 0 above row 2 means final order `[1,0,2]` for three ungrouped children. Align `acceptDrop` normalization with that test — adjust either the controller or `moveVisibleItem` so one unit test pins both.

`draggedFromRow` reads the pasteboard string as `Int`.

- [ ] **Step 3: Manual smoke checklist (document in step; run after Task 4 wires it)**

Cannot unit-test NSTableView drag easily — Task 4 wires; smoke then.

- [ ] **Step 4: Lint**

---

### Task 4: Wire drag → AppModel + clear sort on header cycle

**Files:**
- Modify: `Sources/App/Table/DownloadsGridView.swift`
- Modify: `Sources/App/Table/DownloadsTable.swift`
- Modify: `Sources/App/Home/HomeView.swift` (tableLayout `DownloadsTable` call site)

**Interfaces:**
- Consumes: `onRowReorder` from controller; `AppModel.handleRowReorder`
- Produces: end-to-end drag path

- [ ] **Step 1: Thread callback**

`DownloadsGridView`:

```swift
let onRowReorder: (Int, Int) -> Void
// in wire:
controller.onRowReorder = onRowReorder
```

`DownloadsTable`: add `onRowReorder` parameter; pass into `DownloadsGridView`.

`HomeView.tableLayout`:

```swift
onRowReorder: { from, to in
    Task { await appModel.handleRowReorder(from: from, to: to) }
}
```

- [ ] **Step 2: Verify header sort still clears manual order**

Existing `onCycleSort` already assigns `columnConfig` → `setColumnConfig`. Covered by Task 1 unit test; no extra code unless `ColumnsMenu` bypasses didSet (it should not).

- [ ] **Step 3: Manual UI smoke**

1. Launch app with empty queue; grab 3 single URLs (or seed via debug).
2. With default sort, drag a row → confirm dialog appears; Cancel → order unchanged.
3. Drag again → Proceed → sort indicator clears; order updates.
4. Cycle a column sort on → rows resort; further drag asks again.
5. With a playlist group expanded, drag a child within the group → reorders siblings; drag onto another group’s child → no change; drag group header → does not start.
6. Quit and relaunch → manual order gone (session only).

- [ ] **Step 4: Run AppUnitTests suites touched + lint**

---

### Task 5: Visual gate — body face + first-run variants

**Files:**
- None until picks are recorded. After picks, append a short “Picks” subsection to this plan (or a one-line note at the top of Tasks 6–7) with the chosen names — **do not leave TBD past ship**.

**Candidates to present (lock these; do not silently substitute):**

**Aurora body face**

| ID | Face | Notes |
|---|---|---|
| B0 | Inter | Control (current) |
| B1 | IBM Plex Sans | OFL; clear UI body |
| B2 | Source Sans 3 | OFL; Adobe; neutral |

Present each as body text in a small SwiftUI preview sheet or static PNG/mock beside Sora display + JetBrains mono samples (display/mono stay). Prefer a temporary debug-only preview view **or** side-by-side screenshots in chat — no need to ship the picker.

**First-run Home**

| ID | Variant |
|---|---|
| H0 | Current — hero + paste + three step cards |
| H1 | Hero + paste dominant; steps as a single horizontal numbered strip (no cards) |
| H2 | Centered stack: larger display line, paste, quiet vertical numbered list (no card chrome) |

Behavioral gates unchanged for all variants: no table until first Grab / non-empty queue; step UI first-run-only; emptied table does not resurrect steps; runway still gated on resolve.

- [ ] **Step 1: Present B0–B2 and H0–H2 to the user; stop**

- [ ] **Step 2: Record picks in this plan file** (e.g. `Body face pick: B2 Source Sans 3` / `First-run pick: H1`) before starting Tasks 6–7

---

### Task 6: Wire chosen Aurora body face

**Files:**
- Add: `Resources/Fonts/<Family>/<files>` + OFL text
- Remove: `Resources/Fonts/Inter/**` if nothing else references Inter after the swap
- Modify: `Sources/App/Theme/Theme.swift` (`bodyFont` family string)
- Modify: `apps/media-grabber/CLAUDE.md` font bullet; `apps/media-grabber/docs/design-system.md` if it names Inter
- Modify: `Tests/AppUnitTests/ThemeTests.swift`
- `Project.swift` already globs `Resources/Fonts/**` — regenerate if needed

**Interfaces:**
- Consumes: Task 5 body pick (PostScript / family name that `NSFont(name:size:)` resolves after bundling)
- Produces: Aurora `bodyFont` uses chosen family; Tape Deck theme path unchanged; Sora + JetBrains still resolve

- [ ] **Step 1: Vendor font + failing resolve test**

```swift
@MainActor
func test_auroraBodyFont_chosenFamilyResolves() {
    // After bundling, NSFont(name: "<ChosenFamily>", size: 13) != nil in app test host.
    // If XCTest host does not load app fonts, assert Theme.bodyFont closure still returns
    // Font.custom path by checking the family string constant introduced in Theme.swift
    // (e.g. Theme.auroraBodyFamily) equals the picked name.
    XCTAssertEqual(Theme.auroraBodyFamily, "<PICKED>")
}
```

Introduce `static let auroraBodyFamily = "<PICKED>"` used by `bodyFont`.

- [ ] **Step 2: Implement**

```swift
var bodyFont: (CGFloat, Font.Weight) -> Font {
    { size, weight in Self.resolvedFont(Self.auroraBodyFamily, size: size, weight: weight) }
}
```

Delete Inter resources only after confirming no remaining references (`rg Inter` under `apps/media-grabber` excluding history/docs archives).

- [ ] **Step 3: `tuist generate` if resources changed; run ThemeTests; lint**

- [ ] **Step 4: Manual smoke — launch app; body text looks like the pick; display/mono unchanged**

---

### Task 7: Implement chosen first-run Home

**Files:**
- Modify: `Sources/App/Home/HomeView.swift` (`firstRunLayout`, `hero`, `stepCards` / replacement)
- Modify tests only if existing Home/empty-state tests assert copy or structure (`AppModelTests` showsTable gates must stay green)

**Interfaces:**
- Consumes: Task 5 first-run pick; existing `appModel.showsTable` / `hasGrabbedOnce` / paste / grab flow
- Produces: first-run chrome matching the pick; table layout path untouched

- [ ] **Step 1: Failing / reinforcing behavior tests (if not already present)**

Ensure these still exist (add only if missing):

```swift
func test_showsTable_isFalseUntilFirstGrabOrNonEmptyQueue()
func test_showsTable_isTrueWhenQueueNonEmptyEvenWithoutHasGrabbedOnce()
```

Optional: if copy strings become constants, snapshot-assert the hero title string for the pick.

- [ ] **Step 2: Implement the picked variant in `firstRunLayout` only**

Do not change probe, runway arming, playlist picker, or `tableLayout` empty-body message behavior.

- [ ] **Step 3: Manual smoke**

1. Reset `mg.hasGrabbedOnce` (debug flag / defaults) → first-run shows picked layout.
2. Grab once → table chrome; clear all rows → empty table line, **no** step cards.
3. Paste without Grab → runway still hidden until resolve (existing gate).

- [ ] **Step 4: Lint + AppUnitTests**

---

### Task 8: Docs, archive, full suite

**Files:**
- Modify: `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1 Phase 15 → `*(shipped)*`
- Modify: `apps/media-grabber/ticket-backlog.md` Phase 15
- Modify: `apps/media-grabber/CLAUDE.md` Next → Phase 16
- Modify: `apps/media-grabber/docs/state-flow.md` §4 — mark row-drag + body/first-run rows shipped / remove from parked
- Modify: `docs/superpowers/specs/2026-10-04-media-grabber-phase-15-table-home-finish-design.md` status → shipped
- Move: design + this plan → `docs/superpowers/{specs,plans}/archived/` via `mv` (no git)

- [ ] **Step 1: Full suite**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`  
Expected: PASS (GrabberKitTests + AppUnitTests).

- [ ] **Step 2: Lint**

- [ ] **Step 3: Update tracking docs + archive**

Same style as Phase 14 ship. Sibling Phase 16/17 stubs unchanged in ownership.

---

## Self-Review Notes

- **Spec coverage:** view-order drag → Tasks 1–4; sort confirm → Task 2; session-only / no engine reorder → Global Constraints + Task 1; body face → Tasks 5–6; first-run → Tasks 5 + 7; banner closed → out of plan; docs → Task 8.
- **Placeholder scan:** Task 5 requires recorded picks before 6–7; font family string is `"<PICKED>"` only inside Task 6 after the gate.
- **Type consistency:** `manualOrder`, `moveVisibleItem(from:to:)`, `handleRowReorder(from:to:)`, `onRowReorder`, `sortOverwriteConfirmation()`, `Theme.auroraBodyFamily` are stable across tasks.
- **Review Focus:** default-sort confirm → Task 2; cancel → Task 2; header/cross-group refuse → Task 1; new job append → Task 1; sort clears manual → Task 1.
