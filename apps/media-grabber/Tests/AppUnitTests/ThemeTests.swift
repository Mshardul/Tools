@testable import MediaGrabber
import SwiftUI
import XCTest

final class ThemeTests: XCTestCase {
    func test_auroraSkin_radii() {
        let skin = Skin(.aurora)
        XCTAssertEqual(skin.windowRadius, 18)
        XCTAssertEqual(skin.cardRadius, 14)
        XCTAssertEqual(skin.controlRadius, 9)
        XCTAssertEqual(skin.pillRadius, 20)
        XCTAssertEqual(skin.chipRadius, 7)
        XCTAssertEqual(skin.hairlineWidth, 1)
    }

    func test_auroraSkin_motifIsOrb() {
        XCTAssertEqual(Skin(.aurora).motif, .orb)
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
