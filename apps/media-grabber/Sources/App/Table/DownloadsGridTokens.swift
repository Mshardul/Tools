import AppKit
import GrabberKit
import SwiftUI

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
    let controlBorderWidth: CGFloat

    let cell: NSFont
    let body13Semibold: NSFont
    let body12Medium: NSFont
    let header: NSFont
    let pill: NSFont
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
        controlBorderWidth: 1,
        cell: GridFont.body(13),
        body13Semibold: GridFont.body(13, .semibold),
        body12Medium: GridFont.body(12, .medium),
        header: GridFont.mono(10, .medium),
        pill: GridFont.mono(10),
        mono11: GridFont.mono(11)
    )

    static func make(theme: Theme) -> DownloadsGridTokens {
        let palette = theme.palette
        let type = DownloadsGridTokens.aurora
        return DownloadsGridTokens(
            ground: nsColor(palette.ground),
            panelSolid: nsColor(palette.panelSolid),
            panel: nsColor(palette.panel),
            panelHi: nsColor(palette.panelHi),
            stroke: nsColor(palette.stroke),
            hair: nsColor(palette.hair),
            text: nsColor(palette.text),
            dim: nsColor(palette.dim),
            faint: nsColor(palette.faint),
            accent: nsColor(palette.accent),
            accent2: nsColor(palette.accent2),
            warn: nsColor(palette.warn),
            danger: nsColor(palette.danger),
            barFillStart: nsColor(palette.barFillStart),
            barFillEnd: nsColor(palette.barFillEnd),
            hairlineWidth: theme.hairlineWidth,
            controlBorderWidth: theme.controlBorderWidth,
            cell: GridFont.body(13, family: theme.bodyFamily),
            body13Semibold: GridFont.body(13, .semibold, family: theme.bodyFamily),
            body12Medium: GridFont.body(12, .medium, family: theme.bodyFamily),
            header: GridFont.mono(10, .medium, family: theme.monoFamily),
            pill: GridFont.mono(10, family: theme.monoFamily),
            mono11: GridFont.mono(11, family: theme.monoFamily)
        )
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

    private static func nsColor(_ color: Color) -> NSColor {
        let resolved = color.resolve(in: EnvironmentValues())
        return NSColor(
            srgbRed: CGFloat(resolved.red),
            green: CGFloat(resolved.green),
            blue: CGFloat(resolved.blue),
            alpha: CGFloat(resolved.opacity)
        )
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
        case .enterPasscode: "lock.fill"
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

enum GridFont {
    static func body(
        _ size: CGFloat,
        _ weight: NSFont.Weight = .regular,
        family: String = Theme.auroraBodyFamily
    ) -> NSFont {
        custom(family, size, weight) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func mono(
        _ size: CGFloat,
        _ weight: NSFont.Weight = .regular,
        family: String = Theme.auroraMonoFamily
    ) -> NSFont {
        custom(family, size, weight) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func custom(_ family: String, _ size: CGFloat, _ weight: NSFont.Weight) -> NSFont? {
        guard NSFont(name: family, size: size) != nil else { return nil }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]
        ])
        return NSFont(descriptor: descriptor, size: size)
    }
}
