import AppKit
import Foundation
import GrabberKit

@MainActor
extension DownloadsGridController {
    func tableViewColumnDidResize(_ notification: Notification) {
        guard !applyingColumnWidths else { return }
        guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
        guard let columnID = DownloadsGridColumns.columnID(from: column.identifier) else { return }
        guard ColumnMetrics.isResizable(columnID) else { return }
        let clamped = ColumnMetrics.clamped(column.width, for: columnID)
        if abs(clamped - column.width) > 0.5 {
            applyingColumnWidths = true
            column.width = clamped
            applyingColumnWidths = false
        }
        onColumnWidthChange?(columnID, clamped)
    }

    @objc
    func handleColumnDidMoveNotification(_ notification: Notification) {
        guard !applyingColumnOrder else { return }
        guard let oldIndex = columnMoveIndex(notification, key: "NSOldColumn"),
              let newIndex = columnMoveIndex(notification, key: "NSNewColumn"),
              oldIndex != newIndex
        else { return }

        guard isValidColumnLayout() else {
            undoColumnMove(from: newIndex, to: oldIndex)
            return
        }

        guard let source = movedColumnID(at: newIndex), source != .actions else {
            undoColumnMove(from: newIndex, to: oldIndex)
            return
        }

        guard let destination = reorderDestinationID(after: newIndex) else {
            undoColumnMove(from: newIndex, to: oldIndex)
            return
        }

        onColumnReorder?(source, destination)
    }

    func autoFitColumn(at columnIndex: Int) {
        guard columnIndex >= 0, columnIndex < tableView.tableColumns.count else { return }
        let column = tableView.tableColumns[columnIndex]
        guard let columnID = DownloadsGridColumns.columnID(from: column.identifier) else { return }
        guard ColumnMetrics.isResizable(columnID) else { return }

        let samples = items.compactMap { item -> String? in
            guard case .child = item else { return nil }
            return displayText(for: item, column: columnID)
        }
        let fitted = ColumnMetrics.autoFitWidth(
            sampleStrings: samples,
            min: ColumnMetrics.minWidth(for: columnID)
        )
        let clamped = ColumnMetrics.clamped(fitted, for: columnID)
        applyingColumnWidths = true
        column.width = clamped
        applyingColumnWidths = false
        onColumnWidthChange?(columnID, clamped)
    }

    private func columnMoveIndex(_ notification: Notification, key: String) -> Int? {
        (notification.userInfo?[key] as? NSNumber)?.intValue
    }

    private func movedColumnID(at index: Int) -> ColumnID? {
        guard index >= 0, index < tableView.tableColumns.count else { return nil }
        return DownloadsGridColumns.columnID(from: tableView.tableColumns[index].identifier)
    }

    private func reorderDestinationID(after newIndex: Int) -> ColumnID? {
        let nextIndex = newIndex + 1
        guard nextIndex < tableView.tableColumns.count else { return nil }
        return DownloadsGridColumns.columnID(from: tableView.tableColumns[nextIndex].identifier)
    }

    private func isValidColumnLayout() -> Bool {
        let columns = tableView.tableColumns
        guard let first = columns.first,
              first.identifier == DownloadsGridColumns.selectionIdentifier
        else { return false }
        guard let last = columns.last,
              DownloadsGridColumns.columnID(from: last.identifier) == .actions
        else { return false }
        let selectionMoved = columns.dropFirst().contains {
            $0.identifier == DownloadsGridColumns.selectionIdentifier
        }
        return !selectionMoved
    }

    private func undoColumnMove(from newIndex: Int, to oldIndex: Int) {
        applyingColumnOrder = true
        tableView.moveColumn(newIndex, toColumn: oldIndex)
        applyingColumnOrder = false
    }
}
