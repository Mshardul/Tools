@testable import GrabberKit
@testable import MediaGrabber
import XCTest

final class RunwaySeedTests: XCTestCase {
    private func prefs() -> Preferences {
        let defaults = UserDefaults(suiteName: "mg.seed.\(UUID().uuidString)") ?? .standard
        return Preferences(defaults: defaults)
    }

    func test_fallsBackToDefaults() {
        let seed = runwaySeed(from: prefs())
        XCTAssertEqual(seed.mediaType, .video)
        XCTAssertEqual(seed.videoHeight, 1080)
        XCTAssertEqual(seed.audioFormat, .m4a)
    }

    func test_prefersLastSelected() {
        let stored = prefs()
        stored.lastMediaType = .audio
        stored.lastVideoHeight = .max
        stored.lastAudioFormat = .mp3
        let seed = runwaySeed(from: stored)
        XCTAssertEqual(seed.mediaType, .audio)
        XCTAssertEqual(seed.videoHeight, .max)
        XCTAssertEqual(seed.audioFormat, .mp3)
    }
}
