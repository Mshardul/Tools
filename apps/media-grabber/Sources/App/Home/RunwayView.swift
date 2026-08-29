import GrabberKit
import SwiftUI

struct RunwayView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    @Binding var kindSelector: KindSelector
    @Binding var maxHeight: Int
    @Binding var audioCodec: AudioCodec
    @Binding var destFolder: URL

    let canGrab: Bool
    let onGrab: () -> Void

    enum KindSelector: String, CaseIterable {
        case video
        case audio
    }

    private let heights = [2160, 1440, 1080, 720, 480, 360]

    var body: some View {
        HStack(spacing: Spacing.s4) {
            slot("Link", filled: appModel.resolved != nil) {
                Text(appModel.resolved?.title ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(theme.palette.dim)
            }
            slot("Type", filled: true) { typeMenu }
            slot("Format", filled: true) { formatMenu }
            slot("Save to", filled: true) { saveMenu }

            Divider().frame(height: 28).overlay(theme.palette.hair)

            Button(action: onGrab) {
                Text("Grab")
                    .font(theme.skin.bodyFont(13, .semibold))
                    .foregroundStyle(theme.palette.onAccent)
                    .padding(.horizontal, Spacing.s5)
                    .padding(.vertical, Spacing.s2)
                    .background(
                        LinearGradient(
                            colors: [theme.palette.goFillStart, theme.palette.goFillEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: theme.skin.controlRadius)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canGrab)
            .opacity(canGrab ? 1 : 0.3)
            .grayscale(canGrab ? 0 : 1)
            .accessibilityLabel("Grab")
        }
        .padding(Spacing.s4)
        .background(
            theme.palette.panel,
            in: UnevenRoundedRectangle(
                bottomLeadingRadius: theme.skin.cardRadius,
                bottomTrailingRadius: theme.skin.cardRadius
            )
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
                    .font(theme.skin.monoFont(10, .regular))
                    .foregroundStyle(theme.palette.faint)
            }
            content()
                .font(theme.skin.bodyFont(12, .medium))
        }
    }

    private var typeMenu: some View {
        Menu {
            ForEach(KindSelector.allCases, id: \.self) { option in
                Button(option.rawValue.capitalized) { kindSelector = option }
            }
        } label: {
            Text(kindSelector.rawValue.capitalized).foregroundStyle(theme.palette.text)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var formatMenu: some View {
        switch kindSelector {
        case .video:
            Menu {
                ForEach(heights, id: \.self) { height in
                    Button("\(height)p") { maxHeight = height }
                }
            } label: {
                Text("\(maxHeight)p").foregroundStyle(theme.palette.text)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        case .audio:
            Menu {
                ForEach(AudioCodec.allCases, id: \.self) { codec in
                    Button(codec.rawValue) { audioCodec = codec }
                }
            } label: {
                Text(audioCodec.rawValue).foregroundStyle(theme.palette.text)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var saveMenu: some View {
        Menu {
            Button(destFolder.lastPathComponent) {}
            Divider()
            Button("Choose\u{2026}") { chooseFolder() }
        } label: {
            Text(destFolder.lastPathComponent).foregroundStyle(theme.palette.text)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func chooseFolder() {
        #if canImport(AppKit)
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                destFolder = url
                appModel.prefs.lastUsedDestFolder = url
            }
        #endif
    }
}
