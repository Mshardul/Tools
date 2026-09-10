import Foundation

public struct PlaylistSubmitItem: Sendable {
    public var request: DownloadRequest
    public var force: Bool
    public var prefetched: MediaMetadata?
    public var playlistGroupID: UUID
    public var playlistIndex: Int

    public init(
        request: DownloadRequest,
        force: Bool,
        prefetched: MediaMetadata? = nil,
        playlistGroupID: UUID,
        playlistIndex: Int
    ) {
        self.request = request
        self.force = force
        self.prefetched = prefetched
        self.playlistGroupID = playlistGroupID
        self.playlistIndex = playlistIndex
    }
}
