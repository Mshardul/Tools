import AppKit
import GrabberKit
import SwiftUI

enum ColumnMetrics {
    private static let widths: [ColumnID: CGFloat] = [
        .title: 200, .status: 150, .remark: 160, .progress: 100,
        .speed: 72, .eta: 72, .type: 72, .quality: 72,
        .size: 80, .duration: 80, .site: 96,
        .addedAt: 120, .finishedAt: 120, .destination: 120,
        .attempt: 64, .clientUsed: 64, .actions: 280
    ]

    private static let titles: [ColumnID: String] = [
        .title: "Title", .status: "Status", .remark: "Remark", .progress: "Progress",
        .speed: "Speed", .eta: "ETA", .type: "Type", .quality: "Quality",
        .size: "Size", .site: "Site", .addedAt: "Added at",
        .finishedAt: "Finished at", .duration: "Duration",
        .destination: "Destination", .attempt: "Attempt",
        .clientUsed: "Client used", .actions: "Actions"
    ]

    private static let filterable: Set<ColumnID> = [
        .title, .status, .type, .quality, .site, .destination, .clientUsed
    ]

    static func width(for column: ColumnID) -> CGFloat {
        widths[column] ?? 80
    }

    static func resolvedWidth(for column: ColumnID, config: ColumnConfig) -> CGFloat {
        if let override = config.columnWidths[column] {
            return clamped(CGFloat(override), for: column)
        }
        return width(for: column)
    }

    static func minWidth(for column: ColumnID) -> CGFloat {
        switch column {
        case .title: 120
        case .speed, .eta, .attempt, .type, .quality: 48
        case .actions: width(for: .actions)
        default: 80
        }
    }

    static func clamped(_ width: CGFloat, for column: ColumnID) -> CGFloat {
        max(minWidth(for: column), width)
    }

    static func isResizable(_ column: ColumnID) -> Bool {
        column != .actions
    }

    // One-shot measure for double-click divider autofit; padding covers cell insets.
    static func autoFitWidth(sampleStrings: [String], min minWidth: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let widest = sampleStrings
            .map { ($0 as NSString).size(withAttributes: attributes).width }
            .max() ?? 0
        return max(minWidth, ceil(widest) + 16)
    }

    static func totalWidth(for columns: [ColumnID]) -> CGFloat {
        columns.reduce(0) { $0 + width(for: $1) + Spacing.s4 }
    }

    static func totalWidth(for columns: [ColumnID], config: ColumnConfig) -> CGFloat {
        columns.reduce(0) { $0 + resolvedWidth(for: $1, config: config) + Spacing.s4 }
    }

    static func title(for column: ColumnID) -> String {
        titles[column] ?? column.rawValue
    }

    static func supportsFilter(_ column: ColumnID) -> Bool {
        filterable.contains(column)
    }

    static func supportsSort(_ column: ColumnID) -> Bool {
        column != .actions
    }
}

enum RowStatusStyle {
    static func dotColor(for state: JobState, palette: PaletteTokens) -> Color {
        switch state {
        case .queued: palette.accent2
        case .probing, .running: palette.accent
        case .paused, .waitingForNetwork: palette.dim
        case .cooldown: palette.warn
        case .failed: palette.danger
        case .completed, .cancelled: palette.dim
        }
    }

    static func textColor(for state: JobState, palette: PaletteTokens) -> Color {
        switch state {
        case .failed: palette.danger
        case .completed, .cancelled: palette.dim
        default: palette.text
        }
    }
}
