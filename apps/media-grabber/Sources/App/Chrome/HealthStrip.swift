import SwiftUI

enum DotState {
    case ok
    case attention
}

enum ChipInteraction {
    case none
    case refresh(@Sendable () async throws -> Void)
}

struct HealthChip: Identifiable {
    let id: String
    let label: String
    let dot: DotState
    let interaction: ChipInteraction
}

struct HealthStrip: View {
    let chips: [HealthChip]

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s2) {
            ForEach(chips) { chip in
                chipView(chip)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.s5)
        .padding(.vertical, Spacing.s2)
    }

    private func chipView(_ chip: HealthChip) -> some View {
        HStack(spacing: Spacing.s1) {
            Circle()
                .fill(chip.dot == .ok ? theme.palette.accent : theme.palette.warn)
                .frame(width: 7, height: 7)
            Text(chip.label)
                .font(theme.skin.monoFont(11, .regular))
                .foregroundStyle(theme.palette.dim)
        }
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, Spacing.s1)
        .background(
            theme.palette.panel,
            in: RoundedRectangle(cornerRadius: theme.skin.chipRadius)
        )
    }
}
