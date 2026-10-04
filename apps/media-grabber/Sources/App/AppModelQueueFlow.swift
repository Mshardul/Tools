import Foundation
import GrabberKit

extension AppModel {
    func applyIncomingURL(_ url: URL) async {
        homeFieldText = url.absoluteString
        await resolvePasted(homeFieldText)
    }

    func resolvePasted(_ url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isProbing = true
        probeError = nil

        switch PlaylistLink.classify(trimmed) {
        case .youtubeUnsupported:
            await resolveUnsupportedPlaylistLink(trimmed)
        case .youtubePlaylist:
            await resolvePlaylist(trimmed)
        case .singleVideo:
            await resolveVideo(trimmed)
        }
    }

    func clearResolved() {
        resolved = nil
        probeError = nil
        isPlaylistPickerPresented = false
    }

    func grab(overrides: RunwayOverrides = RunwayOverrides()) async {
        guard let resolved else { return }
        guard case let .video(meta) = resolved else {
            isPlaylistPickerPresented = true
            return
        }
        let request = RequestBuilder.build(from: meta, prefs: prefs, overrides: overrides)
        rememberLastSelection(request, overrides: overrides)
        await submitGrab(request, metadata: meta)
    }

    func addPlaylistSelection(
        model picker: PlaylistPickerModel,
        overrides: RunwayOverrides
    ) async {
        let entries = picker.dump.entries.filter { picker.checked.contains($0.playlistIndex) }
        guard !entries.isEmpty else { return }

        let existingGroupID = existingPlaylistGroupID(for: picker.dump)
        let isNewGroup = existingGroupID == nil
        let groupID = existingGroupID ?? UUID()
        let items = entries.map {
            playlistSubmitItem(
                entry: $0,
                picker: picker,
                overrides: overrides,
                groupID: groupID
            )
        }
        if let first = items.first {
            rememberLastSelection(first.request, overrides: overrides)
        }
        let ids = await engine.submitPlaylistItems(items)
        guard !ids.isEmpty else { return }
        if isNewGroup {
            await registerPlaylistGroup(id: groupID, for: picker.dump)
        }
        if let firstID = ids.first {
            setLastSubmittedJobID(firstID)
            scrollToRowID = firstID
        }
    }

    private func rememberLastSelection(
        _ request: DownloadRequest,
        overrides: RunwayOverrides
    ) {
        if let folder = overrides.destFolder {
            prefs.lastUsedDownloadFolder = folder
        }
        if let kind = overrides.kind {
            switch kind {
            case let .video(maxHeight):
                prefs.lastMediaType = .video
                prefs.lastVideoHeight = maxHeight
            case let .audio(format):
                prefs.lastMediaType = .audio
                prefs.lastAudioFormat = format
            }
        }
        switch request.audioLanguage {
        case .original:
            prefs.lastAudioLanguage = .original
        case let .code(code):
            prefs.lastAudioLanguage = .code(code)
        case .unspecified:
            break
        }
    }

    private func submitGrab(_ request: DownloadRequest, metadata: MediaMetadata) async {
        let result = await engine.submit(request, force: false, prefetchedMetadata: metadata)
        switch result {
        case let .queued(id):
            setLastSubmittedJobID(id)
            scrollToRowID = id
        case let .duplicateExists(existing, wasCompleted):
            await log.log(.jobDuplicateSubmitPrompted(existing: existing))
            let confirmed = await confirm(AppModelDialogs
                .duplicateConfirmation(wasCompleted: wasCompleted))
            if confirmed {
                await log.log(.jobDuplicateSubmitConfirmed)
                let forced = await engine.submit(request, force: true, prefetchedMetadata: metadata)
                if case let .queued(id) = forced {
                    setLastSubmittedJobID(id)
                    scrollToRowID = id
                }
            } else {
                await log.log(.jobDuplicateSubmitCancelled)
                if wasCompleted {
                    scrollToRowID = existing
                }
            }
        }
    }
}
