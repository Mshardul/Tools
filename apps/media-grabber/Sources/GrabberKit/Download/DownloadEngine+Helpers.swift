import Foundation

extension DownloadEngine {
    static func availableActions(
        for state: JobState,
        isImmediatelySchedulable: Bool = false,
        signInAdvice: SignInAdvice = .none,
        offerSiteSignIn: Bool = false
    ) -> Set<RowAction> {
        switch state {
        case .queued:
            isImmediatelySchedulable
                ? [.cancel, .remove, .openInBrowser]
                : [.cancel, .forceStart, .remove, .openInBrowser]
        case .probing:
            [.cancel, .remove, .openInBrowser]
        case .running:
            [.pause, .cancel, .remove, .openInBrowser, .showLog]
        case .paused:
            [.resume, .cancel, .remove, .openInBrowser, .showLog]
        case .waitingForNetwork:
            [.cancel, .remove, .openInBrowser, .showLog]
        case .cooldown:
            [.forceStart, .cancel, .remove, .openInBrowser, .showLog]
        case .completed:
            [.reveal, .remove, .openInBrowser, .showLog]
        case .cancelled:
            [.retry, .remove, .openInBrowser, .showLog]
        case let .failed(errorClass):
            errorClass.presentation.offeredActions
                .union(signInAdvice == .suggest || offerSiteSignIn ? [.retryWithCookies] : [])
                .union([.remove, .openInBrowser, .showLog])
        }
    }

    static func errorClass(for error: MetadataError) -> ErrorClass {
        if let matching = error.matchingErrorClass {
            return matching
        }
        return switch error {
        case .network:
            .networkDown
        case .ytDlpMissing, .launchFailed:
            .depMissing
        case let .unknown(raw):
            .unknown(raw: raw)
        case .hostBlocked:
            .rateLimited()
        default:
            .unknown(raw: "\(error)")
        }
    }

    static func resolvedExitClass(
        kind: DownloadKind,
        lastError: ErrorClass?,
        sawAudioOnly: Bool,
        exitCode: Int? = nil
    ) -> ErrorClass {
        if case .sabrGated = lastError {
            return .sabrGated
        }
        if sawAudioOnly, isVideoKind(kind), isReplaceable(lastError) {
            return .formatsMissing
        }
        if let lastError {
            return lastError
        }
        if let exitCode {
            return .unknown(raw: "yt-dlp exited \(exitCode)")
        }
        return .unknown(raw: "yt-dlp exited")
    }

    private static func isVideoKind(_ kind: DownloadKind) -> Bool {
        if case .video = kind {
            return true
        }
        return false
    }

    private static func isReplaceable(_ lastError: ErrorClass?) -> Bool {
        guard let lastError else { return true }
        if case .unknown = lastError {
            return true
        }
        return false
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
        let byTitle = outputFilesMatchingTitle(for: job)
        if !byTitle.isEmpty {
            return byTitle
        }
        return newestNonPartFiles(in: job.request.destFolder, since: job.startedAt ?? job.addedAt)
    }

    func finalizedOutputFiles(for job: DownloadJob) -> [URL] {
        let fileManager = FileManager.default
        let captured = job.capturedOutputPaths.filter {
            fileManager.fileExists(atPath: $0.path)
        }
        if let last = captured.last {
            return [last]
        }
        return resolveOutputFiles(for: job)
    }

    private func outputFilesMatchingTitle(for job: DownloadJob) -> [URL] {
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

    private func newestNonPartFiles(in folder: URL, since: Date) -> [URL] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let candidates = entries.filter { url in
            url.pathExtension != "part"
                && Self.modificationDate(url) >= since.addingTimeInterval(-2)
        }
        guard let newest = candidates.max(by: {
            Self.modificationDate($0) < Self.modificationDate($1)
        }) else {
            return []
        }
        return [newest]
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    func publishRestoredJobs() -> Bool {
        recoverDisplayFacts()
        let hasJobs = !jobs.isEmpty
        if hasJobs {
            bump()
            emitSnapshot()
        }
        evaluateSchedule()
        scheduleQualityProbe()
        return hasJobs
    }

    // Resolution for saves that predate actualQuality, after the table already has size and progress.
    func scheduleQualityProbe() {
        guard dependencies.ffprobeURL != nil, jobs.contains(where: Self.needsQualityProbe) else { return }
        Task { await probeMissingQuality() }
    }

    // Saves from before size and resolution were stored: recover them from the finished file.
    func recoverDisplayFacts() {
        for job in jobs where job.state == .completed {
            fillMissingOutput(job)
            fillMissingSize(job)
            job.progress = Self.completedProgress(for: job)
        }
    }

    func probeMissingQuality() async {
        let pending = jobs.filter(Self.needsQualityProbe)
        guard !pending.isEmpty else { return }
        var changed = false
        for job in pending {
            guard let quality = await probedQuality(for: job) else { continue }
            guard jobs.contains(where: { $0.id == job.id }), job.actualQuality == nil else { continue }
            job.actualQuality = quality
            changed = true
        }
        guard changed else { return }
        bump()
        emitSnapshot()
    }

    static func needsQualityProbe(_ job: DownloadJob) -> Bool {
        guard job.actualQuality == nil, job.state == .completed else { return false }
        if case .video = job.request.kind {
            return true
        }
        return false
    }

    private func fillMissingOutput(_ job: DownloadJob) {
        guard job.outputFiles.isEmpty, let file = recoveredMediaFile(for: job) else { return }
        job.outputFiles = [file]
    }

    private func fillMissingSize(_ job: DownloadJob) {
        guard job.sizeBytes == nil, let bytes = Self.measuredBytes(job.outputFiles) else { return }
        job.sizeBytes = bytes
    }

    private static func completedProgress(for job: DownloadJob) -> Progress {
        Progress(
            fraction: 1,
            downloadedBytes: job.sizeBytes ?? job.progress?.downloadedBytes ?? 0,
            totalBytes: job.sizeBytes ?? job.progress?.totalBytes
        )
    }

    private func probedQuality(for job: DownloadJob) async -> String? {
        guard let file = recoveredMediaFile(for: job) else { return nil }
        let result = await IntegrityCheck(
            runner: dependencies.runner,
            ffprobeURL: dependencies.ffprobeURL,
            isExecutable: dependencies.ffprobeIsExecutable
        ).verify(file: file, expectedDurationSeconds: job.durationSeconds)
        return result.actualQuality
    }

    func recoveredMediaFile(for job: DownloadJob) -> URL? {
        let seeded = job.outputFiles.filter(Self.isMediaFile)
        let pool = seeded.isEmpty
            ? resolveOutputFiles(for: job).filter(Self.isMediaFile)
            : seeded
        return pool.max { Self.fileByteCount($0) < Self.fileByteCount($1) }
    }

    static func measuredBytes(_ urls: [URL]) -> Int64? {
        let total = urls.reduce(Int64(0)) { $0 + fileByteCount($1) }
        return total > 0 ? total : nil
    }

    private static let mediaExtensions: Set<String> = [
        "mp4", "m4v", "mkv", "webm", "mov", "m4a", "mp3", "opus", "ogg", "flac", "wav", "aac"
    ]

    private static func isMediaFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard mediaExtensions.contains(ext) else { return false }
        return (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    private static func fileByteCount(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    // yt-dlp's %(title)s sanitiser strips path separators and control characters.
    static func titleStem(_ title: String) -> String {
        String(title.unicodeScalars.filter { scalar in
            scalar != "/" && !CharacterSet.controlCharacters.contains(scalar)
        })
    }
}
