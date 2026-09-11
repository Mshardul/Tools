import Foundation
@testable import GrabberKit
import UniformTypeIdentifiers
import XCTest

final class ShareExtractorTests: XCTestCase {
    private func item(url: URL) -> NSExtensionItem {
        let provider = NSItemProvider(object: url as NSURL)
        let item = NSExtensionItem()
        item.attachments = [provider]
        return item
    }

    private func item(text: String) -> NSExtensionItem {
        let provider = NSItemProvider(object: text as NSString)
        let item = NSExtensionItem()
        item.attachments = [provider]
        return item
    }

    private func item(noAttachment _: Void = ()) -> NSExtensionItem {
        NSExtensionItem()
    }

    func test_urlTypeItem_extracts() async throws {
        let result = try await ShareExtractor
            .extractURL(from: [item(url: XCTUnwrap(URL(string: "https://example.com/a")))])
        XCTAssertEqual(result?.absoluteString, "https://example.com/a")
    }

    func test_plainTextItem_withURL_extracts() async {
        let result = await ShareExtractor.extractURL(from: [item(text: "check this out https://example.com/b")])
        XCTAssertEqual(result?.absoluteString, "https://example.com/b")
    }

    func test_plainTextItem_withoutURL_returnsNil() async {
        let result = await ShareExtractor.extractURL(from: [item(text: "no link here")])
        XCTAssertNil(result)
    }

    func test_noAttachments_returnsNil() async {
        let result = await ShareExtractor.extractURL(from: [item()])
        XCTAssertNil(result)
    }

    func test_emptyItems_returnsNil() async {
        let result = await ShareExtractor.extractURL(from: [])
        XCTAssertNil(result)
    }

    func test_firstItemWins_whenMultiple() async throws {
        let items = try [
            item(url: XCTUnwrap(URL(string: "https://first.example"))),
            item(url: XCTUnwrap(URL(string: "https://second.example")))
        ]
        let result = await ShareExtractor.extractURL(from: items)
        XCTAssertEqual(result?.absoluteString, "https://first.example")
    }
}
