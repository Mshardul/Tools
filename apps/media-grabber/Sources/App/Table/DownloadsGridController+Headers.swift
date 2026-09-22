import AppKit
import Foundation
import GrabberKit

@MainActor
extension DownloadsGridController {
    func makeSelectionColumn() -> NSTableColumn {
        let column = NSTableColumn(identifier: DownloadsGridColumns.selectionIdentifier)
        let header = GridHeaderCell()
        header.stringValue = selectionHeaderTitle()
        header.tokens = tokens
        column.headerCell = header
        column.width = DownloadsGridColumns.selectionWidth
        column.minWidth = DownloadsGridColumns.selectionWidth
        column.maxWidth = DownloadsGridColumns.selectionWidth
        column.isEditable = false
        column.resizingMask = []
        return column
    }

    func makeDataColumn(for columnID: ColumnID) -> NSTableColumn {
        let column = NSTableColumn(identifier: DownloadsGridColumns.identifier(for: columnID))
        column.headerCell = makeHeaderCell(for: columnID)
        let width = ColumnMetrics.resolvedWidth(for: columnID, config: columnConfig)
        column.width = width
        column.minWidth = ColumnMetrics.minWidth(for: columnID)
        column.isEditable = false
        if ColumnMetrics.isResizable(columnID) {
            column.resizingMask = .userResizingMask
        } else {
            column.resizingMask = []
            column.maxWidth = width
        }
        return column
    }

    func makeHeaderCell(for columnID: ColumnID) -> GridHeaderCell {
        let header = GridHeaderCell()
        header.stringValue = ColumnMetrics.title(for: columnID)
        header.tokens = tokens
        header.showsSort = ColumnMetrics.supportsSort(columnID)
        header.showsFilter = ColumnMetrics.supportsFilter(columnID)
        applySortFilterState(to: header, columnID: columnID)
        return header
    }

    func refreshHeaderCells() {
        for column in tableView.tableColumns {
            if column.identifier == DownloadsGridColumns.selectionIdentifier {
                if let header = column.headerCell as? GridHeaderCell {
                    header.tokens = tokens
                    header.stringValue = selectionHeaderTitle()
                }
                continue
            }
            guard let columnID = DownloadsGridColumns.columnID(from: column.identifier) else {
                continue
            }
            if let header = column.headerCell as? GridHeaderCell {
                header.tokens = tokens
                applySortFilterState(to: header, columnID: columnID)
            } else {
                column.headerCell = makeHeaderCell(for: columnID)
            }
        }
        tableView.headerView?.needsDisplay = true
    }

    func applySortFilterState(to header: GridHeaderCell, columnID: ColumnID) {
        header.sortActive = columnConfig.sortColumn == columnID
        if columnConfig.sortColumn == columnID {
            switch columnConfig.sortDirection {
            case .ascending: header.sortKind = .sortAsc
            case .descending: header.sortKind = .sortDesc
            case nil: header.sortKind = .sortNeutral
            }
        } else {
            header.sortKind = .sortNeutral
        }
        header.filterActive = !(columnConfig.columnFilters[columnID]?.isEmpty ?? true)
    }

    func refreshSelectionHeaderTitle() {
        guard let column = tableView.tableColumn(
            withIdentifier: DownloadsGridColumns.selectionIdentifier
        ) else { return }
        if let header = column.headerCell as? GridHeaderCell {
            header.stringValue = selectionHeaderTitle()
            header.tokens = tokens
        } else {
            column.title = selectionHeaderTitle()
        }
    }

    func handleHeaderAffordance(columnIndex: Int, hit: GridHeaderHit, event: NSEvent) {
        guard columnIndex >= 0, columnIndex < tableView.tableColumns.count else { return }
        let tableColumn = tableView.tableColumns[columnIndex]
        guard let columnID = DownloadsGridColumns.columnID(from: tableColumn.identifier) else {
            return
        }
        switch hit {
        case .sort:
            onCycleSort?(columnID)
        case .filter:
            presentFilterMenu(for: columnID, event: event)
        case .title:
            break
        }
    }

    func presentFilterMenu(for column: ColumnID, event: NSEvent) {
        let values = filterValueProvider?(column) ?? []
        let menu = NSMenu()
        if values.isEmpty {
            let item = NSMenuItem(title: "(none)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for value in values {
                let selected = columnConfig.columnFilters[column]?.contains(value) == true
                let item = NSMenuItem(
                    title: value,
                    action: #selector(filterMenuItemChosen(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.state = selected ? .on : .off
                item.representedObject = FilterChoice(column: column, value: value)
                menu.addItem(item)
            }
        }
        NSMenu.popUpContextMenu(menu, with: event, for: tableView.headerView ?? tableView)
    }

    @objc
    func filterMenuItemChosen(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? FilterChoice else { return }
        onToggleFilter?(choice.column, choice.value)
    }
}

final class FilterChoice: NSObject {
    let column: ColumnID
    let value: String

    init(column: ColumnID, value: String) {
        self.column = column
        self.value = value
    }
}
