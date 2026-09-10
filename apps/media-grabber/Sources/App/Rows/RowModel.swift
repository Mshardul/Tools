import Foundation
import GrabberKit
import Observation

private struct RowPatchExtras {
    var badgeChanged: Bool
    var retriesChanged: Bool
    var rateChanged: Bool
    var vpnChanged: Bool
}

private struct RowFieldChanges {
    var state: Bool
    var progress: Bool
    var size: Bool
    var title: Bool
    var extractor: Bool
    var duration: Bool
    var kind: Bool
    var quality: Bool
    var attempt: Bool
    var badge: Bool
    var retries: Bool
    var rate: Bool
    var vpn: Bool

    init(from old: JobSnapshot, to next: JobSnapshot, extras: RowPatchExtras) {
        state = old.state != next.state
        progress = old.progress != next.progress
        size = old.sizeBytes != next.sizeBytes
        title = old.title != next.title
        extractor = old.extractor != next.extractor
        duration = old.durationSeconds != next.durationSeconds
        kind = old.kind != next.kind
        quality = old.actualQuality != next.actualQuality
        attempt = old.attempt != next.attempt || old.cooldownUntil != next.cooldownUntil
        badge = extras.badgeChanged
        retries = extras.retriesChanged
        rate = extras.rateChanged
        vpn = extras.vpnChanged
    }

    var needsRecompute: Bool {
        state || progress || size || title || extractor || duration || kind || quality
            || badge || retries || rate || attempt || vpn
    }

    var structural: Bool {
        state || title || extractor || duration || kind
    }

    var refreshStatus: Bool {
        state || progress || retries || rate || attempt || vpn
    }
}

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
    private(set) var rateDisplay: HostRateDisplayState?

    // Test hook: how many times display strings were recomputed.
    private(set) var recomputeCount = 0

    // Live Preferences.maxAutoRetries; AppModel threads it in on every apply.
    private var maxAutoRetries: Int
    private var vpnActive: Bool

    var hostCooldownDeadline: Date? {
        if case let .cooldown(until, _) = rateDisplay?.state {
            return until
        }
        return nil
    }

    init(
        _ snapshot: JobSnapshot,
        queuePosition: Int?,
        maxAutoRetries: Int = 5,
        rate: HostRateDisplayState? = nil,
        vpnActive: Bool = false
    ) {
        id = snapshot.id
        self.snapshot = snapshot
        self.maxAutoRetries = maxAutoRetries
        self.vpnActive = vpnActive
        rateDisplay = rate
        recomputeAll(queuePosition: queuePosition)
    }

    // Returns true if a field that affects filter/sort/grouping changed.
    @discardableResult
    func patch(
        _ next: JobSnapshot,
        queuePosition: Int?,
        maxAutoRetries: Int = 5,
        rate: HostRateDisplayState? = nil,
        vpnActive: Bool = false
    ) -> Bool {
        let old = snapshot
        snapshot = next
        let retriesChanged = self.maxAutoRetries != maxAutoRetries
        self.maxAutoRetries = maxAutoRetries
        let vpnChanged = self.vpnActive != vpnActive
        self.vpnActive = vpnActive
        let rateChanged = rateDisplay != rate
        rateDisplay = rate
        let extras = RowPatchExtras(
            badgeChanged: queueBadge != Self.badge(for: next, position: queuePosition),
            retriesChanged: retriesChanged,
            rateChanged: rateChanged,
            vpnChanged: vpnChanged
        )
        let changes = RowFieldChanges(from: old, to: next, extras: extras)
        guard changes.needsRecompute else {
            return false
        }
        refreshDerivedFields(next, queuePosition: queuePosition, changes: changes)
        recomputeCount += 1
        return changes.structural
    }

    private func refreshDerivedFields(
        _ next: JobSnapshot,
        queuePosition: Int?,
        changes: RowFieldChanges
    ) {
        if changes.refreshStatus {
            statusText = Self.status(
                for: next,
                maxAutoRetries: maxAutoRetries,
                rate: rateDisplay,
                vpnActive: vpnActive
            )
        }
        if changes.state || changes.progress {
            speedText = Self.speed(for: next)
            etaText = Self.eta(for: next)
        }
        if changes.size || changes.state {
            formattedSize = Self.size(for: next)
        }
        if changes.duration {
            formattedDuration = Self.duration(for: next)
        }
        if changes.extractor {
            siteLabel = Self.site(for: next)
        }
        if changes.kind {
            typeLabel = Self.type(for: next)
        }
        if changes.kind || changes.quality {
            qualityLabel = Self.quality(for: next)
        }
        if changes.badge {
            queueBadge = Self.badge(for: next, position: queuePosition)
        }
    }

    func patchProgress(fraction progress: DownloadProgress) {
        let known = snapshot
        snapshot = JobSnapshot(
            id: known.id, url: known.url, rateHost: known.rateHost, title: known.title,
            state: known.state,
            progress: progress, kind: known.kind, durationSeconds: known.durationSeconds,
            extractor: known.extractor, addedAt: known.addedAt, finishedAt: known.finishedAt,
            destFolder: known.destFolder, outputFiles: known.outputFiles,
            sizeBytes: known.sizeBytes ?? progress.totalBytes, actualQuality: known.actualQuality,
            attempt: known.attempt, cooldownUntil: known.cooldownUntil,
            playerClientUsed: known.playerClientUsed, playlistGroupID: known.playlistGroupID,
            playlistIndex: known.playlistIndex,
            integrityVerdict: known.integrityVerdict, availableActions: known.availableActions
        )
        statusText = Self.status(
            for: snapshot,
            maxAutoRetries: maxAutoRetries,
            rate: rateDisplay,
            vpnActive: vpnActive
        )
        speedText = Self.speed(for: snapshot)
        etaText = Self.eta(for: snapshot)
        formattedSize = Self.size(for: snapshot)
        recomputeCount += 1
    }

    private func recomputeAll(queuePosition: Int?) {
        statusText = Self.status(
            for: snapshot,
            maxAutoRetries: maxAutoRetries,
            rate: rateDisplay,
            vpnActive: vpnActive
        )
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
    static func status(
        for snapshot: JobSnapshot,
        maxAutoRetries: Int = 5,
        rate: HostRateDisplayState? = nil,
        vpnActive: Bool = false
    ) -> String {
        RowStatusText.text(
            for: snapshot,
            maxAutoRetries: maxAutoRetries,
            rate: rate,
            vpnActive: vpnActive
        )
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
