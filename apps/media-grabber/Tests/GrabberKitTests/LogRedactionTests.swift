@testable import GrabberKit
import XCTest

final class LogRedactionTests: XCTestCase {
    func test_cookieHeader_valueIsRedacted() {
        XCTAssertEqual(LogRedaction.redact("Cookie: SID=abc; HSID=def"), "Cookie: <redacted>")
    }

    func test_setCookieHeader_valueIsRedacted() {
        XCTAssertEqual(LogRedaction.redact("Set-Cookie: a=b; Path=/"), "Set-Cookie: <redacted>")
    }

    func test_prefixIsKept() {
        XCTAssertEqual(LogRedaction.redact("[debug] Cookie: x=y"), "[debug] Cookie: <redacted>")
    }

    func test_headerNameIsCaseInsensitive() {
        XCTAssertEqual(LogRedaction.redact("cookie: x=y"), "cookie: <redacted>")
    }

    func test_multiLineInput_redactsEachHeaderLine() {
        let input = "ok line\nCookie: a=b\nnext line\nSet-Cookie: c=d"
        XCTAssertEqual(
            LogRedaction.redact(input),
            "ok line\nCookie: <redacted>\nnext line\nSet-Cookie: <redacted>"
        )
    }

    func test_extractedCountLine_isUnchanged() {
        XCTAssertEqual(LogRedaction.redact("Extracted 12 cookies from chrome"), "Extracted 12 cookies from chrome")
    }

    func test_jobLogAppend_writesRedactedHeader() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mg-redact-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let request = DownloadRequest(
            url: "https://archive.org/x",
            destFolder: URL(fileURLWithPath: "/tmp/out"),
            kind: .video(maxHeight: 1080),
            container: "mp4",
            filenameTemplate: "%(title)s.%(ext)s"
        )
        let id = UUID()
        let log = JobLog(id: id, request: request, ytDlpVersion: "1", dir: dir)
        try log.writeHeader()
        log.append(.stderr("Cookie: SID=secret"))
        log.close()
        let text = try String(contentsOf: dir.appendingPathComponent("\(id.uuidString).log"), encoding: .utf8)
        XCTAssertTrue(text.contains("Cookie: <redacted>"))
        XCTAssertFalse(text.contains("secret"))
    }
}
