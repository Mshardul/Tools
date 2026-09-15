import Foundation
@testable import GrabberKit
@testable import MediaGrabber
import TestSupport
import XCTest

@MainActor
private final class FakeIncomingLinkHomeForDiagnostics: IncomingLinkHome {
    var isHomeBusy = false
    var detectClipboardLinks = true
    var appliedURLs: [URL] = []

    func applyIncomingURL(_ url: URL) async {
        appliedURLs.append(url)
    }

    func confirm(_: ConfirmationRequest) async -> Bool {
        false
    }
}

@MainActor
final class DiagnosticsPaneTests: XCTestCase {
    final class SpySharePresenter: SharePresenting {
        var sharedData: Data?
        var sharedFilename: String?
        func share(data: Data, filename: String) {
            sharedData = data
            sharedFilename = filename
        }
    }

    func test_runCheck_updatesReportWithCanaryResult() async {
        let fakeMetadataProbe = FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny"))
        let model = DiagnosticsPaneModel(
            metadataProbe: fakeMetadataProbe,
            environmentProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            ytDlpUpdater: FakeYtDlpUpdater(),
            sharePresenter: SpySharePresenter()
        )
        await model.runCheck()
        XCTAssertEqual(model.canaryResult, .passed)
    }

    func test_runCheck_failedProbe_marksFailed() async {
        let model = DiagnosticsPaneModel(
            metadataProbe: FakeMetadataProbe(default: .failure(.network)),
            environmentProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            ytDlpUpdater: FakeYtDlpUpdater(),
            sharePresenter: SpySharePresenter()
        )
        await model.runCheck()
        XCTAssertEqual(model.canaryResult, .failed)
    }

    func test_runCheck_setsLastRunAt() async {
        let model = DiagnosticsPaneModel(
            metadataProbe: FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny")),
            environmentProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            ytDlpUpdater: FakeYtDlpUpdater(),
            sharePresenter: SpySharePresenter()
        )
        XCTAssertNil(model.lastRunAt)
        await model.runCheck()
        XCTAssertNotNil(model.lastRunAt)
    }

    func test_shareBundle_callsSharePresenterWithZipData() async {
        let spy = SpySharePresenter()
        let model = DiagnosticsPaneModel(
            metadataProbe: FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny")),
            environmentProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            ytDlpUpdater: FakeYtDlpUpdater(),
            sharePresenter: spy
        )
        await model.runCheck()
        model.shareDiagnosticBundle()
        XCTAssertNotNil(spy.sharedData)
        XCTAssertEqual(spy.sharedFilename, "MediaGrabber-Diagnostics.zip")
    }

    func test_copyReport_marksAppPasteboardWrite() async {
        var markedStrings: [String] = []
        let model = DiagnosticsPaneModel(
            metadataProbe: FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny")),
            environmentProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            ytDlpUpdater: FakeYtDlpUpdater(),
            sharePresenter: SpySharePresenter(),
            pasteboardMarker: { markedStrings.append($0) }
        )
        await model.runCheck()
        model.copyReport()
        XCTAssertEqual(markedStrings, [model.reportText])
    }

    func test_copyReport_wiredToRealIncomingLinkController_ignoresSelfWrite() async {
        // Proves the production call site (pasteboardMarker: controller.markAppPasteboardWrite)
        // type-checks and drives the real controller: copyReport's mark of reportText means a
        // later external write of that same text is treated as our own and not re-ingested, per
        // IncomingLinkControllerTests.test_clipboard_selfWrite_ignored's contract.
        let home = FakeIncomingLinkHomeForDiagnostics()
        let pasteboard = FakePasteboard()
        let controller = IncomingLinkController(home: home, pasteboard: pasteboard)
        let model = DiagnosticsPaneModel(
            metadataProbe: FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny")),
            environmentProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            ytDlpUpdater: FakeYtDlpUpdater(),
            sharePresenter: SpySharePresenter(),
            pasteboardMarker: controller.markAppPasteboardWrite
        )
        await model.runCheck()
        model.copyReport()
        pasteboard.writeString(model.reportText)
        await controller.pollPasteboard()
        XCTAssertTrue(home.appliedURLs.isEmpty)
    }

    func test_reinstallYtDlp_rerunsCheckAfterUpdate() async {
        let updater = FakeYtDlpUpdater()
        let model = DiagnosticsPaneModel(
            metadataProbe: FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny")),
            environmentProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            ytDlpUpdater: updater,
            sharePresenter: SpySharePresenter()
        )
        await model.reinstallYtDlp()
        XCTAssertEqual(model.canaryResult, .passed)
    }
}
