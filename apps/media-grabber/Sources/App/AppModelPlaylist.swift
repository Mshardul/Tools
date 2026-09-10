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

    func registerPlaylistGroup(id: UUID, for dump: PlaylistDump) {
        playlistGroups.append(PersistedPlaylistGroup(
            id: id,
            title: dump.title,
            sourceURL: Self.trimmedPlaylistSourceURL(dump.sourceURL),
            isCollapsed: false
        ))
        persistence?.savePlaylistGroups(playlistGroups)
        rowStore.applyGroups(playlistGroups)
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
            probeError = AppModelDialogs.probeErrorMessage(for: error)
            await log.log(.probeCompleted(url: url, title: nil, ok: false))
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
            probeError = error == .botCheck
                ? BotCheckCopy.sentence(vpnActive: vpnDetector.isVPNActive)
                : AppModelDialogs.probeErrorMessage(for: error)
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
        guard let persistence else { return }
        let liveGroupIDs = Set(snapshot.jobs.compactMap(\.playlistGroupID))
        let storedGroups = persistence.loadPlaylistGroups()
        let loaded = storedGroups.filter { liveGroupIDs.contains($0.id) }
        playlistGroups = loaded
        if loaded.count != storedGroups.count {
            persistence.savePlaylistGroups(loaded)
        }
        rowStore.applyGroups(playlistGroups)
    }
}
