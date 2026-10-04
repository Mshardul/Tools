import Foundation

public extension DownloadEngine {
    func upsertPlaylistGroup(_ group: PersistedPlaylistGroup) {
        playlistGroupRegistry[group.id] = group
        persistPlaylistGroups()
        bump()
        emitSnapshot()
    }

    func setPlaylistGroupCollapsed(id: UUID, _ collapsed: Bool) {
        guard var group = playlistGroupRegistry[id] else { return }
        group.isCollapsed = collapsed
        playlistGroupRegistry[id] = group
        persistPlaylistGroups()
        bump()
        emitSnapshot()
    }

    func loadPlaylistGroupsFromPersistence() {
        let liveGroupIDs = Set(jobs.compactMap(\.playlistGroupID))
        let stored = dependencies.persistence.loadPlaylistGroups()
        let loaded = stored.filter { liveGroupIDs.contains($0.id) }
        playlistGroupRegistry = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        if loaded.count != stored.count {
            persistPlaylistGroups()
        }
        bump()
        emitSnapshot()
    }
}

extension DownloadEngine {
    func playlistGroupSnapshots(jobSnapshots: [JobSnapshot]) -> [PlaylistGroupSnapshot] {
        pruneEmptyPlaylistGroups(against: jobSnapshots)
        return playlistGroupRegistry.values
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { PlaylistGroupSnapshot.rollup(from: jobSnapshots, registry: $0) }
    }

    private func pruneEmptyPlaylistGroups(against jobSnapshots: [JobSnapshot]) {
        let live = Set(jobSnapshots.compactMap(\.playlistGroupID))
        let before = playlistGroupRegistry.count
        playlistGroupRegistry = playlistGroupRegistry.filter { live.contains($0.key) }
        if playlistGroupRegistry.count != before {
            persistPlaylistGroups()
        }
    }

    private func persistPlaylistGroups() {
        dependencies.persistence.savePlaylistGroups(Array(playlistGroupRegistry.values))
    }
}
