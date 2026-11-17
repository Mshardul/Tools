import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class AppModelUpdatingTests: XCTestCase {
    private final class FakeAppUpdating: AppUpdating {
        private(set) var checks = 0
        private(set) var automaticChecks: [Bool] = []

        func start(automaticChecks _: Bool) {}

        func setAutomaticChecks(_ enabled: Bool) {
            automaticChecks.append(enabled)
        }

        func checkForUpdates() {
            checks += 1
        }
    }

    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var logDirectory: URL!

    override func setUp() async throws {
        suiteName = "mg.updating.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-updating-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logDirectory)
    }

    private func makeModel(bundlePath: String, updater: FakeAppUpdating) -> AppModel {
        AppModelTestHelpers.makeModel(
            defaults: defaults,
            logDirectory: logDirectory,
            appUpdating: updater,
            bundleURL: URL(fileURLWithPath: bundlePath),
            homeURL: URL(fileURLWithPath: "/Users/ada", isDirectory: true)
        )
    }

    func test_checkForUpdates_fromApplications_asksTheUpdater() {
        let updater = FakeAppUpdating()
        makeModel(bundlePath: "/Applications/MediaGrabber.app", updater: updater).checkForUpdates()
        XCTAssertEqual(updater.checks, 1)
    }

    func test_checkForUpdates_fromDownloads_neverAsksTheUpdater() {
        let updater = FakeAppUpdating()
        let model = makeModel(bundlePath: "/Users/ada/Downloads/MediaGrabber.app", updater: updater)
        model.checkForUpdates()
        XCTAssertEqual(updater.checks, 0)
        XCTAssertFalse(model.canReplaceItself)
    }

    func test_automaticChecksToggle_reachesTheUpdater() {
        let updater = FakeAppUpdating()
        let model = makeModel(bundlePath: "/Applications/MediaGrabber.app", updater: updater)
        model.setAutomaticUpdateChecks(false)
        model.setAutomaticUpdateChecks(true)
        XCTAssertEqual(updater.automaticChecks, [false, true])
    }

    func test_blockedMessage_tellsThePersonToMoveTheApp() {
        XCTAssertTrue(InstallLocation.updateBlockedMessage.contains("Applications"))
    }

    func test_openNotices_opensTheBundledLicensesFile() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-notices-\(UUID().uuidString)")
        let resources = folder.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("licenses".utf8).write(to: resources.appendingPathComponent("NOTICES.md"))
        defer { try? FileManager.default.removeItem(at: folder) }
        let opener = FakeOpenURLSink()
        let model = AppModelTestHelpers.makeModel(defaults: defaults, logDirectory: logDirectory, openURLSink: opener)
        let bundle = try XCTUnwrap(Bundle(url: folder))
        model.openNotices(in: bundle)
        XCTAssertEqual(opener.opened.map(\.lastPathComponent), ["NOTICES.md"])
    }
}
