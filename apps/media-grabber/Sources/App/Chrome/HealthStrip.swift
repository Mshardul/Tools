import GrabberKit
import SwiftUI

enum DotState: Equatable {
    case ok
    case attention
    case busy
}

enum PopoverKind: Equatable {
    case hostRate
}

enum ChipInteraction: Equatable {
    case none
    case refresh(isBusy: Bool)
    case popover(PopoverKind)
}

struct HealthChip: Identifiable {
    let id: String
    let label: String
    let dot: DotState
    var interaction: ChipInteraction
    var countdownUntil: Date?
}

struct HealthStrip: View {
    let chips: [HealthChip]
    var onRefresh: ((HealthChip) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        case let .refresh(isBusy):
            Button {
                if !isBusy {
                    onRefresh?(chip)
                }
            } label: {
                HStack(spacing: Spacing.s1) {
                    chipBody(chip)
                    Text("↻")
                        .font(theme.monoFont(11, .regular))
                        .foregroundStyle(theme.palette.dim)
                        .rotationEffect(isSpinning(isBusy, reduceMotion: reduceMotion) ? .degrees(360) : .degrees(0))
                        .animation(
                            isSpinning(isBusy, reduceMotion: reduceMotion)
                                ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                : .default,
                            value: isSpinning(isBusy, reduceMotion: reduceMotion)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
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
            dotView(chip.dot)
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

    func isPulsing(_ dot: DotState, reduceMotion: Bool) -> Bool {
        dot == .busy && !reduceMotion
    }

    func isSpinning(_ isBusy: Bool, reduceMotion: Bool) -> Bool {
        isBusy && !reduceMotion
    }

    @ViewBuilder
    private func dotView(_ dot: DotState) -> some View {
        switch dot {
        case .ok:
            Circle().fill(theme.palette.accent)
        case .attention:
            Circle().fill(theme.palette.warn)
        case .busy:
            TimelineView(.animation(paused: !isPulsing(dot, reduceMotion: reduceMotion))) { context in
                let opacity = isPulsing(dot, reduceMotion: reduceMotion)
                    ? 0.4 + 0.6 * abs(context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.2) / 1.2 * 2 - 1)
                    : 1.0
                Circle()
                    .fill(theme.palette.faint)
                    .opacity(opacity)
            }
        }
    }
}
