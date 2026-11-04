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
    let brand: Color
}

func palette(for kind: PaletteKind) -> PaletteTokens {
    switch kind {
    case .auroraMintIris: .auroraMintIris
    case .auroraLimeForest: .auroraLimeForest
    case .auroraMagentaViolet: .auroraMagentaViolet
    case .tapeDeckA: .tapeDeckTealRust
    case .tapeDeckB: .tapeDeckPlumBlush
    case .tapeDeckC: .tapeDeckNavyAqua
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
        glowB: Color(red: 139 / 255, green: 123 / 255, blue: 255 / 255, opacity: 0.16),
        brand: .clear
    )

    static let auroraLimeForest = aurora(
        ground: "#0A0F0C",
        panelSolid: "#0C1210",
        stroke: Color(red: 190 / 255, green: 255 / 255, blue: 210 / 255, opacity: 0.13),
        text: "#E9F2EC",
        dim: "#93A99C",
        faint: "#5F7268",
        headline: "#F2F8F3",
        accent: "#B6F04A",
        accent2: "#4ED6A0",
        warn: "#F2C14E",
        danger: "#FF6F6F",
        goEnd: "#4ED6A0",
        orbWarn: "#F2C14E",
        bannerStart: "#FF6F6F",
        glowA: ("#B6F04A", 0.16),
        glowB: ("#4ED6A0", 0.14)
    )

    static let auroraMagentaViolet = aurora(
        ground: "#100C14",
        panelSolid: "#120E16",
        stroke: Color(red: 230 / 255, green: 190 / 255, blue: 255 / 255, opacity: 0.14),
        text: "#F1EAF5",
        dim: "#A996B5",
        faint: "#7A6B85",
        headline: "#F7F2FA",
        accent: "#F25C9E",
        accent2: "#9B6BFF",
        warn: "#FFC24B",
        danger: "#FF6B6B",
        goEnd: "#9B6BFF",
        orbWarn: "#5ED6E8",
        bannerStart: "#FF6B6B",
        glowA: ("#F25C9E", 0.16),
        glowB: ("#9B6BFF", 0.16)
    )

    static let tapeDeckTealRust = tapeDeck(
        ground: "#F3E9D8",
        surface: "#FBF4E6",
        ink: "#2B2118",
        dim: "#8A7A60",
        accent: "#D2601A",
        accent2: "#0E5C57",
        warn: "#9C5A00",
        danger: "#B4472A",
        go: "#E4A11B"
    )

    static let tapeDeckPlumBlush = tapeDeck(
        ground: "#EFE9E9",
        surface: "#FBF5F5",
        ink: "#281E26",
        dim: "#8B8088",
        accent: "#E98C89",
        accent2: "#5A2E52",
        warn: "#9A6410",
        danger: "#C25B57",
        go: "#E8B24A"
    )

    static let tapeDeckNavyAqua = tapeDeck(
        ground: "#E7E9E7",
        surface: "#F5F6F3",
        ink: "#1B222A",
        dim: "#7C838A",
        accent: "#2FA69A",
        accent2: "#1F3350",
        warn: "#8E6318",
        danger: "#D9694C",
        go: "#F2B12E"
    )

    // swiftlint:disable:next function_parameter_count
    private static func aurora(
        ground: String,
        panelSolid: String,
        stroke: Color,
        text: String,
        dim: String,
        faint: String,
        headline: String,
        accent: String,
        accent2: String,
        warn: String,
        danger: String,
        goEnd: String,
        orbWarn: String,
        bannerStart: String,
        glowA: (String, Double),
        glowB: (String, Double)
    ) -> PaletteTokens {
        PaletteTokens(
            ground: Color(hex: ground),
            panelSolid: Color(hex: panelSolid),
            panel: Color(white: 1, opacity: 0.05),
            panelHi: Color(white: 1, opacity: 0.08),
            stroke: stroke,
            hair: Color(white: 1, opacity: 0.06),
            text: Color(hex: text),
            dim: Color(hex: dim),
            faint: Color(hex: faint),
            headline: Color(hex: headline),
            onAccent: Color(hex: "#07080B"),
            accent: Color(hex: accent),
            accent2: Color(hex: accent2),
            warn: Color(hex: warn),
            danger: Color(hex: danger),
            goFillStart: Color(hex: accent),
            goFillEnd: Color(hex: goEnd),
            orbStops: [
                Color(hex: accent),
                Color(hex: accent2),
                Color(hex: orbWarn),
                Color(hex: accent)
            ],
            barFillStart: Color(hex: accent),
            barFillEnd: Color(hex: goEnd),
            bannerFillStart: Color(hex: bannerStart),
            bannerFillEnd: Color(hex: warn),
            glowA: Color(hex: glowA.0).opacity(glowA.1),
            glowB: Color(hex: glowB.0).opacity(glowB.1),
            brand: .clear
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func tapeDeck(
        ground: String,
        surface: String,
        ink: String,
        dim: String,
        accent: String,
        accent2: String,
        warn: String,
        danger: String,
        go: String
    ) -> PaletteTokens {
        let inkColor = Color(hex: ink)
        let accentColor = Color(hex: accent)
        return PaletteTokens(
            ground: Color(hex: ground),
            panelSolid: Color(hex: surface),
            panel: Color(hex: ground),
            panelHi: Color.black.opacity(0.04),
            stroke: inkColor,
            hair: inkColor.opacity(0.18),
            text: inkColor,
            dim: Color(hex: dim),
            faint: Color(hex: dim),
            headline: inkColor,
            onAccent: inkColor,
            accent: accentColor,
            accent2: Color(hex: accent2),
            warn: Color(hex: warn),
            danger: Color(hex: danger),
            goFillStart: Color(hex: go),
            goFillEnd: Color(hex: go),
            orbStops: [accentColor, Color(hex: accent2), Color(hex: warn), accentColor],
            barFillStart: accentColor,
            barFillEnd: accentColor,
            bannerFillStart: accentColor,
            bannerFillEnd: accentColor,
            glowA: .clear,
            glowB: .clear,
            brand: Color(hex: accent2)
        )
    }
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
