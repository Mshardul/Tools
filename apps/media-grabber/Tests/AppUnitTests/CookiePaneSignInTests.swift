@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
final class CookiePaneSignInTests: XCTestCase {
    private struct StubProbe: MetadataProbing {
        let result: Result<MediaMetadata, MetadataError>
        func probe(
            _: String,
            context _: ExtractorContext,
            onWait _: (@Sendable (Date?) -> Void)?
        ) async -> Result<MediaMetadata, MetadataError> {
            result
        }

        func probePlaylist(_: String, context _: ExtractorContext) async -> Result<PlaylistDump, MetadataError> {
            .failure(.malformedOutput)
        }
    }

    private let home = URL(fileURLWithPath: "/Users/tester")

    private func model(
        _ source: CookieSource,
        installed dir: String?,
        result: Result<MediaMetadata, MetadataError>
    ) throws -> CookiePaneModel {
        let prefs = try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)))
        prefs.cookiesFromBrowser = source
        var fm = FakeFileManaging()
        if let dir {
            fm.files = [home.appendingPathComponent("Library/Application Support/\(dir)").path]
        }
        return CookiePaneModel(
            prefs: prefs,
            resolver: CookieResolver(fileManager: fm, home: home),
            signInProbe: StubProbe(result: result)
        )
    }

    private let ok = Result<MediaMetadata, MetadataError>.success(
        MediaMetadata(title: "t", durationSeconds: 1, isPlaylist: false, sourceURL: "u")
    )

    func test_passes_whenSignInCanBeRead() async throws {
        let sut = try model(.brave, installed: "BraveSoftware/Brave-Browser", result: ok)
        await sut.testSignIn()
        XCTAssertEqual(sut.signInTest, .passed("MediaGrabber can read your Brave sign-in."))
    }

    func test_cookieReadFailure_isPlainAndActionable() async throws {
        let sut = try model(.brave, installed: "BraveSoftware/Brave-Browser", result: .failure(.cookieReadFailed))
        await sut.testSignIn()
        guard case let .failed(text) = sut.signInTest else { return XCTFail("expected failure") }
        XCTAssertTrue(text.contains("Close Brave"))
        XCTAssertFalse(text.lowercased().contains("cookie"))
    }

    func test_browserNotInstalled_failsWithoutRunningTheProbe() async throws {
        let sut = try model(.edge, installed: nil, result: ok)
        await sut.testSignIn()
        XCTAssertEqual(
            sut.signInTest,
            .failed("Microsoft Edge isn't installed on this Mac, or hasn't been opened yet.")
        )
    }

    func test_otherFailures_doNotBlameTheInternetUnlessItIsTheNetwork() async throws {
        let unknown = try model(
            .chrome, installed: "Google/Chrome", result: .failure(.unknown(raw: "x"))
        )
        await unknown.testSignIn()
        XCTAssertEqual(unknown.signInTest, .failed("The test couldn't finish. Try again in a moment."))

        let offline = try model(.chrome, installed: "Google/Chrome", result: .failure(.network))
        await offline.testSignIn()
        XCTAssertTrue({
            if case let .failed(text) = offline.signInTest {
                return text.contains("no internet")
            }
            return false
        }())
    }

    func test_changingBrowser_clearsPreviousResult() async throws {
        let sut = try model(.brave, installed: "BraveSoftware/Brave-Browser", result: ok)
        await sut.testSignIn()
        sut.source = .chrome
        XCTAssertEqual(sut.signInTest, .idle)
    }

    func test_noBrowserSelected_noTestOffered() throws {
        let sut = try model(.none, installed: nil, result: ok)
        XCTAssertFalse(sut.canTestSignIn)
    }
}
