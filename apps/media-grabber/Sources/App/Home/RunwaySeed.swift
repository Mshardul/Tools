import Foundation
import GrabberKit

struct RunwaySeed: Equatable {
    var mediaType: MediaType
    var videoHeight: Int
    var audioFormat: AudioFormat
    var downloadFolder: URL
}

func runwaySeed(from prefs: Preferences) -> RunwaySeed {
    let folder = prefs.lastUsedDownloadFolder != prefs.defaultDownloadFolder
        ? prefs.lastUsedDownloadFolder
        : prefs.defaultDownloadFolder
    return RunwaySeed(
        mediaType: prefs.lastMediaType ?? prefs.defaultMediaType,
        videoHeight: prefs.lastVideoHeight ?? prefs.defaultVideoHeight,
        audioFormat: prefs.lastAudioFormat ?? prefs.defaultAudioFormat,
        downloadFolder: folder
    )
}
