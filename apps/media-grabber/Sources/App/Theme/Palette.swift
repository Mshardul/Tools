import GrabberKit
import SwiftUI

struct PaletteTokens {
    let ground: Color
    let panelSolid: Color
    let panel: Color
    let panelHi: Color
    let stroke: Color
    let hair: Color

    let text: Color
    let dim: Color
    let faint: Color
    let headline: Color
    let onAccent: Color

    let accent: Color
    let accent2: Color
    let warn: Color
    let danger: Color

    let goFillStart: Color
    let goFillEnd: Color
    let orbStops: [Color]
    let barFillStart: Color
    let barFillEnd: Color
    let bannerFillStart: Color
    let bannerFillEnd: Color
    let glowA: Color
    let glowB: Color
}

// Phase 1 ships only Mint & Iris; other kinds fall back to it (Phase 9 fills them in).
func palette(for kind: PaletteKind) -> PaletteTokens {
    switch kind {
    case .auroraMintIris,
         .auroraLimeForest,
         .auroraMagentaViolet,
         .tapeDeckA,
         .tapeDeckB,
         .tapeDeckC:
        .auroraMintIris
    }
}

extension PaletteTokens {
    static let auroraMintIris = PaletteTokens(
        ground: Color(hex: "#0C1013"),
        panelSolid: Color(hex: "#0E1117"),
        panel: Color(white: 1, opacity: 0.05),
        panelHi: Color(white: 1, opacity: 0.08),
        stroke: Color(white: 1, opacity: 0.12),
        hair: Color(white: 1, opacity: 0.06),
        text: Color(hex: "#EDF0F5"),
        dim: Color(hex: "#9AA3B2"),
        faint: Color(hex: "#6B7480"),
        headline: Color(hex: "#F4F6FA"),
        onAccent: Color(hex: "#07080B"),
        accent: Color(hex: "#5EF2C8"),
        accent2: Color(hex: "#8B7BFF"),
        warn: Color(hex: "#FFC24B"),
        danger: Color(hex: "#FF7A6B"),
        goFillStart: Color(hex: "#5EF2C8"),
        goFillEnd: Color(hex: "#8B7BFF"),
        orbStops: [
            Color(hex: "#5EF2C8"),
            Color(hex: "#8B7BFF"),
            Color(hex: "#FF7A6B"),
            Color(hex: "#5EF2C8")
        ],
        barFillStart: Color(hex: "#5EF2C8"),
        barFillEnd: Color(hex: "#8B7BFF"),
        bannerFillStart: Color(hex: "#FF7A6B"),
        bannerFillEnd: Color(hex: "#FFC24B"),
        glowA: Color(red: 94 / 255, green: 242 / 255, blue: 200 / 255, opacity: 0.14),
        glowB: Color(red: 139 / 255, green: 123 / 255, blue: 255 / 255, opacity: 0.16)
    )
}

extension Color {
    // #RRGGBB or #RRGGBBAA; falls back to .clear on a malformed string.
    init(hex: String) {
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard let value = UInt64(raw, radix: 16) else {
            self = .clear
            return
        }
        let red, green, blue, alpha: Double
        switch raw.count {
        case 6:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        default:
            self = .clear
            return
        }
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
