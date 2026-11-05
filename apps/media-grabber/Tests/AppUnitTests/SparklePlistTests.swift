@testable import MediaGrabber
import XCTest

final class SparklePlistTests: XCTestCase {
    func test_sparklePublicKey_isAbsentOrReal() {
        let key = Bundle(for: AppDelegate.self).object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        XCTAssertNotEqual(key, "")
    }
}
