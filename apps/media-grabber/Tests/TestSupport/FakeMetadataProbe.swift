import Foundation
@testable import GrabberKit

final class FakeMetadataProbe: MetadataProbing, @unchecked Sendable {
    typealias Outcome = Result<MediaMetadata, MetadataError>

    private struct State {
        var results: [String: Outcome] = [:]
        var fallback: Outcome
        var probedURLs: [String] = []
        var perProbeDelay: Duration = .zero
    }

    private let box: LockedBox<State>

    init(default fallback: Outcome = .failure(.malformedOutput)) {
        box = LockedBox(State(fallback: fallback))
    }

    var probedURLs: [String] {
        box.read { $0.probedURLs }
    }

    var wasProbed: Bool {
        box.read { !$0.probedURLs.isEmpty }
    }

    var perProbeDelay: Duration {
        get { box.read { $0.perProbeDelay } }
        set { box.mutate { $0.perProbeDelay = newValue } }
    }

    func result(_ result: Outcome, forURL url: String) {
        box.mutate { $0.results[url] = result }
    }

    func result(_ result: Outcome) {
        box.mutate { $0.fallback = result }
    }

    static func success(
        title: String,
        durationSeconds: Int? = nil,
        sourceURL: String = ""
    ) -> Outcome {
        .success(MediaMetadata(
            title: title,
            durationSeconds: durationSeconds,
            isPlaylist: false,
            sourceURL: sourceURL
        ))
    }

    func probe(_ url: String) async -> Outcome {
        let (result, delay) = box.mutate { state -> (Outcome, Duration) in
            state.probedURLs.append(url)
            return (state.results[url] ?? state.fallback, state.perProbeDelay)
        }
        if delay != .zero {
            try? await Task.sleep(for: delay)
        }
        return result
    }
}
