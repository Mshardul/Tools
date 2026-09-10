import Foundation
@testable import MediaGrabber
import XCTest

final class IncomingLinkSchemeTests: XCTestCase {
    private func schemeURL(query: String) throws -> URL {
        let string = "mediagrabber://open?\(query)"
        let url = try XCTUnwrap(URL(string: string))
        XCTAssertEqual(url.scheme, IncomingLinkScheme.scheme)
        XCTAssertEqual(url.host, "open")
        XCTAssertTrue(url.path.isEmpty)
        XCTAssertEqual(url.absoluteString, string)
        return url
    }

    func test_validHTTPS() throws {
        let incoming = try schemeURL(query: "url=https%3A%2F%2Fexample.com%2Fwatch%3Fv%3Dabc")
        let result = IncomingLinkScheme.openURL(from: incoming)

        XCTAssertEqual(
            result,
            try .success(XCTUnwrap(URL(string: "https://example.com/watch?v=abc")))
        )
    }

    func test_validHTTP() throws {
        let incoming = try schemeURL(query: "url=http%3A%2F%2Fexample.com")
        let result = IncomingLinkScheme.openURL(from: incoming)

        XCTAssertEqual(result, try .success(XCTUnwrap(URL(string: "http://example.com"))))
    }

    func test_extraQueryKeysIgnored() throws {
        let incoming = try schemeURL(query: "foo=bar&url=https%3A%2F%2Fexample.com&baz=1")
        let result = IncomingLinkScheme.openURL(from: incoming)

        XCTAssertEqual(result, try .success(XCTUnwrap(URL(string: "https://example.com"))))
    }

    func test_pathOpenFormAccepted() throws {
        let incoming = try XCTUnwrap(URL(string: "mediagrabber:///open?url=https%3A%2F%2Fexample.com"))
        XCTAssertEqual(incoming.path, "/open")

        let result = IncomingLinkScheme.openURL(from: incoming)
        XCTAssertEqual(result, try .success(XCTUnwrap(URL(string: "https://example.com"))))
    }

    func test_missingURLQueryKey() throws {
        let incoming = try schemeURL(query: "foo=bar")
        XCTAssertEqual(IncomingLinkScheme.openURL(from: incoming), .failure(.missingURL))
    }

    func test_emptyURLQueryValue() throws {
        let incoming = try schemeURL(query: "url=")
        XCTAssertEqual(IncomingLinkScheme.openURL(from: incoming), .failure(.missingURL))
    }

    func test_malformedPercentEncoding() throws {
        let incoming = try XCTUnwrap(URL(string: "mediagrabber://open?url=%"))
        XCTAssertEqual(IncomingLinkScheme.openURL(from: incoming), .failure(.malformed))
    }

    func test_malformedDecodedURLString() throws {
        let incoming = try schemeURL(query: "url=not%20a%20url")
        XCTAssertEqual(IncomingLinkScheme.openURL(from: incoming), .failure(.malformed))
    }

    func test_notWebURL_ftp() throws {
        let incoming = try schemeURL(query: "url=ftp%3A%2F%2Fexample.com%2Ffile")
        XCTAssertEqual(IncomingLinkScheme.openURL(from: incoming), .failure(.notWebURL))
    }

    func test_wrongScheme() throws {
        let incoming = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertEqual(IncomingLinkScheme.openURL(from: incoming), .failure(.wrongScheme))
    }

    func test_wrongOpenTarget() throws {
        let incoming = try XCTUnwrap(URL(string: "mediagrabber://close?url=https%3A%2F%2Fexample.com"))
        XCTAssertEqual(IncomingLinkScheme.openURL(from: incoming), .failure(.malformed))
    }
}
