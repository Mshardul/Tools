@testable import GrabberKit
import XCTest

final class LinkExtractorTests: XCTestCase {
    func testHTTPS() {
        XCTAssertEqual(
            LinkExtractor.extract(from: "  https://example.com/a  ")?.absoluteString,
            "https://example.com/a"
        )
    }

    func testAngleBrackets() {
        XCTAssertEqual(
            LinkExtractor.extract(from: "<https://youtu.be/x>")?.absoluteString,
            "https://youtu.be/x"
        )
    }

    func testAngleBracketsMidSentence() {
        XCTAssertEqual(
            LinkExtractor.extract(from: "grab <https://youtu.be/x> when you can")?.absoluteString,
            "https://youtu.be/x"
        )
    }

    func testFirstOfMany() {
        XCTAssertEqual(
            LinkExtractor.extract(from: "see https://a.example and https://b.example")?.absoluteString,
            "https://a.example"
        )
    }

    func testRejectsWWWWithoutScheme() {
        XCTAssertNil(LinkExtractor.extract(from: "www.youtube.com/watch?v=1"))
    }

    func testRejectsEmpty() {
        XCTAssertNil(LinkExtractor.extract(from: "   "))
    }
}
