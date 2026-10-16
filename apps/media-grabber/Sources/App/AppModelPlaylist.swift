import Foundation
import GrabberKit

extension AppModel {
    static func trimmedPlaylistSourceURL(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func existingPlaylistGroupID(for dump: PlaylistDump) -> UUID? {
        let sourceURL = Self.trimmedPlaylistSourceURL(dump.sourceURL)
        let liveGroupIDs = Set(rowStore.rows.compactMap(\.snapshot.playlistGroupID))
        return playlistGroups.first(where: {
            Self.trimmedPlaylistSourceURL($0.sourceURL) == sourceURL && liveGroupIDs.contains($0.id)
        })?.id
    }

    func registerPlaylistGroup(id: UUID, for dump: PlaylistDump) async {
        let group = PersistedPlaylistGroup(
            id: id,
            title: dump.title,
            sourceURL: Self.trimmedPlaylistSourceURL(dump.sourceURL),
            isCollapsed: false
        )
        playlistGroups.append(group)
        rowStore.applyGroups(playlistGroups)
        await engine.upsertPlaylistGroup(group)
    }

    func resolveUnsupportedPlaylistLink(_ url: String) async {
        isProbing = false
        resolved = nil
        isPlaylistPickerPresented = false
        probeError = AppModelDialogs.unsupportedPlaylistLink
        await log.log(.probeCompleted(url: url, title: nil, ok: false))
    }

    func resolvePlaylist(_ url: String) async {
        let result = await engine.previewPlaylist(url)
        isProbing = false
        switch result {
        case let .success(dump):
            resolved = .playlist(dump)
            isPlaylistPickerPresented = true
            await log.log(.probeCompleted(url: url, title: dump.title, ok: true))
        case let .failure(error):
            resolved = nil
            isPlaylistPickerPresented = false
            await showProbeFailure(error, url: url)
            await log.log(.probeCompleted(url: url, title: nil, ok: false))
        }
    }

    private func showProbeFailure(_ error: MetadataError, url: String) async {
        let shieldStatus = await engine.currentSnapshot().shieldStatus
        let isYouTube = RateHost(urlString: url).canonical == "youtube"
        probeError = AppModelDialogs.probeErrorMessage(
            for: error,
            vpnActive: vpnDetector.isVPNActive,
            shieldStatus: shieldStatus,
            isYouTube: isYouTube
        )
        shieldSetup.probePrompt = error == .botCheck && isYouTube ? Self.shieldPrompt(for: shieldStatus) : nil
    }

    private static func shieldPrompt(for status: ShieldStatus) -> ShieldSetupController.ProbePrompt? {
        switch status {
        case .running: nil
        case .down: .restart
        case .missing: .setUp
        }
    }

    func resolveVideo(_ url: String) async {
        let result = await engine.preview(url)
        isProbing = false
        isPlaylistPickerPresented = false
        switch result {
        case let .success(meta):
            resolved = .video(meta)
            await log.log(.probeCompleted(url: url, title: meta.title, ok: true))
        case let .failure(error):
            resolved = nil
            await showProbeFailure(error, url: url)
            await log.log(.probeCompleted(url: url, title: nil, ok: false))
        }
    }

    func playlistSubmitItem(
        entry: PlaylistEntry,
        picker: PlaylistPickerModel,
        overrides: RunwayOverrides,
        groupID: UUID
    ) -> PlaylistSubmitItem {
        PlaylistSubmitItem(
            request: RequestBuilder.build(from: entry, prefs: prefs, overrides: overrides),
            force: picker.warnings[entry.playlistIndex] != nil,
            prefetched: RequestBuilder.prefetch(from: entry),
            playlistGroupID: groupID,
            playlistIndex: entry.playlistIndex
        )
    }

    func loadPlaylistGroups(for snapshot: QueueSnapshot) {
        syncPlaylistGroups(from: snapshot)
    }

    func syncPlaylistGroups(from snapshot: QueueSnapshot) {
        playlistGroups = snapshot.playlistGroups.map(\.asPersisted)
        rowStore.applyGroupSnapshots(snapshot.playlistGroups)
    }
}
