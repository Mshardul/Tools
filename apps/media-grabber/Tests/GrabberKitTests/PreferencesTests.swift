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
        XCTAssertEqual(prefs.defaultVideoHeight, 1080)
        XCTAssertEqual(prefs.defaultAudioFormat, .m4a)
        XCTAssertEqual(prefs.filenameTemplate, "%(title)s.%(ext)s")
        XCTAssertEqual(prefs.maxAutoRetries, 5)
        XCTAssertFalse(prefs.verboseLogging)
        XCTAssertEqual(prefs.theme, .aurora)
        XCTAssertEqual(prefs.palette, .auroraMintIris)
        XCTAssertTrue(prefs.defaultDownloadFolder.path.hasSuffix("/Downloads"))
    }

    func test_setPersistsToDefaults() {
        let prefs = Preferences(defaults: defaults)
        prefs.defaultVideoHeight = 720
        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.defaultVideoHeight, 720)
    }

    func test_maxAutoRetriesClampedTo1through5() {
        let prefs = Preferences(defaults: defaults)
        prefs.maxAutoRetries = 0
        XCTAssertEqual(prefs.maxAutoRetries, 1)
        prefs.maxAutoRetries = 9
        XCTAssertEqual(prefs.maxAutoRetries, 5)
    }

    func test_lastUsedDefaultsToDefaultDownloadFolder() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.lastUsedDownloadFolder, prefs.defaultDownloadFolder)
    }

    func test_renamedKeys_oldKeysIgnored() {
        defaults.set(480, forKey: "mg.defaultMaxHeight")
        XCTAssertEqual(Preferences(defaults: defaults).defaultVideoHeight, 1080)
    }

    func test_newFieldDefaults() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.detectClipboardLinks)
        XCTAssertNil(prefs.proxyURL)
        XCTAssertFalse(prefs.forceIPv4)
        XCTAssertEqual(prefs.speedLimitKBps, 0)
        XCTAssertNil(prefs.lastVideoHeight)
        XCTAssertNil(prefs.lastMediaType)
        XCTAssertNil(prefs.lastAudioFormat)
    }

    func test_proxyURL_trimAndEmptyToNil() {
        let prefs = Preferences(defaults: defaults)
        prefs.proxyURL = "  "
        XCTAssertNil(Preferences(defaults: defaults).proxyURL)
        prefs.proxyURL = " http://h:1 "
        XCTAssertEqual(Preferences(defaults: defaults).proxyURL, "http://h:1")
    }

    func test_speedLimitKBps_clamp() {
        let prefs = Preferences(defaults: defaults)
        prefs.speedLimitKBps = -5
        XCTAssertEqual(prefs.speedLimitKBps, 0)
        prefs.speedLimitKBps = 999_999
        XCTAssertEqual(prefs.speedLimitKBps, 100_000)
    }

    func test_lastSelected_roundTripIncludingIntMax() {
        let prefs = Preferences(defaults: defaults)
        prefs.lastVideoHeight = .max
        prefs.lastMediaType = .audio
        prefs.lastAudioFormat = .mp3
        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.lastVideoHeight, .max)
        XCTAssertEqual(reloaded.lastMediaType, .audio)
        XCTAssertEqual(reloaded.lastAudioFormat, .mp3)
    }

    func test_cookiesFromBrowser_defaultsToNone() {
        XCTAssertEqual(Preferences(defaults: defaults).cookiesFromBrowser, .none)
    }

    func test_cookiesFromBrowser_roundTripsFirefoxProfile() {
        Preferences(defaults: defaults).cookiesFromBrowser = .firefox(profile: "work")
        XCTAssertEqual(
            Preferences(defaults: defaults).cookiesFromBrowser,
            .firefox(profile: "work")
        )
    }

    func test_cookiesFromBrowser_malformedData_decodesToNone() {
        defaults.set(Data("not json".utf8), forKey: "mg.cookiesFromBrowser")
        XCTAssertEqual(Preferences(defaults: defaults).cookiesFromBrowser, .none)
    }

    func test_resetToDefaults_clearsCookiesFromBrowser() {
        let prefs = Preferences(defaults: defaults)
        prefs.cookiesFromBrowser = .safari
        prefs.resetToDefaults()
        XCTAssertEqual(prefs.cookiesFromBrowser, .none)
    }

    func test_resetToDefaults_restoresEveryField() {
        let prefs = Preferences(defaults: defaults)
        prefs.defaultVideoHeight = 480
        prefs.theme = .tapeDeck
        prefs.palette = .tapeDeckC
        prefs.forceIPv4 = true
        prefs.proxyURL = "http://h:1"
        prefs.speedLimitKBps = 500
        prefs.detectClipboardLinks = false
        prefs.maxConcurrentDownloads = 6
        prefs.filenameTemplate = "%(id)s.%(ext)s"
        prefs.lastMediaType = .audio
        prefs.resetToDefaults()
        XCTAssertEqual(prefs.defaultVideoHeight, 1080)
        XCTAssertEqual(prefs.theme, .aurora)
        XCTAssertEqual(prefs.palette, .auroraMintIris)
        XCTAssertFalse(prefs.forceIPv4)
        XCTAssertNil(prefs.proxyURL)
        XCTAssertEqual(prefs.speedLimitKBps, 0)
        XCTAssertTrue(prefs.detectClipboardLinks)
        XCTAssertEqual(prefs.maxConcurrentDownloads, 3)
        XCTAssertEqual(prefs.filenameTemplate, "%(title)s.%(ext)s")
        XCTAssertNil(prefs.lastMediaType)
    }
}
