import Foundation
import TestSupport

final class PasscodeCallLog: @unchecked Sendable {
    private struct State {
        var setCalls: [(passcode: String, url: String)] = []
        var retryCalls: [(id: UUID, passcode: String)] = []
    }

    private let box = LockedBox(State())

    var setCalls: [(passcode: String, url: String)] {
        box.read { $0.setCalls }
    }

    var retryCalls: [(id: UUID, passcode: String)] {
        box.read { $0.retryCalls }
    }

    func recordSet(_ passcode: String, for url: String) {
        box.mutate { $0.setCalls.append((passcode, url)) }
    }

    func recordRetry(_ id: UUID, passcode: String) {
        box.mutate { $0.retryCalls.append((id, passcode)) }
    }
}
