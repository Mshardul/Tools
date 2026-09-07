@testable import GrabberKit
import XCTest

final class YtDlpArgumentsLanguageTests: XCTestCase {
    private let dest = URL(fileURLWithPath: "/Users/x/Movies")
    private let url = "https://example.com/watch?v=abc"

    private func request(
        kind: DownloadKind,
        audioLanguage: AudioLanguage = .unspecified,
        container: String? = nil
    ) -> DownloadRequest {
        DownloadRequest(
            url: url,
            destFolder: dest,
            kind: kind,
            container: container,
            audioLanguage: audioLanguage
        )
    }

    func testUnspecifiedVideoFormatMatchesToday() {
        let argv = YtDlpArguments.build(
            for: request(kind: .video(maxHeight: 1080), container: "mp4"),
            concurrentFragments: 4
        )
        XCTAssertTrue(argv.contains(
            "bv*[height<=1080][ext=mp4]+ba[ext=m4a]/bv*[height<=1080]+ba/b[height<=1080]"
        ))
    }

    func testCodeSplicesLanguageOntoBa() {
        let argv = YtDlpArguments.build(
            for: request(kind: .video(maxHeight: 1080), audioLanguage: .code("ja")),
            concurrentFragments: 4
        )
        let selector = argv.first { $0.contains("ba[language=ja]") }
        XCTAssertNotNil(selector)
        XCTAssertTrue(selector?.contains("ba[language=ja][ext=m4a]") == true)
        XCTAssertTrue(selector?.contains("/bv*[height<=1080][ext=mp4]+ba[ext=m4a]") == true)
    }

    func testOriginalSplicesFormatNote() {
        let argv = YtDlpArguments.build(
            for: request(kind: .video(maxHeight: 720), audioLanguage: .original),
            concurrentFragments: 4
        )
        let selector = argv.first { $0.contains("format_note*=original") }
        XCTAssertNotNil(selector)
        XCTAssertTrue(selector?.contains("ba[format_note*=original][ext=m4a]") == true)
    }

    func testAudioCodePrependsFormatFilter() {
        let argv = YtDlpArguments.build(
            for: request(kind: .audio(format: .m4a), audioLanguage: .code("ja")),
            concurrentFragments: 4
        )
        XCTAssertTrue(argv.contains("ba[language=ja]/ba"))
        XCTAssertTrue(hasSubsequence(argv, ["-x", "--audio-format", "m4a"]))
        let fIndex = argv.firstIndex(of: "-f")
        let xIndex = argv.firstIndex(of: "-x")
        XCTAssertNotNil(fIndex)
        XCTAssertNotNil(xIndex)
        if let fIndex, let xIndex {
            XCTAssertLessThan(fIndex, xIndex)
        }
    }

    private func hasSubsequence(_ array: [String], _ sub: [String]) -> Bool {
        guard let start = array.firstIndex(of: sub[0]) else { return false }
        guard start + sub.count <= array.count else { return false }
        return Array(array[start ..< start + sub.count]) == sub
    }
}
