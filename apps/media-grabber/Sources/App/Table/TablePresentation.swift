import Foundation
import GrabberKit

@MainActor
enum TablePresentation {
    static let emDash = "—"
    static let emptyQueueMessage = "No downloads — paste a link above."
    static let filteredEmptyMessage = "No downloads match this filter."

    static func cellText(for row: RowModel, column: ColumnID) -> String {
        switch column {
        case .status:
            statusDisplay(for: row)
        case .progress:
            progressLabel(for: row)
        case .speed:
            row.speedText.isEmpty ? "" : row.speedText
        case .eta:
            row.etaText.isEmpty ? "" : row.etaText
        case .actions:
            ""
        default:
            dataColumnText(for: row, column: column)
        }
    }

    private static func dataColumnText(for row: RowModel, column: ColumnID) -> String {
        switch column {
        case .title:
            row.snapshot.title ?? emDash
        case .type:
            row.typeLabel
        case .quality:
            row.qualityLabel
        case .size:
            row.formattedSize
        case .site:
            row.siteLabel
        case .addedAt:
            dateString(row.snapshot.addedAt)
        case .finishedAt:
            row.snapshot.finishedAt.map(dateString) ?? emDash
        case .duration:
            row.formattedDuration
        case .destination, .attempt, .clientUsed:
            metadataColumnText(for: row, column: column)
        default:
            emDash
        }
    }

    private static func metadataColumnText(for row: RowModel, column: ColumnID) -> String {
        switch column {
        case .destination:
            row.snapshot.destFolder.lastPathComponent
        case .attempt:
            row.snapshot.attempt > 0 ? String(row.snapshot.attempt) : emDash
        case .clientUsed:
            row.snapshot.playerClientUsed ?? emDash
        default:
            emDash
        }
    }

    static func statusDisplay(for row: RowModel) -> String {
        if row.snapshot.state == .queued, let badge = row.queueBadge {
            return "queued · \(badge)"
        }
        switch row.snapshot.state {
        case .queued: return "queued"
        case .probing: return "probing"
        case .running: return "downloading"
        case .paused: return "paused"
        case .waitingForNetwork: return "waiting for network"
        case .cooldown: return "cooling down"
        case .completed: return "saved"
        case .cancelled: return "cancelled"
        case .failed:
            return row.statusText.replacingOccurrences(of: "Failed — ", with: "")
        }
    }

    static func progressLabel(for row: RowModel) -> String {
        guard let fraction = row.snapshot.progress?.fraction else { return "" }
        return "\(Int(fraction * 100))%"
    }

    static func isActionEnabled(_ action: RowAction, available: Set<RowAction>) -> Bool {
        available.contains(action)
    }

    static func emptyBodyMessage(
        rowCount: Int,
        visibleCount: Int,
        activeChip: FilterChip,
        columnFilters: [ColumnID: [String]]
    ) -> String? {
        guard visibleCount == 0 else { return nil }
        if rowCount == 0 {
            return emptyQueueMessage
        }
        if hasActiveFilters(activeChip: activeChip, columnFilters: columnFilters) {
            return filteredEmptyMessage
        }
        return filteredEmptyMessage
    }

    static func hasActiveFilters(
        activeChip: FilterChip,
        columnFilters: [ColumnID: [String]]
    ) -> Bool {
        activeChip != .all || columnFilters.values.contains { !$0.isEmpty }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
