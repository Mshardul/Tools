@testable import GrabberKit
import XCTest

final class ReleaseGateTests: XCTestCase {
    func test_footprintRemovalLeavesDownloadsAlone() throws {
        let home = temporaryHome()
        let fileManager = FileManager.default
        for directory in AppFootprint.directories(in: home) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let marker = directory.appendingPathComponent("marker.txt")
            try Data("x".utf8).write(to: marker)
        }
        let preferences = AppFootprint.preferenceFile(in: home)
        try fileManager.createDirectory(
            at: preferences.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("prefs".utf8).write(to: preferences)
        let downloads = home.appendingPathComponent("Downloads/video.mp4")
        try fileManager.createDirectory(
            at: downloads.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("media".utf8).write(to: downloads)
        let otherApp = home.appendingPathComponent("Library/Application Support/OtherApp/keep.txt")
        try fileManager.createDirectory(
            at: otherApp.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(to: otherApp)

        try AppFootprint.remove(in: home)

        for directory in AppFootprint.directories(in: home) {
            XCTAssertFalse(fileManager.fileExists(atPath: directory.path))
        }
        XCTAssertFalse(fileManager.fileExists(atPath: AppFootprint.preferenceFile(in: home).path))
        XCTAssertTrue(fileManager.fileExists(atPath: downloads.path))
        XCTAssertTrue(fileManager.fileExists(atPath: otherApp.path))
    }

    func test_installLocation() {
        let home = URL(fileURLWithPath: "/Users/ada", isDirectory: true)
        XCTAssertTrue(InstallLocation.canReplaceItself(
            bundleURL: URL(fileURLWithPath: "/Applications/MediaGrabber.app"),
            home: home
        ))
        XCTAssertTrue(InstallLocation.canReplaceItself(
            bundleURL: home.appendingPathComponent("Applications/MediaGrabber.app"),
            home: home
        ))
        XCTAssertFalse(InstallLocation.canReplaceItself(
            bundleURL: URL(fileURLWithPath: "/private/var/folders/ab/AppTranslocation/cd/d/MediaGrabber.app"),
            home: home
        ))
        XCTAssertFalse(InstallLocation.canReplaceItself(
            bundleURL: URL(fileURLWithPath: "/Volumes/MediaGrabber/MediaGrabber.app"),
            home: home
        ))
    }

    func test_moveIntoHomeApplicationsWhenSystemFolderIsLocked() throws {
        let root = temporaryHome()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let source = root.appendingPathComponent("dmg/MediaGrabber.app", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("app".utf8).write(to: source.appendingPathComponent("Info.plist"))

        let destination = InstallLocation.destination(
            bundleURL: source,
            home: home,
            systemApplicationsWritable: false
        )
        try InstallLocation.move(bundleURL: source, to: destination)

        XCTAssertEqual(
            destination.path,
            home.appendingPathComponent("Applications/MediaGrabber.app").path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Info.plist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func test_moveRefusesToReplaceAnExistingCopy() throws {
        let root = temporaryHome()
        let source = root.appendingPathComponent("old/MediaGrabber.app", isDirectory: true)
        let destination = root.appendingPathComponent("Applications/MediaGrabber.app", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        XCTAssertThrowsError(try InstallLocation.move(bundleURL: source, to: destination)) { error in
            XCTAssertEqual(error as? InstallMoveError, .destinationExists)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func test_uninstallNamesOnlyActiveDownloads() {
        let titles = UninstallCopy.activeTitles(jobs: [
            UninstallJob(title: "Live", url: "https://example.com/live", state: .running),
            UninstallJob(title: "  ", url: "https://example.com/blank", state: .queued),
            UninstallJob(title: "Saved", url: "https://example.com/saved", state: .completed),
            UninstallJob(title: nil, url: "https://example.com/failed", state: .failed(.private))
        ])
        XCTAssertEqual(titles, ["Live", "https://example.com/blank"])
        XCTAssertTrue(UninstallCopy.message(activeTitles: []).contains("downloaded files stay"))
        XCTAssertTrue(UninstallCopy.message(activeTitles: titles).contains("Still downloading: Live"))
    }

    func test_uninstallOrderSkipsTrashQuitWhenDeleteFails() async {
        let effects = RecordingEffects(deleteError: CocoaError(.fileWriteUnknown))
        let result = await UninstallSequence.run(effects)
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(effects.steps, [.shutdown, .deleteFootprint])
    }

    func test_uninstallOrderStopsAfterAFailedTrash() async {
        let effects = RecordingEffects(trashError: CocoaError(.fileWriteNoPermission))
        let result = await UninstallSequence.run(effects)
        XCTAssertEqual(result, .needsManualRemoval)
        XCTAssertEqual(effects.steps, [.shutdown, .deleteFootprint, .clearPreferences, .trashBundle])
    }

    func test_uninstallOrderRemovesThenWouldQuit() async {
        let effects = RecordingEffects()
        let result = await UninstallSequence.run(effects)
        XCTAssertEqual(result, .removed)
        XCTAssertEqual(effects.steps, [.shutdown, .deleteFootprint, .clearPreferences, .trashBundle])
    }

    private func temporaryHome() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mg-footprint-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private final class RecordingEffects: UninstallEffects, @unchecked Sendable {
    enum Step: Equatable {
        case shutdown, deleteFootprint, clearPreferences, trashBundle
    }

    private let box = Locked(State())
    private let deleteError: Error?
    private let trashError: Error?

    private struct State {
        var steps: [Step] = []
    }

    init(deleteError: Error? = nil, trashError: Error? = nil) {
        self.deleteError = deleteError
        self.trashError = trashError
    }

    var steps: [Step] {
        box.read { $0.steps }
    }

    func shutdown() async {
        box.mutate { $0.steps.append(.shutdown) }
    }

    func deleteFootprint() throws {
        box.mutate { $0.steps.append(.deleteFootprint) }
        if let deleteError {
            throw deleteError
        }
    }

    func clearPreferences() {
        box.mutate { $0.steps.append(.clearPreferences) }
    }

    func trashBundle() throws {
        box.mutate { $0.steps.append(.trashBundle) }
        if let trashError {
            throw trashError
        }
    }
}
