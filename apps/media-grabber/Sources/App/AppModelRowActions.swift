import Foundation
import GrabberKit

#if canImport(AppKit)
    import AppKit
#endif

enum PlaylistGroupAction {
    case pauseAll
    case retryFailed
    case cancelAll
}

extension AppModel {
    func handleRowAction(_ id: UUID, action: RowAction) async {
        switch action {
        case .pause: await engine.pause(id)
        case .resume: await engine.resume(id)
        case .cancel: await engine.cancel(id)
        case .remove: await removeRow(id)
        case .forceStart: await engine.forceStart(id)
        case .reveal: await reveal(jobID: id)
        case .openInBrowser: openInBrowser(jobID: id)
        case .retry: await engine.retry(id)
        case .showLog: await showLog(jobID: id)
        case .retryWithCookies: await retryWithCookies(id)
        }
    }

    private func retryWithCookies(_ id: UUID) async {
        if prefs.cookiesFromBrowser.isNone {
            setPendingCookieRetry(id)
            page = .preferences(.cookies)
        } else {
            await engine.retryWithCookies(id)
        }
    }

    func handlePlaylistGroupAction(_ id: UUID, action: PlaylistGroupAction) async {
        let children = playlistChildren(for: id)
        switch action {
        case .pauseAll:
            await pauseRunning(children)
        case .retryFailed:
            await retryFailed(children)
        case .cancelAll:
            await cancelCancellable(children)
        }
    }

    func setPlaylistGroupCollapsed(id: UUID, _ isCollapsed: Bool) {
        guard let index = playlistGroups.firstIndex(where: { $0.id == id }) else { return }
        playlistGroups[index].isCollapsed = isCollapsed
        rowStore.setCollapsed(id: id, isCollapsed)
        persistence?.savePlaylistGroups(playlistGroups)
        rowStore.applyGroups(playlistGroups)
    }

    private func removeRow(_ id: UUID) async {
        let removedGroupID = rowStore.rows.first { $0.id == id }?.snapshot.playlistGroupID
        await engine.remove(id)
        guard let groupID = removedGroupID else { return }
        dropPlaylistGroupIfEmpty(groupID, removing: id)
    }

    private func dropPlaylistGroupIfEmpty(_ groupID: UUID, removing removedID: UUID) {
        let hasRemaining = rowStore.rows.contains {
            $0.id != removedID && $0.snapshot.playlistGroupID == groupID
        }
        guard !hasRemaining else { return }
        playlistGroups.removeAll { $0.id == groupID }
        persistence?.savePlaylistGroups(playlistGroups)
        rowStore.applyGroups(playlistGroups)
    }

    private func playlistChildren(for id: UUID) -> [RowModel] {
        rowStore.rows.filter { $0.snapshot.playlistGroupID == id }
    }

    private func pauseRunning(_ children: [RowModel]) async {
        for child in children where child.snapshot.state == .running {
            await engine.pause(child.id)
        }
    }

    private func retryFailed(_ children: [RowModel]) async {
        for child in children where child.snapshot.state.isFailed {
            await engine.retry(child.id)
        }
    }

    private func cancelCancellable(_ children: [RowModel]) async {
        let targets = children.filter(\.snapshot.state.isPlaylistCancellable)
        guard !targets.isEmpty else { return }
        let confirmed = await confirm(AppModelDialogs.playlistCancelAllConfirmation())
        guard confirmed else { return }
        for target in targets {
            await engine.cancel(target.id)
        }
    }

    func showLog(jobID: UUID) async {
        let url = engineJobLogDir.appendingPathComponent("\(jobID.uuidString).log")
        if FileManager.default.fileExists(atPath: url.path) {
            openURLSink.open(url)
        } else {
            await log.log(.showLogTargetMissing(jobID: jobID))
            _ = await confirm(AppModelDialogs.showLogMissingNotice())
        }
    }

    func reveal(jobID: UUID) async {
        guard let row = rowStore.rows.first(where: { $0.id == jobID }) else { return }
        let existing = row.snapshot.outputFiles.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        if existing.isEmpty {
            await log.log(.revealTargetMissing(jobID: jobID))
            _ = await confirm(AppModelDialogs.revealMissingConfirmation())
        } else {
            revealSink.reveal(existing)
        }
    }

    private func openInBrowser(jobID: UUID) {
        guard let row = rowStore.rows.first(where: { $0.id == jobID }),
              let url = URL(string: row.snapshot.url)
        else { return }
        #if canImport(AppKit)
            NSWorkspace.shared.open(url)
        #endif
    }
}

private extension JobState {
    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }

    var isPlaylistCancellable: Bool {
        switch self {
        case .queued, .paused, .probing, .running:
            true
        default:
            false
        }
    }
}
