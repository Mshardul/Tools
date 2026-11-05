import Foundation

public enum UninstallResult: Equatable, Sendable {
    case removed
    case needsManualRemoval
    case failed
}

public struct UninstallJob: Sendable, Equatable {
    public var title: String?
    public var url: String
    public var state: JobState

    public init(title: String?, url: String, state: JobState) {
        self.title = title
        self.url = url
        self.state = state
    }
}

public enum UninstallCopy {
    public static let confirmTitle = "Remove MediaGrabber?"
    public static let confirmButton = "Remove"
    public static let manualTitle = "One step left"
    public static let manualMessage =
        "Everything MediaGrabber saved is gone. Move the app to the Trash yourself."
    public static let failedTitle = "Couldn't remove MediaGrabber"
    public static let failedMessage =
        "MediaGrabber couldn't remove what it saved, so the app is still installed."

    public static func message(activeTitles: [String]) -> String {
        let base = "Remove MediaGrabber and everything it saved? Your downloaded files stay where they are."
        guard !activeTitles.isEmpty else { return base }
        return base + " Still downloading: " + activeTitles.joined(separator: ", ") + "."
    }

    public static func activeTitles(jobs: [UninstallJob]) -> [String] {
        jobs.compactMap { job in
            guard isActive(job.state) else { return nil }
            let trimmed = job.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? job.url : trimmed
        }
    }

    public static func isActive(_ state: JobState) -> Bool {
        switch state {
        case .completed, .cancelled, .failed:
            false
        case .queued, .probing, .running, .paused, .waitingForNetwork, .cooldown:
            true
        }
    }
}

public protocol UninstallEffects: Sendable {
    func shutdown() async
    func deleteFootprint() throws
    func clearPreferences()
    func trashBundle() throws
}

public enum UninstallSequence {
    public static func run(_ effects: any UninstallEffects) async -> UninstallResult {
        await effects.shutdown()
        do {
            try effects.deleteFootprint()
        } catch {
            return .failed
        }
        effects.clearPreferences()
        do {
            try effects.trashBundle()
        } catch {
            return .needsManualRemoval
        }
        return .removed
    }
}
