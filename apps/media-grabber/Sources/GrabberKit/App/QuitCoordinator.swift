import Foundation

public final class QuitCoordinator: Sendable {
    private let engine: any DownloadEngineProtocol
    private let persistence: any QueuePersisting
    private let confirmer: any Confirming

    public init(
        engine: any DownloadEngineProtocol,
        persistence: any QueuePersisting,
        confirmer: any Confirming
    ) {
        self.engine = engine
        self.persistence = persistence
        self.confirmer = confirmer
    }

    public func requestTerminate() async -> Bool {
        let snapshot = await engine.currentSnapshot()
        let hasActive = await engine.hasActiveJobs()
        if hasActive || snapshot.queueHalt != nil {
            let confirmed = await confirmer.confirm(Self.quitConfirmation(halt: snapshot.queueHalt))
            if !confirmed {
                return false
            }
        }

        await persistence.flushNow()
        await engine.shutdown()
        return true
    }

    public static func quitConfirmation(halt: QueueHaltReason?) -> ConfirmationRequest {
        let message = quitMessage(for: halt)
        return ConfirmationRequest(
            title: "Quit MediaGrabber?",
            message: message,
            confirmTitle: "Quit Anyway",
            cancelTitle: "Cancel",
            isDestructive: true
        )
    }

    private static func quitMessage(for halt: QueueHaltReason?) -> String {
        switch halt {
        case .depMissing:
            "Downloads are paused — yt-dlp needs reinstalling. Quit anyway?"
        case .networkDown:
            "Downloads are paused — no internet connection. They'll resume when you're back online. Quit anyway?"
        case .circuitOpen:
            "Downloads are paused — a site is rate-limiting you. Quit anyway?"
        case nil:
            "A download is still running. Quit anyway?"
        }
    }
}
