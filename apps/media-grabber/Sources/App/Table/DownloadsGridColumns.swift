import AppKit
import GrabberKit

enum DownloadsGridColumns {
    static let selectionIdentifier = NSUserInterfaceItemIdentifier("sel")
    static let selectionWidth: CGFloat = 32

    static func identifier(for column: ColumnID) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(column.rawValue)
    }

    static func columnID(from identifier: NSUserInterfaceItemIdentifier) -> ColumnID? {
        guard identifier != selectionIdentifier else { return nil }
        return ColumnID(rawValue: identifier.rawValue)
    }

    static func resolvedWidth(
        for identifier: NSUserInterfaceItemIdentifier,
        config: ColumnConfig
    ) -> CGFloat {
        if identifier == selectionIdentifier {
            return selectionWidth
        }
        guard let column = columnID(from: identifier) else { return 80 }
        return ColumnMetrics.resolvedWidth(for: column, config: config)
    }
}
