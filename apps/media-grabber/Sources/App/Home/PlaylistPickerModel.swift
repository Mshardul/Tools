import Foundation
import GrabberKit

struct PlaylistPickerModel: Equatable {
    var dump: PlaylistDump
    var checked: Set<Int>
    var filter: String
    var warnings: [Int: PlaylistRowWarning]
    var showPlaylistBanner: Bool

    init(
        dump: PlaylistDump,
        existing: [(url: String, completed: Bool)],
        showPlaylistBanner: Bool
    ) {
        self.dump = dump
        warnings = Self.warnings(for: dump.entries, existing: existing)
        checked = Set(dump.entries.map(\.playlistIndex)).subtracting(warnings.keys)
        filter = ""
        self.showPlaylistBanner = showPlaylistBanner
    }

    var selectedCount: Int {
        checked.count
    }

    var overlapCount: Int {
        checked.intersection(warnings.keys).count
    }

    var durationSum: Int {
        dump.entries.reduce(0) { sum, entry in
            guard checked.contains(entry.playlistIndex) else { return sum }
            return sum + (entry.durationSeconds ?? 0)
        }
    }

    var filteredEntries: [PlaylistEntry] {
        guard !filter.isEmpty else { return dump.entries }
        return dump.entries.filter { entry in
            entry.title.localizedCaseInsensitiveContains(filter)
        }
    }

    var footerLine: String {
        var parts = ["\(selectedCount) of \(dump.entries.count) selected"]
        if overlapCount > 0 {
            parts.append("\(overlapCount) already in queue")
        }
        parts.append("≈ \(Self.durationString(durationSum))")
        return parts.joined(separator: " · ")
    }

    mutating func selectAllFiltered() {
        for entry in filteredEntries {
            checked.insert(entry.playlistIndex)
        }
    }

    mutating func selectNoneFiltered() {
        for entry in filteredEntries {
            checked.remove(entry.playlistIndex)
        }
    }

    private static func warnings(
        for entries: [PlaylistEntry],
        existing: [(url: String, completed: Bool)]
    ) -> [Int: PlaylistRowWarning] {
        var result: [Int: PlaylistRowWarning] = [:]
        for entry in entries {
            result[entry.playlistIndex] = warning(for: entry.watchURL, existing: existing)
        }
        return result
    }

    private static func warning(
        for url: String,
        existing: [(url: String, completed: Bool)]
    ) -> PlaylistRowWarning? {
        var hasIncompleteMatch = false
        for item in existing where item.url == url {
            if item.completed {
                return .alreadySaved
            }
            hasIncompleteMatch = true
        }
        return hasIncompleteMatch ? .inQueue : nil
    }

    private static func durationString(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return "\(hours):\(padded(minutes)):\(padded(remainingSeconds))"
        }
        return "\(minutes):\(padded(remainingSeconds))"
    }

    private static func padded(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}

enum PlaylistRowWarning: Equatable {
    case inQueue
    case alreadySaved
}
