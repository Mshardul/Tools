import Foundation
import GrabberKit
import Observation

@MainActor
@Observable
final class RowModel: Identifiable {
    let id: UUID

    private(set) var snapshot: JobSnapshot

    // Cached display strings — recomputed on patch only when their source field changed.
    private(set) var statusText = ""
    private(set) var speedText = ""
    private(set) var etaText = ""
    private(set) var formattedSize = "—"
    private(set) var formattedDuration = "—"
    private(set) var siteLabel = "—"
    private(set) var typeLabel = ""
    private(set) var qualityLabel = ""
    private(set) var queueBadge: String?

    // Test hook: how many times display strings were recomputed.
    private(set) var recomputeCount = 0

    // The current Preferences.maxAutoRetries — the "attempt N of M" status needs it, and it
    // must track a live pref change, so AppModel threads it in on every apply.
    private var maxAutoRetries: Int

    init(_ snapshot: JobSnapshot, queuePosition: Int?, maxAutoRetries: Int = 5) {
        id = snapshot.id
        self.snapshot = snapshot
        self.maxAutoRetries = maxAutoRetries
        recomputeAll(queuePosition: queuePosition)
    }

    // Returns true if a field that affects filter/sort/grouping changed.
    @discardableResult
    func patch(_ next: JobSnapshot, queuePosition: Int?, maxAutoRetries: Int = 5) -> Bool {
        let old = snapshot
        snapshot = next
        let retriesChanged = self.maxAutoRetries != maxAutoRetries
        self.maxAutoRetries = maxAutoRetries

        let stateChanged = old.state != next.state
        let progressChanged = old.progress != next.progress
        let sizeChanged = old.sizeBytes != next.sizeBytes
        let titleChanged = old.title != next.title
        let extractorChanged = old.extractor != next.extractor
        let durationChanged = old.durationSeconds != next.durationSeconds
        let kindChanged = old.kind != next.kind
        let qualityChanged = old.actualQuality != next.actualQuality
        let badgeChanged = queueBadge != Self.badge(for: next, position: queuePosition)

        guard stateChanged || progressChanged || sizeChanged || titleChanged
            || extractorChanged || durationChanged || kindChanged || qualityChanged
            || badgeChanged || retriesChanged
        else {
            return false
        }

        if stateChanged || progressChanged || retriesChanged {
            statusText = Self.status(for: next, maxAutoRetries: maxAutoRetries)
        }
        if stateChanged || progressChanged {
            speedText = Self.speed(for: next)
        }
        if stateChanged || progressChanged {
            etaText = Self.eta(for: next)
        }
        if sizeChanged || stateChanged {
            formattedSize = Self.size(for: next)
        }
        if durationChanged {
            formattedDuration = Self.duration(for: next)
        }
        if extractorChanged {
            siteLabel = Self.site(for: next)
        }
        if kindChanged {
            typeLabel = Self.type(for: next)
        }
        if kindChanged || qualityChanged {
            qualityLabel = Self.quality(for: next)
        }
        if badgeChanged {
            queueBadge = Self.badge(for: next, position: queuePosition)
        }
        recomputeCount += 1

        return stateChanged || titleChanged || extractorChanged || durationChanged || kindChanged
    }

    func patchProgress(fraction progress: DownloadProgress) {
        let known = snapshot
        snapshot = JobSnapshot(
            id: known.id, url: known.url, title: known.title, state: known.state,
            progress: progress, kind: known.kind, durationSeconds: known.durationSeconds,
            extractor: known.extractor, addedAt: known.addedAt, finishedAt: known.finishedAt,
            destFolder: known.destFolder, outputFiles: known.outputFiles,
            sizeBytes: known.sizeBytes ?? progress.totalBytes, actualQuality: known.actualQuality,
            attempt: known.attempt, cooldownUntil: known.cooldownUntil,
            playerClientUsed: known.playerClientUsed, playlistGroupID: known.playlistGroupID,
            integrityVerdict: known.integrityVerdict, availableActions: known.availableActions
        )
        statusText = Self.status(for: snapshot, maxAutoRetries: maxAutoRetries)
        speedText = Self.speed(for: snapshot)
        etaText = Self.eta(for: snapshot)
        formattedSize = Self.size(for: snapshot)
        recomputeCount += 1
    }

    private func recomputeAll(queuePosition: Int?) {
        statusText = Self.status(for: snapshot, maxAutoRetries: maxAutoRetries)
        speedText = Self.speed(for: snapshot)
        etaText = Self.eta(for: snapshot)
        formattedSize = Self.size(for: snapshot)
        formattedDuration = Self.duration(for: snapshot)
        siteLabel = Self.site(for: snapshot)
        typeLabel = Self.type(for: snapshot)
        qualityLabel = Self.quality(for: snapshot)
        queueBadge = Self.badge(for: snapshot, position: queuePosition)
        recomputeCount += 1
    }
}

// MARK: - Derivations

extension RowModel {
    static func status(for snapshot: JobSnapshot, maxAutoRetries: Int = 5) -> String {
        switch snapshot.state {
        case .queued:
            snapshot.attempt > 0
                ? "Retrying — attempt \(snapshot.attempt + 1) of \(maxAutoRetries)"
                : "Queued"
        case .probing: "Resolving…"
        case .running:
            snapshot.progress.map { "Downloading \(Int($0.fraction * 100))%" } ?? "Downloading"
        case .paused: "Paused"
        case .waitingForNetwork: "Waiting for network"
        case .cooldown: "Cooling down"
        case .completed: "Saved"
        case .cancelled: "Cancelled"
        case let .failed(errorClass): "Failed — \(errorClass.presentation.sentence)"
        }
    }

    static func speed(for snapshot: JobSnapshot) -> String {
        guard snapshot.state == .running, let bytes = snapshot.progress?.speedBytesPerSec else {
            return ""
        }
        return byteString(Int64(bytes)) + "/s"
    }

    static func eta(for snapshot: JobSnapshot) -> String {
        guard snapshot.state == .running, let seconds = snapshot.progress?.etaSeconds else {
            return ""
        }
        return clockString(seconds)
    }

    static func size(for snapshot: JobSnapshot) -> String {
        guard let bytes = snapshot.sizeBytes else { return "—" }
        return byteString(bytes)
    }

    static func duration(for snapshot: JobSnapshot) -> String {
        guard let seconds = snapshot.durationSeconds else { return "—" }
        return clockString(seconds)
    }

    static func site(for snapshot: JobSnapshot) -> String {
        guard let extractor = snapshot.extractor else { return "—" }
        return siteMap[extractor.lowercased()] ?? extractor
    }

    static func type(for snapshot: JobSnapshot) -> String {
        switch snapshot.kind {
        case .audio: "Audio"
        case .video: "Video"
        }
    }

    static func quality(for snapshot: JobSnapshot) -> String {
        let request: String = switch snapshot.kind {
        case let .video(maxHeight): "\(maxHeight)p"
        case let .audio(format): format.rawValue
        }
        guard let actual = snapshot.actualQuality, actual != request else { return request }
        return "\(request) → \(actual)"
    }

    static func badge(for snapshot: JobSnapshot, position: Int?) -> String? {
        guard snapshot.state == .queued, snapshot.attempt == 0, let position else { return nil }
        return "#\(position)"
    }

    private static let siteMap: [String: String] = [
        "youtube": "YouTube",
        "youtube:tab": "YouTube",
        "youtu.be": "YouTube",
        "m.youtube.com": "YouTube",
        "vimeo": "Vimeo",
        "archive.org": "Internet Archive",
        "generic": "Web"
    ]

    private static func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func clockString(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
