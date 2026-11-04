import Foundation
@testable import MediaGrabber

@MainActor
final class FakeOpenURLSink: OpenURLSink {
    private(set) var opened: [URL] = []

    nonisolated init() {}

    func open(_ url: URL) {
        opened.append(url)
    }
}
