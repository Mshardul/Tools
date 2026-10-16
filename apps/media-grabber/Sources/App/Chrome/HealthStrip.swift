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
    case setUp
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
            .accessibilityLabel(HealthChipAccessibility.popoverLabel(chipLabel: chip.label))
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
            refreshChip(chip, isBusy: isBusy)
        case .setUp:
            setUpChip(chip)
        case .none:
            chipBody(chip)
        }
    }

    private func refreshChip(_ chip: HealthChip, isBusy: Bool) -> some View {
        Button {
            if !isBusy {
                onRefresh?(chip)
            }
        } label: {
            chipBody(
                chip,
                trailing: Text("↻")
                    .font(theme.monoFont(11, .regular))
                    .foregroundStyle(theme.palette.dim)
                    .rotationEffect(isSpinning(isBusy, reduceMotion: reduceMotion) ? .degrees(360) : .degrees(0))
                    .animation(
                        isSpinning(isBusy, reduceMotion: reduceMotion)
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: isSpinning(isBusy, reduceMotion: reduceMotion)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(HealthChipAccessibility.refreshLabel(id: chip.id))
    }

    private func setUpChip(_ chip: HealthChip) -> some View {
        Button {
            onRefresh?(chip)
        } label: {
            chipBody(
                chip,
                trailing: Text("set up")
                    .font(theme.monoFont(11, .medium))
                    .foregroundStyle(theme.palette.accent)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chip.label), set up")
    }

    private func chipBody(_ chip: HealthChip) -> some View {
        chipBody(chip, trailing: EmptyView())
    }

    @ViewBuilder
    private func chipBody(_ chip: HealthChip, trailing: some View) -> some View {
        if let until = chip.countdownUntil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                chipLabel(
                    chip,
                    suffix: " — \(CountdownFormat.mmss(until: until, now: context.date))",
                    trailing: trailing
                )
            }
        } else {
            chipLabel(chip, suffix: "", trailing: trailing)
        }
    }

    private func chipLabel(_ chip: HealthChip, suffix: String, trailing: some View) -> some View {
        HStack(spacing: Spacing.s2) {
            dotView(chip.dot)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(chip.label + suffix)
                .font(theme.monoFont(11, .regular))
                .foregroundStyle(theme.palette.dim)
            trailing
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s1 + 1)
        .background(theme.palette.panel, in: Capsule())
        .overlay(Capsule().stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth))
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
