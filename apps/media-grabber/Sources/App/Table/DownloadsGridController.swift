import AppKit
import Foundation
import GrabberKit

struct DownloadsGridSyncState {
    var items: [VisibleItem]
    var visibleColumns: [ColumnID]
    var columnConfig: ColumnConfig
    var selectedJobIDs: Set<UUID>
    var selectionAnchorID: UUID?
    var visibleChildOrder: [UUID]
    var scrollToRowID: UUID?
    var tokens: DownloadsGridTokens
    var filterValueProvider: ((ColumnID) -> [String])?
}

@MainActor
final class DownloadsGridController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let scrollView = NSScrollView()
    let tableView = GridTableView()

    var items: [VisibleItem] = []
    var visibleColumns: [ColumnID] = []
    var columnConfig = ColumnConfig.default
    var selectedJobIDs: Set<UUID> = []
    var selectionAnchorID: UUID?
    var visibleChildOrder: [UUID] = []
    var applyingSelection = false
    var applyingColumnWidths = false
    var applyingColumnOrder = false
    var tokens = DownloadsGridTokens.aurora
    var filterValueProvider: ((ColumnID) -> [String])?

    var onAction: ((UUID, RowAction) -> Void)?
    var onPlaylistGroupAction: ((UUID, PlaylistGroupAction) -> Void)?
    var onTogglePlaylistGroupCollapsed: ((UUID, Bool) -> Void)?
    var onClearScrollTarget: (() -> Void)?
    var onSetSelectedJobIDs: ((Set<UUID>, UUID?) -> Void)?
    var onSelectAllVisible: (() -> Void)?
    var onClearSelection: (() -> Void)?
    var onColumnWidthChange: ((ColumnID, CGFloat) -> Void)?
    var onColumnReorder: ((ColumnID, ColumnID) -> Void)?
    var onCycleSort: ((ColumnID) -> Void)?
    var onToggleFilter: ((ColumnID, String) -> Void)?

    var rootView: NSView {
        scrollView
    }

    private var allVisibleChildrenSelected: Bool {
        !visibleChildOrder.isEmpty && Set(visibleChildOrder) == selectedJobIDs
    }

    override init() {
        super.init()
        configureScrollView()
        configureTableView()
    }

    func sync(_ state: DownloadsGridSyncState) {
        let columnsChanged = visibleColumns != state.visibleColumns

        items = state.items
        visibleColumns = state.visibleColumns
        columnConfig = state.columnConfig
        selectedJobIDs = state.selectedJobIDs
        selectionAnchorID = state.selectionAnchorID
        visibleChildOrder = state.visibleChildOrder
        tokens = state.tokens
        filterValueProvider = state.filterValueProvider

        if columnsChanged || tableView.tableColumns.isEmpty {
            rebuildColumns()
        } else {
            applyResolvedWidths()
            refreshSelectionHeaderTitle()
            refreshHeaderCells()
        }
        // RowModel mutates in place; reload each sync so progress/status stay fresh.
        tableView.reloadData()
        applySelectionHighlight()
        if let scrollToRowID = state.scrollToRowID {
            scrollToJob(scrollToRowID)
            onClearScrollTarget?()
        }
    }

    private func configureScrollView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = tableView
    }

    private func configureTableView() {
        let header = DownloadsGridHeaderView(frame: .zero)
        header.onDoubleClickDivider = { [weak self] columnIndex in
            self?.autoFitColumn(at: columnIndex)
        }
        header.onHeaderAffordanceClick = { [weak self] columnIndex, hit, event in
            self?.handleHeaderAffordance(columnIndex: columnIndex, hit: hit, event: event)
        }
        tableView.headerView = header
        tableView.style = .plain
        tableView.rowHeight = 36
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.focusRingType = .none
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
        tableView.onRowClick = { [weak self] row, column, flags in
            self?.handleRowClick(row: row, column: column, flags: flags)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleColumnDidMoveNotification(_:)),
            name: NSTableView.columnDidMoveNotification,
            object: tableView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func rebuildColumns() {
        for column in tableView.tableColumns {
            tableView.removeTableColumn(column)
        }

        tableView.addTableColumn(makeSelectionColumn())
        for columnID in visibleColumns {
            tableView.addTableColumn(makeDataColumn(for: columnID))
        }
    }

    func applyResolvedWidths() {
        applyingColumnWidths = true
        defer { applyingColumnWidths = false }
        for column in tableView.tableColumns {
            let width = DownloadsGridColumns.resolvedWidth(
                for: column.identifier,
                config: columnConfig
            )
            if abs(column.width - width) > 0.5 {
                column.width = width
            }
            if shouldLockMaxWidth(for: column) {
                column.maxWidth = width
            }
        }
    }

    private func shouldLockMaxWidth(for column: NSTableColumn) -> Bool {
        guard let columnID = DownloadsGridColumns.columnID(from: column.identifier) else {
            return false
        }
        return !ColumnMetrics.isResizable(columnID)
    }

    func selectionHeaderTitle() -> String {
        allVisibleChildrenSelected ? "☑" : "☐"
    }

    private func applySelectionHighlight() {
        applyingSelection = true
        defer { applyingSelection = false }

        tableView.deselectAll(nil)
        var indexes = IndexSet()
        for (index, item) in items.enumerated() {
            guard case let .child(row) = item, selectedJobIDs.contains(row.id) else { continue }
            indexes.insert(index)
        }
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
    }

    private func scrollToJob(_ id: UUID) {
        guard let index = rowIndex(ofJob: id) else { return }
        tableView.scrollRowToVisible(index)
    }

    private func rowIndex(ofJob id: UUID) -> Int? {
        items.firstIndex { item in
            if case let .child(row) = item {
                return row.id == id
            }
            return false
        }
    }

    func handleRowClick(row: Int, column: Int, flags: NSEvent.ModifierFlags) {
        guard let id = childJobID(at: row) else { return }

        if isSelectionColumn(column) || flags.contains(.command) {
            let next = RowSelection.toggle(id, in: selectedJobIDs)
            onSetSelectedJobIDs?(next, anchorAfterToggle(id, in: next))
            return
        }

        if flags.contains(.shift) {
            let next = RowSelection.rangeSelecting(
                from: selectionAnchorID,
                to: id,
                visibleChildOrder: visibleChildOrder,
                replacing: selectedJobIDs
            )
            onSetSelectedJobIDs?(next, selectionAnchorID ?? id)
            return
        }

        onSetSelectedJobIDs?([id], id)
    }

    private func childJobID(at row: Int) -> UUID? {
        guard row >= 0, row < items.count else { return nil }
        guard case let .child(model) = items[row] else { return nil }
        return model.id
    }

    private func isSelectionColumn(_ column: Int) -> Bool {
        guard column >= 0, column < tableView.tableColumns.count else { return false }
        return tableView.tableColumns[column].identifier
            == DownloadsGridColumns.selectionIdentifier
    }

    private func anchorAfterToggle(_ id: UUID, in next: Set<UUID>) -> UUID? {
        if next.contains(id) {
            return id
        }
        if let current = selectionAnchorID, next.contains(current) {
            return current
        }
        return next.first
    }

    func isHeaderRow(_ row: Int) -> Bool {
        guard row >= 0, row < items.count else { return false }
        if case .header = items[row] {
            return true
        }
        return false
    }

    func numberOfRows(in _: NSTableView) -> Int {
        items.count
    }

    func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard applyingSelection else { return false }
        guard row >= 0, row < items.count else { return false }
        return !isHeaderRow(row)
    }

    func tableView(_: NSTableView, mouseDownInHeaderOf tableColumn: NSTableColumn) {
        guard tableColumn.identifier == DownloadsGridColumns.selectionIdentifier else { return }
        if allVisibleChildrenSelected || visibleChildOrder.isEmpty {
            onClearSelection?()
        } else {
            onSelectAllVisible?()
        }
    }
}
