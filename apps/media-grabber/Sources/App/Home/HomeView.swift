import GrabberKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    @AppStorage("mg.hasGrabbedOnce") private var hasGrabbedOnce = false

    @State private var pastedURL = ""
    @State private var mediaType: MediaType = .video
    @State private var videoHeight = 1080
    @State private var audioFormat: AudioFormat = .m4a
    @State private var selectedTrackID = "default"
    @State private var destFolder = URL(fileURLWithPath: NSHomeDirectory())
    @State private var seeded = false
    @State private var probeTask: Task<Void, Never>?

    private var showsTable: Bool {
        hasGrabbedOnce || !appModel.rowStore.rows.isEmpty
    }

    var body: some View {
        Group {
            if showsTable {
                tableLayout
            } else {
                firstRunLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: seedFromPrefs)
        .onChange(of: appModel.resolved) { _, meta in
            seedCatalog(meta)
        }
    }

    private var firstRunLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Spacing.s5) {
                hero
                pasteBlock()
                stepCards
            }
            .padding(Spacing.s6)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }

    private var tableLayout: some View {
        @Bindable var appModel = appModel
        return VStack(spacing: 0) {
            pasteBlock(reserveRunwaySlot: true)
                .padding(.horizontal, Spacing.s6)
                .padding(.top, Spacing.s4)

            DownloadsTable(
                store: appModel.rowStore,
                columnConfig: $appModel.columnConfig,
                scrollToRowID: $appModel.scrollToRowID,
                onAction: { id, action in
                    Task { await appModel.handleRowAction(id, action: action) }
                }
            )
            .padding(.top, Spacing.s5)
            .frame(maxHeight: .infinity)
        }
    }

    private func seedFromPrefs() {
        guard !seeded else { return }
        seeded = true
        let seed = runwaySeed(from: appModel.prefs)
        mediaType = seed.mediaType
        videoHeight = seed.videoHeight
        audioFormat = seed.audioFormat
        destFolder = seed.downloadFolder
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("PASTE. PICK. GRAB.")
                .font(theme.monoFont(11, .medium))
                .foregroundStyle(theme.palette.accent)
            Text("One link in. One file out.")
                .font(theme.displayFont(32, .semibold))
                .foregroundStyle(theme.palette.headline)
        }
    }

    @ViewBuilder
    private var probeStatus: some View {
        if appModel.isProbing {
            ProgressView()
                .controlSize(.small)
                .tint(theme.palette.accent)
        } else if let resolved = appModel.resolved {
            Text("\u{2713} \(resolved.title)")
                .font(theme.monoFont(12, .regular))
                .foregroundStyle(theme.palette.accent)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func pasteBlock(reserveRunwaySlot: Bool = false) -> some View {
        VStack(spacing: Spacing.s3) {
            pasteField
            if runwayAttached || reserveRunwaySlot {
                attachedRunway
                    .opacity(runwayAttached ? 1 : 0)
                    .allowsHitTesting(runwayAttached)
                    .accessibilityHidden(!runwayAttached)
            }
        }
    }

    private var pasteField: some View {
        VStack(spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                TextField("", text: $pastedURL)
                    .textFieldStyle(.plain)
                    .font(theme.bodyFont(14, .regular))
                    .foregroundStyle(theme.palette.text)
                    .onSubmit { Task { await resolve() } }
                    .onChange(of: pastedURL) { _, new in autoProbe(new) }
                    .overlay(alignment: .leading) {
                        if pastedURL.isEmpty {
                            Text("Paste a link")
                                .font(theme.bodyFont(14, .regular))
                                .foregroundStyle(theme.palette.faint)
                                .allowsHitTesting(false)
                        }
                    }
                probeStatus
            }

            if let error = appModel.probeError {
                Text(error)
                    .font(theme.bodyFont(12, .regular))
                    .foregroundStyle(theme.palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.palette.panel,
            in: RoundedRectangle(cornerRadius: theme.cardRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius)
                .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
        )
    }

    private var attachedRunway: some View {
        RunwayView(
            mediaType: $mediaType,
            videoHeight: $videoHeight,
            audioFormat: $audioFormat,
            selectedTrackID: $selectedTrackID,
            destFolder: $destFolder,
            audioTracks: languagePickerTracks,
            offeredHeights: offeredHeights,
            canGrab: appModel.resolved != nil,
            onGrab: grab
        )
    }

    private var runwayAttached: Bool {
        appModel.resolved != nil
    }

    private var stepCards: some View {
        HStack(spacing: Spacing.s3) {
            stepCard(1, "Paste a link", "Any video page URL.")
            stepCard(2, "Pick a format", "Video quality or audio only.")
            stepCard(3, "Press Grab", "It saves to your folder.")
        }
    }

    private func stepCard(_ index: Int, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("\(index)")
                .font(theme.monoFont(12, .medium))
                .foregroundStyle(theme.palette.faint)
            Text(title)
                .font(theme.bodyFont(13, .semibold))
                .foregroundStyle(theme.palette.text)
            Text(subtitle)
                .font(theme.bodyFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s3)
        .background(
            theme.palette.panel,
            in: RoundedRectangle(cornerRadius: theme.cardRadius)
        )
    }

    private func resolve() async {
        probeTask?.cancel()
        await appModel.resolvePasted(pastedURL)
    }

    private func autoProbe(_ value: String) {
        probeTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("://") else {
            appModel.clearResolved()
            return
        }
        probeTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await appModel.resolvePasted(trimmed)
        }
    }

    private func grab() {
        Task {
            await appModel.grab(overrides: runwayOverrides)
            hasGrabbedOnce = true
            pastedURL = ""
            appModel.clearResolved()
        }
    }

    private var runwayOverrides: RunwayOverrides {
        RunwayOverrides(
            kind: selectedKind,
            destFolder: destFolder,
            audioLanguage: selectedAudioLanguage
        )
    }

    private var selectedKind: DownloadKind {
        switch mediaType {
        case .video:
            .video(maxHeight: videoHeight)
        case .audio:
            .audio(format: audioFormat)
        }
    }
}

extension HomeView {
    private var languagePickerTracks: [AudioTrack] {
        let tracks = appModel.resolved?.audioTracks ?? []
        if tracks.isEmpty {
            return [AudioTrack(
                id: "default",
                languageCode: nil,
                label: "Default",
                isOriginal: false,
                isDefault: true
            )]
        }
        return tracks
    }

    private var offeredHeights: [Int] {
        guard let meta = appModel.resolved else {
            return VideoQualityOptions.offered(from: MediaMetadata(
                title: "",
                durationSeconds: nil,
                isPlaylist: false,
                sourceURL: ""
            ))
        }
        return VideoQualityOptions.offered(from: meta)
    }

    private var selectedAudioLanguage: AudioLanguage {
        let tracks = languagePickerTracks
        let track = tracks.first { $0.id == selectedTrackID } ?? tracks.first
        guard let track else {
            return .unspecified
        }
        return RequestBuilder.audioLanguage(from: track)
    }

    private func seedCatalog(_ meta: MediaMetadata?) {
        guard let meta else { return }
        videoHeight = VideoQualityOptions.seed(
            last: appModel.prefs.lastVideoHeight,
            defaultHeight: appModel.prefs.defaultVideoHeight,
            offered: VideoQualityOptions.offered(from: meta)
        )
        selectedTrackID = AudioLanguageSeed.pick(
            tracks: meta.audioTracks,
            last: appModel.prefs.lastAudioLanguage,
            policy: appModel.prefs.defaultAudioLanguagePolicy
        ).id
    }
}
