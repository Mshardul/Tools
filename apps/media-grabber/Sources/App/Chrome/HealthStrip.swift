import GrabberKit
import SwiftUI

enum DotState: Equatable {
    case ok
    case attention
}

enum PopoverKind: Equatable {
    case hostRate
}

enum ChipInteraction: Equatable {
    case none
    case refresh
    case popover(PopoverKind)
}

struct HealthChip: Identifiable {
    let id: String
    let label: String
    let dot: DotState
    let interaction: ChipInteraction
    var countdownUntil: Date?
}

struct HealthStrip: View {
    let chips: [HealthChip]
    var onRefresh: ((HealthChip) -> Void)?

    @Environment(\.theme) private var theme
    @State private var openPopoverID: String?

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

    @ViewBuilder
    private func chipView(_ chip: HealthChip) -> some View {
        switch chip.interaction {
        case .popover:
            Button {
                openPopoverID = chip.id
            } label: {
                chipBody(chip)
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { openPopoverID == chip.id },
                set: {
                    if !$0 {
                        openPopoverID = nil
                    }
                }
            )) {
                HostRatePopover()
            }
        case .refresh:
            Button {
                onRefresh?(chip)
            } label: {
                HStack(spacing: Spacing.s1) {
                    chipBody(chip)
                    Text("↻")
                        .font(theme.monoFont(11, .regular))
                        .foregroundStyle(theme.palette.dim)
                }
            }
            .buttonStyle(.plain)
        case .none:
            chipBody(chip)
        }
    }

    @ViewBuilder
    private func chipBody(_ chip: HealthChip) -> some View {
        if let until = chip.countdownUntil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                chipLabel(chip, suffix: " — \(CountdownFormat.mmss(until: until, now: context.date))")
            }
        } else {
            chipLabel(chip, suffix: "")
        }
    }

    private func chipLabel(_ chip: HealthChip, suffix: String) -> some View {
        HStack(spacing: Spacing.s1) {
            Circle()
                .fill(chip.dot == .ok ? theme.palette.accent : theme.palette.warn)
                .frame(width: 7, height: 7)
            Text(chip.label + suffix)
                .font(theme.monoFont(11, .regular))
                .foregroundStyle(theme.palette.dim)
        }
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, Spacing.s1)
        .background(
            theme.palette.panel,
            in: RoundedRectangle(cornerRadius: theme.chipRadius)
        )
    }
}
