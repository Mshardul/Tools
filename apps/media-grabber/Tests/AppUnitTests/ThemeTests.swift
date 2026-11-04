import AppKit
import GrabberKit
@testable import MediaGrabber
import SwiftUI
import XCTest

final class ThemeTests: XCTestCase {
    func test_auroraTheme_radii() {
        let theme = Theme(.aurora)
        XCTAssertEqual(theme.windowRadius, 18)
        XCTAssertEqual(theme.cardRadius, 14)
        XCTAssertEqual(theme.controlRadius, 9)
        XCTAssertEqual(theme.pillRadius, 20)
        XCTAssertEqual(theme.chipRadius, 7)
        XCTAssertEqual(theme.hairlineWidth, 1)
    }

    func test_auroraTheme_motifIsOrb() {
        XCTAssertEqual(Theme(.aurora).motif, .orb)
        XCTAssertEqual(MotifView.style(for: Theme(.aurora)), .orb)
    }

    func test_tapeDeckTheme_shapeAndBorder() {
        let theme = Theme(.tapeDeck)
        XCTAssertEqual(theme.windowRadius, 14)
        XCTAssertEqual(theme.cardRadius, 12)
        XCTAssertEqual(theme.controlRadius, 8)
        XCTAssertEqual(theme.pillRadius, 20)
        XCTAssertEqual(theme.chipRadius, 6)
        XCTAssertEqual(theme.hairlineWidth, 2)
        XCTAssertEqual(theme.controlBorderWidth, 1.5)
        XCTAssertEqual(theme.cardShadowOffset, 8)
        XCTAssertEqual(theme.cardShadowRadius, 0)
        XCTAssertEqual(MotifView.style(for: theme), .reel)
        XCTAssertEqual(palette(for: .tapeDeckA).brand, Color(hex: "#0E5C57"))
        XCTAssertEqual(palette(for: .tapeDeckB).brand, Color(hex: "#5A2E52"))
        XCTAssertEqual(palette(for: .tapeDeckC).brand, Color(hex: "#1F3350"))
        let grid = DownloadsGridTokens.make(theme: theme)
        XCTAssertEqual(grid.hairlineWidth, 2)
        XCTAssertEqual(grid.controlBorderWidth, 1.5)
    }

    func test_mintIrisPalette_keyTokens() {
        let palette = palette(for: .auroraMintIris)
        XCTAssertEqual(palette.accent, Color(hex: "#5EF2C8"))
        XCTAssertEqual(palette.danger, Color(hex: "#FF7A6B"))
        XCTAssertEqual(palette.ground, Color(hex: "#0C1013"))
        XCTAssertEqual(palette.orbStops.count, 4)
    }

    func test_eachPalette_usesItsOwnAccent() {
        let accents: [(PaletteKind, String)] = [
            (.auroraMintIris, "#5EF2C8"),
            (.auroraLimeForest, "#B6F04A"),
            (.auroraMagentaViolet, "#F25C9E"),
            (.tapeDeckA, "#D2601A"),
            (.tapeDeckB, "#E98C89"),
            (.tapeDeckC, "#2FA69A")
        ]
        for (kind, hex) in accents {
            XCTAssertEqual(palette(for: kind).accent, Color(hex: hex), "\(kind)")
        }
    }

    func test_gridTokens_followTheActivePalette() {
        let theme = Theme(themeKind: .aurora, paletteKind: .auroraLimeForest)
        let accent = DownloadsGridTokens.make(theme: theme).accent
        XCTAssertEqual(srgbHex(accent), "#B6F04A")
    }

    func test_paletteSwatch_is56PointsWide() {
        XCTAssertEqual(AppearancePane.swatchWidth, 56)
    }

    func test_gridTokens_useTheThemeTypefaces() {
        let tapeDeck = DownloadsGridTokens.make(theme: Theme(.tapeDeck))
        XCTAssertEqual(tapeDeck.cell.familyName, "DM Sans")
        XCTAssertEqual(tapeDeck.header.familyName, "DM Mono")
        let aurora = DownloadsGridTokens.make(theme: Theme(.aurora))
        XCTAssertEqual(aurora.cell.familyName, "IBM Plex Sans")
        XCTAssertEqual(aurora.header.familyName, "JetBrains Mono")
    }

    func test_defaultEnvironmentTheme_isAuroraMintIris() {
        let theme = EnvironmentValues().theme
        XCTAssertEqual(theme.palette.accent, Color(hex: "#5EF2C8"))
    }

    func test_spacingScale() {
        XCTAssertEqual(Spacing.s1, 4)
        XCTAssertEqual(Spacing.s2, 8)
        XCTAssertEqual(Spacing.s3, 12)
        XCTAssertEqual(Spacing.s4, 16)
        XCTAssertEqual(Spacing.s5, 22)
        XCTAssertEqual(Spacing.s6, 30)
        XCTAssertEqual(Spacing.s7, 44)
    }

    @MainActor
    func test_auroraBodyFont_chosenFamilyResolves() {
        XCTAssertEqual(Theme.auroraBodyFamily, "IBM Plex Sans")
        XCTAssertEqual(Theme(.aurora).bodyFamily, "IBM Plex Sans")
        XCTAssertEqual(Theme(.aurora).displayFamily, "Sora")
        XCTAssertEqual(Theme(.aurora).monoFamily, "JetBrains Mono")
        XCTAssertEqual(Theme(.tapeDeck).displayFamily, "Bricolage Grotesque")
        XCTAssertEqual(Theme(.tapeDeck).bodyFamily, "DM Sans")
        XCTAssertEqual(Theme(.tapeDeck).monoFamily, "DM Mono")
    }

    private func srgbHex(_ color: NSColor) -> String {
        let resolved = color.usingColorSpace(.sRGB) ?? color
        let red = Int((resolved.redComponent * 255).rounded())
        let green = Int((resolved.greenComponent * 255).rounded())
        let blue = Int((resolved.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    @MainActor
    func test_motifView_staticUnderReduceMotion() {
        let view = MotifView(isActive: true, size: 20)
        XCTAssertFalse(view.isSpinning(reduceMotion: true))
        XCTAssertTrue(view.isSpinning(reduceMotion: false))
    }
}
