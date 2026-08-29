@testable import GrabberKit
import XCTest

final class PreferencesTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "mg.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_defaults() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.defaultMaxHeight, 1080)
        XCTAssertEqual(prefs.defaultAudioCodec, .m4a)
        XCTAssertEqual(prefs.outputTemplate, "%(title)s.%(ext)s")
        XCTAssertEqual(prefs.maxAutoAttempts, 5)
        XCTAssertFalse(prefs.verboseLogging)
        XCTAssertEqual(prefs.skin, .aurora)
        XCTAssertEqual(prefs.palette, .auroraMintIris)
        XCTAssertTrue(prefs.defaultDestFolder.path.hasSuffix("/Downloads"))
    }

    func test_setPersistsToDefaults() {
        let prefs = Preferences(defaults: defaults)
        prefs.defaultMaxHeight = 720
        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.defaultMaxHeight, 720)
    }

    func test_maxAutoAttemptsClampedTo1through5() {
        let prefs = Preferences(defaults: defaults)
        prefs.maxAutoAttempts = 0
        XCTAssertEqual(prefs.maxAutoAttempts, 1)
        prefs.maxAutoAttempts = 9
        XCTAssertEqual(prefs.maxAutoAttempts, 5)
    }

    func test_lastUsedDefaultsToDefaultDest() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.lastUsedDestFolder, prefs.defaultDestFolder)
    }
}
