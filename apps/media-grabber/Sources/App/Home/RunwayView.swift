import AppKit
import GrabberKit
import SwiftUI

struct RunwayView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    @Binding var mediaType: MediaType
    @Binding var videoHeight: Int
    @Binding var audioFormat: AudioFormat
    @Binding var destFolder: URL

    let canGrab: Bool
    let onGrab: () -> Void

    private enum SaveTarget: Hashable {
        case folder(URL)
        case choose
    }

    private static let qualityLadder: [(label: String, height: Int)] = [
        ("2160p", 2160),
        ("1440p", 1440),
        ("1080p", 1080),
        ("720p", 720),
        ("480p", 480),
        ("Best available", Int.max)
    ]

    var body: some View {
        HStack(spacing: Spacing.s4) {
            slot("Link", filled: appModel.resolved != nil) {
                Text(appModel.resolved?.title ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(theme.palette.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            slot("Type", filled: true) { typeControl }
            slot("Format", filled: true) { formatControl }
            slot("Save to", filled: true) { saveControl }

            Divider().frame(height: 28).overlay(theme.palette.hair)

            Button(action: onGrab) {
                Text("Grab")
                    .font(theme.bodyFont(13, .semibold))
                    .foregroundStyle(theme.palette.onAccent)
                    .padding(.horizontal, Spacing.s5)
                    .padding(.vertical, Spacing.s2)
                    .background(
                        LinearGradient(
                            colors: [theme.palette.goFillStart, theme.palette.goFillEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: theme.controlRadius)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canGrab)
            .opacity(canGrab ? 1 : 0.3)
            .grayscale(canGrab ? 0 : 1)
            .accessibilityLabel("Grab")
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.palette.panelHi,
            in: RoundedRectangle(cornerRadius: theme.cardRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius)
                .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
        )
    }

    private func slot(
        _ label: String,
        filled: Bool,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack(spacing: Spacing.s1) {
                Text(filled ? "\u{25CF}" : "\u{25CB}")
                    .foregroundStyle(filled ? theme.palette.accent : theme.palette.faint)
                Text(label)
                    .font(theme.monoFont(10, .regular))
                    .foregroundStyle(theme.palette.faint)
            }
            content()
                .font(theme.bodyFont(12, .medium))
        }
    }

    private var typeControl: some View {
        SkinnedSegment(
            [MediaType.video, .audio],
            selection: $mediaType
        ) { $0 == .video ? "Video" : "Audio" }
    }

    @ViewBuilder
    private var formatControl: some View {
        switch mediaType {
        case .video:
            SkinnedPicker(
                caption: "Resolution",
                rows: Self.qualityLadder.map {
                    SkinnedPickerRow(id: $0.height, title: $0.label, subtitle: nil)
                },
                selection: $videoHeight,
                triggerLabel: qualityLabel(videoHeight)
            )
        case .audio:
            SkinnedSegment(
                [AudioFormat.m4a, .mp3],
                selection: $audioFormat
            ) { $0.rawValue.uppercased() }
        }
    }

    private var saveControl: some View {
        SkinnedPicker(
            caption: "Save to",
            rows: saveRows,
            selection: Binding(
                get: { .folder(destFolder) },
                set: { applySaveTarget($0) }
            ),
            triggerLabel: destFolder.lastPathComponent
        )
    }

    private var saveRows: [SkinnedPickerRow<SaveTarget>] {
        let defaultFolder = appModel.prefs.defaultDownloadFolder
        let lastUsed = appModel.prefs.lastUsedDownloadFolder
        var rows = [
            SkinnedPickerRow(
                id: SaveTarget.folder(defaultFolder),
                title: defaultFolder.lastPathComponent,
                subtitle: defaultFolder.path
            )
        ]
        if lastUsed != defaultFolder {
            rows.append(SkinnedPickerRow(
                id: SaveTarget.folder(lastUsed),
                title: lastUsed.lastPathComponent,
                subtitle: lastUsed.path
            ))
        }
        rows.append(SkinnedPickerRow(id: SaveTarget.choose, title: "Choose\u{2026}", subtitle: nil))
        return rows
    }

    private func applySaveTarget(_ target: SaveTarget) {
        switch target {
        case let .folder(url):
            destFolder = url
        case .choose:
            chooseFolder()
        }
    }

    private func qualityLabel(_ height: Int) -> String {
        Self.qualityLadder.first { $0.height == height }?.label ?? "\(height)p"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            destFolder = url
            appModel.prefs.lastUsedDownloadFolder = url
        }
    }
}
