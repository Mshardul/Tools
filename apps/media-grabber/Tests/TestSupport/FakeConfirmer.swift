import Foundation
import GrabberKit

public final class FakeConfirmer: Confirming, @unchecked Sendable {
    private struct State {
        var answers: [Bool] = []
        var seen: [ConfirmationRequest] = []
        var fallback = true
    }

    private let box = LockedBox(State())

    public init(answering fallback: Bool = true) {
        box.mutate { $0.fallback = fallback }
    }

    public func queue(_ answers: Bool...) {
        box.mutate { $0.answers.append(contentsOf: answers) }
    }

    public var seenRequests: [ConfirmationRequest] {
        box.read { $0.seen }
    }

    public func confirm(_ request: ConfirmationRequest) async -> Bool {
        box.mutate { state in
            state.seen.append(request)
            if state.answers.isEmpty {
                return state.fallback
            }
            return state.answers.removeFirst()
        }
    }
}
