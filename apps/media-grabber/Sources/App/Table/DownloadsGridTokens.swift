import AppKit
import GrabberKit

struct DownloadsGridTokens {
    let ground: NSColor
    let panelSolid: NSColor
    let panel: NSColor
    let panelHi: NSColor
    let stroke: NSColor
    let hair: NSColor
    let text: NSColor
    let dim: NSColor
    let faint: NSColor
    let accent: NSColor
    let accent2: NSColor
    let warn: NSColor
    let danger: NSColor
    let barFillStart: NSColor
    let barFillEnd: NSColor
    let hairlineWidth: CGFloat

    let body12: NSFont
    let body13Semibold: NSFont
    let body12Medium: NSFont
    let mono10Semibold: NSFont
    let mono11Medium: NSFont
    let mono11: NSFont

    // Matches PaletteTokens.auroraMintIris (AppKit-owned copies; no SwiftUI Color bridge).
    nonisolated(unsafe) static let aurora = DownloadsGridTokens(
        ground: hex("#0C1013"),
        panelSolid: hex("#0E1117"),
        panel: NSColor(white: 1, alpha: 0.05),
        panelHi: NSColor(white: 1, alpha: 0.08),
        stroke: NSColor(white: 1, alpha: 0.12),
        hair: NSColor(white: 1, alpha: 0.06),
        text: hex("#EDF0F5"),
        dim: hex("#9AA3B2"),
        faint: hex("#6B7480"),
        accent: hex("#5EF2C8"),
        accent2: hex("#8B7BFF"),
        warn: hex("#FFC24B"),
        danger: hex("#FF7A6B"),
        barFillStart: hex("#5EF2C8"),
        barFillEnd: hex("#8B7BFF"),
        hairlineWidth: 1,
        body12: NSFont.systemFont(ofSize: 12, weight: .regular),
        body13Semibold: NSFont.systemFont(ofSize: 13, weight: .semibold),
        body12Medium: NSFont.systemFont(ofSize: 12, weight: .medium),
        mono10Semibold: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
        mono11Medium: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
        mono11: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    )

    static func make(theme: Theme) -> DownloadsGridTokens {
        // All palettes currently resolve to aurora; keep Theme in the API for later skins.
        _ = theme
        return .aurora
    }

    func statusDotColor(for state: JobState) -> NSColor {
        switch state {
        case .queued: accent2
        case .probing, .running: accent
        case .paused, .waitingForNetwork: dim
        case .cooldown: warn
        case .failed: danger
        case .completed, .cancelled: dim
        }
    }

    func statusTextColor(for state: JobState) -> NSColor {
        switch state {
        case .failed: danger
        case .completed, .cancelled: dim
        default: text
        }
    }

    private static func hex(_ value: String) -> NSColor {
        let raw = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard raw.count == 6, let int = UInt64(raw, radix: 16) else {
            return .labelColor
        }
        let red = CGFloat((int >> 16) & 0xFF) / 255
        let green = CGFloat((int >> 8) & 0xFF) / 255
        let blue = CGFloat(int & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

extension IconKind {
    var systemSymbolName: String {
        switch self {
        case .pause: "pause.fill"
        case .resume: "play.fill"
        case .cancel: "xmark"
        case .forceStart: "arrow.up.to.line"
        case .retry: "arrow.clockwise"
        case .retryWithCookies: "key.fill"
        case .reveal: "folder"
        case .openInBrowser: "globe"
        case .remove: "trash"
        case .showLog: "doc.text"
        case .sortNeutral: "arrow.up.arrow.down"
        case .sortAsc: "chevron.up"
        case .sortDesc: "chevron.down"
        case .filter: "line.3.horizontal.decrease.circle"
        case .columnsMenu: "tablecells"
        case .warning: "exclamationmark.triangle.fill"
        }
    }
}
