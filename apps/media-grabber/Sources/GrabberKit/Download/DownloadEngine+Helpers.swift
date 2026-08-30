import Foundation

extension DownloadEngine {
    static func availableActions(for state: JobState) -> Set<RowAction> {
        switch state {
        case .queued:
            [.pause, .cancel, .forceStart, .remove, .openInBrowser]
        case .probing:
            [.cancel, .remove, .openInBrowser]
        case .running:
            [.pause, .cancel, .remove, .openInBrowser]
        case .paused:
            [.resume, .cancel, .remove, .openInBrowser]
        case .waitingForNetwork, .cooldown:
            [.cancel, .remove, .openInBrowser]
        case .completed:
            [.reveal, .remove, .openInBrowser]
        case .cancelled, .failed:
            [.remove, .openInBrowser]
        }
    }

    static func errorClass(for error: MetadataError) -> ErrorClass {
        switch error {
        case .network:
            .networkDown
        case .ytDlpMissing, .launchFailed:
            .depMissing
        case let .unknown(raw):
            .unknown(raw: raw)
        case .badURL, .unsupported, .unavailable, .malformedOutput:
            .unknown(raw: "\(error)")
        }
    }

    func deletePartFiles(for job: DownloadJob) {
        guard let title = job.title else { return }
        let stem = Self.titleStem(title)
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: job.request.destFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for url in entries where isPartFile(url, stem: stem) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func isPartFile(_ url: URL, stem: String) -> Bool {
        url.lastPathComponent.hasPrefix(stem) && url.pathExtension == "part"
    }

    func resolveOutputFiles(for job: DownloadJob) -> [URL] {
        guard let title = job.title else { return [] }
        let stem = Self.titleStem(title)
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: job.request.destFolder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .filter { $0.lastPathComponent.hasPrefix(stem) }
            .sorted { Self.modificationDate($0) > Self.modificationDate($1) }
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    // yt-dlp's %(title)s sanitiser strips path separators and control characters.
    private static func titleStem(_ title: String) -> String {
        String(title.unicodeScalars.filter { scalar in
            scalar != "/" && !CharacterSet.controlCharacters.contains(scalar)
        })
    }
}
