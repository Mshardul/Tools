import Foundation

extension DownloadEngine {
    // The row "Retry" button: resume keeps the .part and the attempt count; retry restarts
    // clean with the full auto-retry budget restored. Both re-enqueue at the tail with no
    // deferral — the user chose the moment.
    public func retry(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }),
              case let .failed(errorClass) = job.state,
              errorClass.presentation.offeredActions.contains(.retry)
        else {
            return
        }

        job.state = .queued
        job.finishedAt = nil
        job.progress = nil
        job.sizeBytes = nil
        job.integrityVerdict = nil
        job.actualQuality = nil
        move(job, toTail: true)

        if shouldResume(job, errorClass: errorClass) {
            logEvent(.jobResumed(id: id))
        } else {
            job.attempt = 0
            deletePartFiles(for: job)
            logEvent(.jobRetried(id: id))
        }

        bump()
        emitSnapshot()
        evaluateSchedule()
    }

    private func shouldResume(_ job: DownloadJob, errorClass: ErrorClass) -> Bool {
        let transient = switch errorClass {
        case .networkDown, .incomplete, .unknown: true
        default: false
        }
        return transient && usablePartFile(for: job) != nil
    }

    // A .part matching the job's title stem in the destination folder, non-empty.
    private func usablePartFile(for job: DownloadJob) -> URL? {
        guard let title = job.title else { return nil }
        let stem = Self.titleStem(title)
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: job.request.destFolder,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return entries.first { url in
            guard url.lastPathComponent.hasPrefix(stem), url.pathExtension == "part" else {
                return false
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size > 0
        }
    }
}
