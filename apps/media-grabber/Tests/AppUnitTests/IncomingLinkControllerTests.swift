import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
private final class FakeIncomingLinkHome: IncomingLinkHome {
    var isHomeBusy = false
    var detectClipboardLinks = true
    var appliedURLs: [URL] = []
    var confirmRequests: [ConfirmationRequest] = []
    var confirmResult = false
    var onConfirm: (() async -> Void)?

    func applyIncomingURL(_ url: URL) async {
        appliedURLs.append(url)
    }

    func confirm(_ request: ConfirmationRequest) async -> Bool {
        confirmRequests.append(request)
        await onConfirm?()
        return confirmResult
    }
}

final class FakePasteboard: PasteboardReading, PasteboardWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var _string: String?
    private var _changeCount = 0

    init(string: String? = nil) {
        if let string {
            _string = string
            _changeCount = 1
        }
    }

    var changeCount: Int {
        lock.withLock { _changeCount }
    }

    func readString() -> String? {
        lock.withLock { _string }
    }

    func writeString(_ string: String) {
        lock.withLock {
            _string = string
            _changeCount += 1
        }
    }

    func setExternal(_ string: String?) {
        lock.withLock {
            _string = string
            _changeCount += 1
        }
    }
}

@MainActor
final class IncomingLinkControllerTests: XCTestCase {
    private func makeController(
        home: FakeIncomingLinkHome,
        pasteboard: FakePasteboard = FakePasteboard()
    ) -> IncomingLinkController {
        IncomingLinkController(home: home, pasteboard: pasteboard)
    }

    func test_plainText_idle_appliesWithoutConfirm() async {
        let home = FakeIncomingLinkHome()
        let controller = makeController(home: home)
        await controller.handlePlainText("watch this https://example.com/a now")
        XCTAssertEqual(home.appliedURLs.map(\.absoluteString), ["https://example.com/a"])
        XCTAssertTrue(home.confirmRequests.isEmpty)
    }

    func test_plainText_noURL_doesNothing() async {
        let home = FakeIncomingLinkHome()
        let controller = makeController(home: home)
        await controller.handlePlainText("just some words, no link")
        XCTAssertTrue(home.appliedURLs.isEmpty)
        XCTAssertTrue(home.confirmRequests.isEmpty)
    }

    func test_plainText_busy_confirmedApplies() async {
        let home = FakeIncomingLinkHome()
        home.isHomeBusy = true
        home.confirmResult = true
        let controller = makeController(home: home)
        await controller.handlePlainText("https://example.com/b")
        XCTAssertEqual(home.confirmRequests.count, 1)
        XCTAssertEqual(home.confirmRequests.first?.message, "https://example.com/b")
        XCTAssertEqual(home.appliedURLs.map(\.absoluteString), ["https://example.com/b"])
    }

    func test_plainText_busy_declinedDoesNotApply() async {
        let home = FakeIncomingLinkHome()
        home.isHomeBusy = true
        home.confirmResult = false
        let controller = makeController(home: home)
        await controller.handlePlainText("https://example.com/c")
        XCTAssertEqual(home.confirmRequests.count, 1)
        XCTAssertTrue(home.appliedURLs.isEmpty)
    }

    func test_openURL_validScheme_applies() async throws {
        let home = FakeIncomingLinkHome()
        let controller = makeController(home: home)
        let raw = "mediagrabber://open?url=https%3A%2F%2Fexample.com%2Fd"
        let url = try XCTUnwrap(URL(string: raw))
        await controller.handleOpenURL(url)
        XCTAssertEqual(home.appliedURLs.map(\.absoluteString), ["https://example.com/d"])
        XCTAssertTrue(home.confirmRequests.isEmpty)
    }

    func test_openURL_badScheme_showsFailureNotice() async throws {
        let home = FakeIncomingLinkHome()
        let controller = makeController(home: home)
        let url = try XCTUnwrap(URL(string: "mediagrabber://open?url=ftp%3A%2F%2Fx"))
        await controller.handleOpenURL(url)
        XCTAssertEqual(home.confirmRequests.count, 1)
        XCTAssertNil(home.confirmRequests.first?.cancelTitle)
        XCTAssertEqual(home.confirmRequests.first?.title, "Couldn\u{2019}t open that link")
        XCTAssertTrue(home.appliedURLs.isEmpty)
    }

    func test_openURL_validScheme_busy_confirmsBeforeApply() async throws {
        let home = FakeIncomingLinkHome()
        home.isHomeBusy = true
        home.confirmResult = true
        let controller = makeController(home: home)
        let raw = "mediagrabber://open?url=https%3A%2F%2Fexample.com%2Fe"
        let url = try XCTUnwrap(URL(string: raw))
        await controller.handleOpenURL(url)
        XCTAssertEqual(home.confirmRequests.count, 1)
        XCTAssertEqual(home.confirmRequests.first?.title, "Grab this link?")
        XCTAssertEqual(home.appliedURLs.map(\.absoluteString), ["https://example.com/e"])
    }

    // MARK: - Clipboard

    func test_clipboard_prefsOff_doesNotSniff() async {
        let home = FakeIncomingLinkHome()
        home.detectClipboardLinks = false
        let pasteboard = FakePasteboard(string: "https://example.com/clip")
        let controller = makeController(home: home, pasteboard: pasteboard)
        await controller.applicationDidBecomeActive()
        XCTAssertTrue(home.appliedURLs.isEmpty)
    }

    func test_clipboard_onActivation_sniffsAndApplies() async {
        let home = FakeIncomingLinkHome()
        let pasteboard = FakePasteboard(string: "look https://example.com/clip")
        let controller = makeController(home: home, pasteboard: pasteboard)
        await controller.applicationDidBecomeActive()
        XCTAssertEqual(home.appliedURLs.map(\.absoluteString), ["https://example.com/clip"])
    }

    func test_clipboard_sameChangeCountAndURL_deduped() async {
        let home = FakeIncomingLinkHome()
        let pasteboard = FakePasteboard(string: "https://example.com/clip")
        let controller = makeController(home: home, pasteboard: pasteboard)
        await controller.applicationDidBecomeActive()
        await controller.pollPasteboard()
        XCTAssertEqual(home.appliedURLs.count, 1)
    }

    func test_clipboard_newChangeCountNewURL_appliesAgain() async {
        let home = FakeIncomingLinkHome()
        let pasteboard = FakePasteboard(string: "https://example.com/first")
        let controller = makeController(home: home, pasteboard: pasteboard)
        await controller.applicationDidBecomeActive()
        pasteboard.setExternal("https://example.com/second")
        await controller.pollPasteboard()
        XCTAssertEqual(
            home.appliedURLs.map(\.absoluteString),
            ["https://example.com/first", "https://example.com/second"]
        )
    }

    func test_clipboard_selfWrite_ignored() async {
        let home = FakeIncomingLinkHome()
        let pasteboard = FakePasteboard()
        let controller = makeController(home: home, pasteboard: pasteboard)
        let ours = "https://example.com/ours"
        controller.markAppPasteboardWrite(ours)
        pasteboard.writeString(ours)
        await controller.pollPasteboard()
        XCTAssertTrue(home.appliedURLs.isEmpty)
    }

    func test_clipboard_externalWriteAfterSelfWrite_stillSniffed() async {
        let home = FakeIncomingLinkHome()
        let pasteboard = FakePasteboard()
        let controller = makeController(home: home, pasteboard: pasteboard)
        controller.markAppPasteboardWrite("https://example.com/ours")
        pasteboard.setExternal("https://example.com/theirs")
        await controller.pollPasteboard()
        XCTAssertEqual(home.appliedURLs.map(\.absoluteString), ["https://example.com/theirs"])
    }

    func test_clipboard_disableMidOffer_skipsApply() async {
        let home = FakeIncomingLinkHome()
        home.isHomeBusy = true
        home.confirmResult = true
        let pasteboard = FakePasteboard(string: "https://example.com/clip")
        let controller = makeController(home: home, pasteboard: pasteboard)
        home.onConfirm = { [weak controller] in
            await controller?.setClipboardDetectionEnabled(false)
        }
        await controller.applicationDidBecomeActive()
        XCTAssertEqual(home.confirmRequests.count, 1)
        XCTAssertTrue(home.appliedURLs.isEmpty)
    }
}
