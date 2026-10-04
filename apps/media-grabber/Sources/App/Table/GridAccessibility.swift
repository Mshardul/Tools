import Foundation

enum GridKeyboard {
    static let up: UInt16 = 126
    static let down: UInt16 = 125
    static let space: UInt16 = 49
    static let tab: UInt16 = 48

    enum Command: Equatable {
        case move(delta: Int, extending: Bool)
        case toggleSelection
        case enterRowActions(reverse: Bool)
        case ignored
    }

    static func command(keyCode: UInt16, shift: Bool) -> Command {
        switch keyCode {
        case up:
            .move(delta: -1, extending: shift)
        case down:
            .move(delta: 1, extending: shift)
        case space:
            .toggleSelection
        case tab:
            .enterRowActions(reverse: shift)
        default:
            .ignored
        }
    }
}

enum GridKeyboardFocus {
    static func destination(from row: Int, delta: Int, rowCount: Int) -> Int? {
        guard rowCount > 0, delta != 0 else { return nil }
        let start = row < 0 ? (delta > 0 ? -1 : rowCount) : row
        let next = start + delta
        guard next >= 0, next < rowCount else { return nil }
        return next
    }
}

enum GridKeyView {
    static func refusesFirstResponder(enabled: Bool, rowIsKeyboardFocus: Bool) -> Bool {
        !(enabled && rowIsKeyboardFocus)
    }
}

enum GridHeaderAccessibility {
    enum Sort: Equatable {
        case unavailable
        case available
        case ascending
        case descending
    }

    static func label(title: String, sort: Sort, showsFilter: Bool, filterActive: Bool) -> String {
        var parts = [title]
        switch sort {
        case .unavailable:
            break
        case .available:
            parts.append("sortable")
        case .ascending:
            parts.append("sorted ascending")
        case .descending:
            parts.append("sorted descending")
        }
        if showsFilter {
            parts.append(filterActive ? "filter on" : "filter")
        }
        return parts.joined(separator: ", ")
    }

    static func selectionLabel(allSelected: Bool) -> String {
        allSelected ? "Clear selection" : "Select all"
    }
}

enum GridStatusAccessibility {
    static func label(status: String, remark: String) -> String {
        remark.isEmpty ? status : "\(status), \(remark)"
    }
}

enum HealthChipAccessibility {
    static func refreshLabel(id: String) -> String {
        switch id {
        case "shield": "Restart bot-check shield"
        case "engine": "Reinstall downloader"
        default: "Refresh"
        }
    }

    static func popoverLabel(chipLabel: String) -> String {
        "\(chipLabel), host rate"
    }
}
