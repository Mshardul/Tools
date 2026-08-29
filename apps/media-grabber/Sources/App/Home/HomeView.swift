import GrabberKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    @AppStorage("mg.hasGrabbedOnce") private var hasGrabbedOnce = false

    @State private var pastedURL = ""
    @State private var kindSelector: RunwayView.KindSelector = .video
    @State private var maxHeight = 1080
    @State private var audioCodec: AudioCodec = .m4a
    @State private var destFolder = URL(fileURLWithPath: NSHomeDirectory())
    @State private var seeded = false
    @State private var probeTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s5) {
                if !hasGrabbedOnce {
                    hero
                }
                pasteBlock
                if !hasGrabbedOnce, appModel.job == nil {
                    stepCards
                }
                if let job = appModel.job {
                    jobRow(job)
                }
            }
            .padding(Spacing.s6)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear(perform: seedFromPrefs)
    }

    private func seedFromPrefs() {
        guard !seeded else { return }
        seeded = true
        switch appModel.prefs.defaultKind {
        case let .video(height):
            kindSelector = .video
            maxHeight = height
        case let .audio(codec):
            kindSelector = .audio
            audioCodec = codec
        }
        destFolder = appModel.prefs.lastUsedDestFolder
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("PASTE. PICK. GRAB.")
                .font(theme.skin.monoFont(11, .medium))
                .foregroundStyle(theme.palette.accent)
            Text("One link in. One file out.")
                .font(theme.skin.displayFont(32, .semibold))
                .foregroundStyle(theme.palette.headline)
        }
    }

    private var pasteBlock: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s2) {
                TextField("", text: $pastedURL)
                    .textFieldStyle(.plain)
                    .font(theme.skin.bodyFont(14, .regular))
                    .foregroundStyle(theme.palette.text)
                    .onSubmit { Task { await resolve() } }
                    .onChange(of: pastedURL) { _, new in autoProbe(new) }
                    .overlay(alignment: .leading) {
                        if pastedURL.isEmpty {
                            Text("Paste a link")
                                .font(theme.skin.bodyFont(14, .regular))
                                .foregroundStyle(theme.palette.faint)
                                .allowsHitTesting(false)
                        }
                    }
                if appModel.isProbing {
                    ProgressView().controlSize(.small)
                } else if let resolved = appModel.resolved {
                    Text("\u{2713} \(resolved.title)")
                        .font(theme.skin.monoFont(12, .regular))
                        .foregroundStyle(theme.palette.accent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(Spacing.s4)
            .background(
                theme.palette.panel,
                in: runwayAttached
                    ? AnyShape(UnevenRoundedRectangle(
                        topLeadingRadius: theme.skin.cardRadius,
                        topTrailingRadius: theme.skin.cardRadius
                    ))
                    : AnyShape(RoundedRectangle(cornerRadius: theme.skin.cardRadius))
            )

            if let error = appModel.probeError {
                Text(error)
                    .font(theme.skin.bodyFont(12, .regular))
                    .foregroundStyle(theme.palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.s2)
            }

            if runwayAttached {
                RunwayView(
                    kindSelector: $kindSelector,
                    maxHeight: $maxHeight,
                    audioCodec: $audioCodec,
                    destFolder: $destFolder,
                    canGrab: appModel.resolved != nil,
                    onGrab: grab
                )
            }
        }
    }

    private var runwayAttached: Bool {
        appModel.resolved != nil && appModel.job == nil
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
                .font(theme.skin.monoFont(12, .medium))
                .foregroundStyle(theme.palette.faint)
            Text(title)
                .font(theme.skin.bodyFont(13, .semibold))
                .foregroundStyle(theme.palette.text)
            Text(subtitle)
                .font(theme.skin.bodyFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s3)
        .background(
            theme.palette.panel,
            in: RoundedRectangle(cornerRadius: theme.skin.cardRadius)
        )
    }

    private func jobRow(_ job: DownloadJob) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s3) {
                if case .running = job.state {
                    MotifView(isActive: true, size: 14)
                }
                Text(job.title ?? "Downloading")
                    .font(theme.skin.bodyFont(13, .medium))
                    .foregroundStyle(theme.palette.text)
                Spacer()
                Text(statusWord(job.state))
                    .font(theme.skin.monoFont(11, .regular))
                    .foregroundStyle(statusColor(job.state))
                rowAction(job)
            }
            ProgressView(value: job.progress?.fraction ?? 0)
                .tint(theme.palette.accent)
            if case let .failed(errorClass) = job.state, case let .unknown(raw) = errorClass {
                DisclosureGroup("Details") {
                    Text(raw)
                        .font(theme.skin.monoFont(10, .regular))
                        .foregroundStyle(theme.palette.dim)
                        .textSelection(.enabled)
                }
                .font(theme.skin.bodyFont(11, .regular))
            }
        }
        .padding(Spacing.s3)
        .background(
            theme.palette.panel,
            in: RoundedRectangle(cornerRadius: theme.skin.cardRadius)
        )
    }

    @ViewBuilder
    private func rowAction(_ job: DownloadJob) -> some View {
        switch job.state {
        case .completed:
            Button("Reveal") { appModel.reveal() }
                .accessibilityLabel("Reveal in Finder")
        case .running:
            Button("Cancel") { Task { await appModel.cancelJob() } }
                .accessibilityLabel("Cancel download")
        default:
            EmptyView()
        }
    }

    private func statusWord(_ state: JobState) -> String {
        switch state {
        case .queued: "Queued"
        case .probing: "Resolving\u{2026}"
        case .running: "Downloading"
        case .paused: "Paused"
        case .waitingForNetwork: "Waiting for network"
        case .cooldown: "Cooling down"
        case .completed: "Saved"
        case .cancelled: "Cancelled"
        case let .failed(errorClass): "Failed \u{2014} \(Self.failureCopy(errorClass))"
        }
    }

    private func statusColor(_ state: JobState) -> Color {
        switch state {
        case .completed: theme.palette.accent
        case .failed: theme.palette.danger
        default: theme.palette.dim
        }
    }

    private static func failureCopy(_ errorClass: ErrorClass) -> String {
        switch errorClass {
        case .networkDown: "No internet connection."
        case .depMissing: "yt-dlp is missing \u{2014} reopen setup."
        default: "Download failed."
        }
    }

    private func resolve() async {
        probeTask?.cancel()
        await appModel.resolvePasted(pastedURL)
    }

    // Fire a probe shortly after the field settles, so a paste resolves without Return.
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
            await appModel.grab()
            hasGrabbedOnce = true
        }
    }
}
