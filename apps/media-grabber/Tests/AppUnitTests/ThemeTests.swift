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
    }

    func test_mintIrisPalette_keyTokens() {
        let palette = palette(for: .auroraMintIris)
        XCTAssertEqual(palette.accent, Color(hex: "#5EF2C8"))
        XCTAssertEqual(palette.danger, Color(hex: "#FF7A6B"))
        XCTAssertEqual(palette.ground, Color(hex: "#0C1013"))
        XCTAssertEqual(palette.orbStops.count, 4)
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
    func test_motifView_staticUnderReduceMotion() {
        let view = MotifView(isActive: true, size: 20)
        XCTAssertFalse(view.isSpinning(reduceMotion: true))
        XCTAssertTrue(view.isSpinning(reduceMotion: false))
    }
}
