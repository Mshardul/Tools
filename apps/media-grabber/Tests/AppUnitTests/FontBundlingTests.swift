import AppKit
import XCTest

final class FontBundlingTests: XCTestCase {
    func test_soraFamily_resolvesAfterBundling() {
        XCTAssertNotNil(
            NSFont(name: "Sora", size: 14),
            "Sora must resolve once bundled — check ATSApplicationFontsPath"
        )
    }

    func test_interFamily_resolvesAfterBundling() {
        XCTAssertNotNil(NSFont(name: "Inter", size: 14))
    }

    func test_jetBrainsMonoFamily_resolvesAfterBundling() {
        XCTAssertNotNil(NSFont(name: "JetBrains Mono", size: 14))
    }
}
