import Foundation
@testable import GrabberKit

public final class FakeYtDlpUpdater: YtDlpUpdating, @unchecked Sendable {
    private let box: LockedBox<YtDlpUpdateResult>

    public init(result: YtDlpUpdateResult = .success(newVersion: "2026.08.19")) {
        box = LockedBox(result)
    }

    public func setResult(_ result: YtDlpUpdateResult) {
        box.mutate { $0 = result }
    }

    public func reinstallToMinimum() async -> YtDlpUpdateResult {
        box.read { $0 }
    }
}
