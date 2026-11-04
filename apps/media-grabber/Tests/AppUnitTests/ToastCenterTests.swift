@testable import MediaGrabber
import XCTest

@MainActor
final class ToastCenterTests: XCTestCase {
    func test_fillIsOpaquePanel() {
        let palette = palette(for: .auroraMintIris)
        XCTAssertEqual(ToastChrome.fill(palette).description, palette.panelSolid.description)
    }

    func test_hasAShadow() {
        XCTAssertEqual(ToastChrome.shadowY, 12)
        XCTAssertGreaterThan(ToastChrome.shadowRadius, 0)
    }

    func test_sitsClearOfTheBanner() {
        XCTAssertEqual(ToastChrome.bottomInset(bannerHeight: 0), Spacing.s4)
        let banner: CGFloat = 48
        XCTAssertGreaterThanOrEqual(ToastChrome.bottomInset(bannerHeight: banner), banner + Spacing.s4 + Spacing.s4)
    }

    func test_enqueue_appendsToItems() {
        let center = ToastCenter()
        center.enqueue(ToastItem(text: "Clip.mp4 saved", actionTitle: "Reveal", action: nil))
        XCTAssertEqual(center.items.count, 1)
        XCTAssertEqual(center.items.first?.text, "Clip.mp4 saved")
    }

    func test_enqueue_stacksMultipleInOrder() {
        let center = ToastCenter()
        center.enqueue(ToastItem(text: "First", actionTitle: nil, action: nil))
        center.enqueue(ToastItem(text: "Second", actionTitle: nil, action: nil))
        XCTAssertEqual(center.items.map(\.text), ["First", "Second"])
    }

    func test_dismiss_removesOnlyThatItem() {
        let center = ToastCenter()
        let first = ToastItem(text: "First", actionTitle: nil, action: nil)
        let second = ToastItem(text: "Second", actionTitle: nil, action: nil)
        center.enqueue(first)
        center.enqueue(second)

        center.dismiss(first.id)

        XCTAssertEqual(center.items.map(\.text), ["Second"])
    }

    func test_autoDismiss_removesAfterDelay() async throws {
        let center = ToastCenter(autoDismissDelay: .milliseconds(50))
        center.enqueue(ToastItem(text: "Ephemeral", actionTitle: nil, action: nil))
        XCTAssertEqual(center.items.count, 1)

        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(center.items.count, 0)
    }
}
