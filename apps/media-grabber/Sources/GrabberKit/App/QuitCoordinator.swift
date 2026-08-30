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
        let message = if halt == .depMissing {
            "Downloads are paused — yt-dlp needs reinstalling. Quit anyway?"
        } else {
            "A download is still running. Quit anyway?"
        }
        return ConfirmationRequest(
            title: "Quit MediaGrabber?",
            message: message,
            confirmTitle: "Quit Anyway",
            cancelTitle: "Cancel",
            isDestructive: true
        )
    }
}
