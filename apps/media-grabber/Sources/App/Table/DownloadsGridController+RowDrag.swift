import AppKit
import Foundation

extension DownloadsGridController {
    static let rowDragType = NSPasteboard.PasteboardType("app.mediagrabber.downloads.row")

    func configureRowDragging() {
        tableView.draggingDestinationFeedbackStyle = .gap
        tableView.registerForDraggedTypes([Self.rowDragType])
    }

    func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard items.indices.contains(row), case .child = items[row] else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.rowDragType)
        return item
    }

    func tableView(
        _: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard dropOperation == .above else { return [] }
        guard let from = draggedFromRow(info), items.indices.contains(from), case .child = items[from]
        else { return [] }
        guard row >= 0, row <= items.count else { return [] }
        return .move
    }

    func tableView(
        _: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard dropOperation == .above, let from = draggedFromRow(info) else { return false }
        // `row` is the pre-move “insert above” index (may equal items.count for end).
        guard from != row else { return false }
        onRowReorder?(from, row)
        return true
    }

    private func draggedFromRow(_ info: any NSDraggingInfo) -> Int? {
        let value = info.draggingPasteboard.string(forType: Self.rowDragType)
        guard let value, let from = Int(value) else { return nil }
        return from
    }
}
