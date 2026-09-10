import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class IncomingLinkDialogsTests: XCTestCase {
    func test_incomingLinkBusyConfirmation_fields() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/watch?v=abc"))
        let request = AppModelDialogs.incomingLinkBusyConfirmation(url: url)

        XCTAssertEqual(request.title, "Grab this link?")
        XCTAssertEqual(request.message, "https://example.com/watch?v=abc")
        XCTAssertEqual(request.confirmTitle, "Grab")
        XCTAssertEqual(request.cancelTitle, "Not now")
        XCTAssertNil(request.suppressionKey)
        XCTAssertFalse(request.isDestructive)
    }

    func test_incomingLinkSchemeFailureNotice_fields() {
        let request = AppModelDialogs.incomingLinkSchemeFailureNotice()

        XCTAssertEqual(request.title, "Couldn\u{2019}t open that link")
        XCTAssertEqual(request.message, "The link was missing or not a web address.")
        XCTAssertEqual(request.confirmTitle, "OK")
        XCTAssertNil(request.cancelTitle)
    }

    func test_appModel_conformsToIncomingLinkHome() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "mg.incoming.\(UUID().uuidString)"))
        let logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-incoming-\(UUID().uuidString)")
        let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory)
        let home: IncomingLinkHome = model

        XCTAssertFalse(home.isHomeBusy)
        XCTAssertTrue(home.detectClipboardLinks)
        model.prefs.detectClipboardLinks = false
        XCTAssertFalse(home.detectClipboardLinks)
    }
}
