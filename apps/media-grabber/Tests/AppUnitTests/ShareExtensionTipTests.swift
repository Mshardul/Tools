import Foundation
import XCTest

final class ShareExtensionTipTests: XCTestCase {
    func test_dismissedFlag_persistsAcrossReads() throws {
        let suiteName = "ShareExtensionTipTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(defaults.bool(forKey: "mg.shareExtensionTipDismissed"))
        defaults.set(true, forKey: "mg.shareExtensionTipDismissed")
        XCTAssertTrue(defaults.bool(forKey: "mg.shareExtensionTipDismissed"))
    }
}
