import GrabberKit
import SwiftUI

struct AppearancePane: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var prefs = appModel.prefs
        return VStack(alignment: .leading, spacing: 0) {
            PrefPaneHeader(.appearance)

            PrefRow(
                "Theme",
                helper: "Aurora is dark and luminous. Tape Deck is warm and light."
            ) {
                SkinnedSegment(
                    [ThemeKind.aurora, .tapeDeck],
                    selection: $prefs.theme
                ) { $0 == .aurora ? "Aurora" : "Tape Deck" }
            }

            PrefRow("Palette") {
                HStack(spacing: Spacing.s3) {
                    ForEach(palettes(for: prefs.theme), id: \.self) { kind in
                        swatch(kind, selected: kind == prefs.palette) {
                            prefs.palette = kind
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: prefs.theme) { _, new in
            prefs.palette = defaultPalette(for: new)
        }
    }

    private func palettes(for theme: ThemeKind) -> [PaletteKind] {
        switch theme {
        case .aurora: [.auroraMintIris, .auroraLimeForest, .auroraMagentaViolet]
        case .tapeDeck: [.tapeDeckA, .tapeDeckB, .tapeDeckC]
        }
    }

    private func defaultPalette(for theme: ThemeKind) -> PaletteKind {
        switch theme {
        case .aurora: .auroraMintIris
        case .tapeDeck: .tapeDeckA
        }
    }

    private func displayName(_ kind: PaletteKind) -> String {
        switch kind {
        case .auroraMintIris: "Mint & Iris"
        case .auroraLimeForest: "Lime & Forest"
        case .auroraMagentaViolet: "Magenta & Violet"
        case .tapeDeckA: "Teal & Rust"
        case .tapeDeckB: "Plum & Blush"
        case .tapeDeckC: "Navy & Aqua"
        }
    }

    private func swatch(
        _ kind: PaletteKind,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let tokens = palette(for: kind)
        return Button(action: action) {
            VStack(spacing: Spacing.s1) {
                HStack(spacing: 0) {
                    tokens.accent
                    tokens.accent2
                }
                .frame(width: 84, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: theme.chipRadius))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: theme.chipRadius)
                            .stroke(theme.palette.accent, lineWidth: 2)
                            .padding(-2)
                    }
                }
                Text(displayName(kind))
                    .font(theme.bodyFont(11, .regular))
                    .foregroundStyle(theme.palette.text)
            }
        }
        .buttonStyle(.plain)
    }
}
