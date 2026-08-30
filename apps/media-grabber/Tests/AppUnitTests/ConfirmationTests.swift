@testable import GrabberKit
@testable import MediaGrabber
import SwiftUI
import XCTest

@MainActor
final class ConfirmationTests: XCTestCase {
    private final class MemorySuppression: SuppressionStore {
        var keys: Set<String> = []
        func isSuppressed(_ key: String) -> Bool {
            keys.contains(key)
        }

        func setSuppressed(_ key: String) {
            keys.insert(key)
        }
    }

    private func makeModel(suppression: SuppressionStore) -> AppModel {
        let defaults = UserDefaults(suiteName: "mg.confirm.\(UUID().uuidString)")!
        return AppModel(
            engine: FakeEngine(),
            probe: FakeMetadataProbe(.failure(.malformedOutput)),
            installer: OnboardingInstaller(
                probe: FakeEnvironmentProbe(ready: true),
                runner: NullRunner()
            ),
            prefs: Preferences(defaults: defaults),
            log: LogWriter(directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mg-confirm-\(UUID().uuidString)")),
            envProbe: FakeEnvironmentProbe(ready: true),
            suppression: suppression
        )
    }

    private func request(
        cancelTitle: String? = "Cancel",
        destructive: Bool = false,
        suppressionKey: String? = nil
    ) -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Are you sure?",
            message: "This affects your downloads.",
            confirmTitle: "Yes",
            cancelTitle: cancelTitle,
            isDestructive: destructive,
            suppressionKey: suppressionKey
        )
    }

    func test_confirmResolvesToUserChoice() async {
        let model = makeModel(suppression: MemorySuppression())
        let task = Task { await model.confirm(request()) }
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertNotNil(model.pendingConfirmation)
        model.resolveConfirmation(true, suppressFutures: false)
        let result = await task.value
        XCTAssertTrue(result)
        XCTAssertNil(model.pendingConfirmation)
    }

    func test_confirmResolvesFalse() async {
        let model = makeModel(suppression: MemorySuppression())
        let task = Task { await model.confirm(request()) }
        try? await Task.sleep(for: .milliseconds(20))
        model.resolveConfirmation(false, suppressFutures: false)
        let result = await task.value
        XCTAssertFalse(result)
    }

    func test_suppressedKeyReturnsTrueWithoutShowing() async {
        let suppression = MemorySuppression()
        suppression.keys.insert("dupe")
        let model = makeModel(suppression: suppression)

        let result = await model.confirm(request(suppressionKey: "dupe"))
        XCTAssertTrue(result)
        XCTAssertNil(model.pendingConfirmation)
    }

    func test_confirmWithSuppressCheckbox_persistsSuppression() async {
        let suppression = MemorySuppression()
        let model = makeModel(suppression: suppression)
        let task = Task { await model.confirm(request(suppressionKey: "dupe")) }
        try? await Task.sleep(for: .milliseconds(20))
        model.resolveConfirmation(true, suppressFutures: true)
        _ = await task.value

        XCTAssertTrue(suppression.isSuppressed("dupe"))
    }

    func test_noticeMode_showsOneButton() {
        XCTAssertFalse(request(cancelTitle: nil).showsCancel)
        XCTAssertTrue(request(cancelTitle: "Cancel").showsCancel)
    }

    func test_dialogBuildsInBothSkins() {
        for skin in [SkinKind.tapeDeck, .aurora] {
            _ = ResolvedTheme(skinKind: skin, paletteKind: .auroraMintIris)
            let dialog = ConfirmationDialog(request: request(destructive: true)) { _, _ in }
            _ = dialog.body
        }
    }

    func test_hostReportsNoticeMode() {
        let notice = ConfirmationDialog(request: request(cancelTitle: nil)) { _, _ in }
        XCTAssertFalse(notice.showsCancel)
        let choice = ConfirmationDialog(request: request()) { _, _ in }
        XCTAssertTrue(choice.showsCancel)
    }
}

private struct NullRunner: ProcessRunning {
    func run(_: ProcessLaunch) -> ProcessExecution {
        let (stream, continuation) = AsyncStream<ProcessLine>.makeStream()
        continuation.finish()
        return ProcessExecution(lines: stream) { ProcessResult(exitCode: 0, wasCancelled: false) }
    }
}
