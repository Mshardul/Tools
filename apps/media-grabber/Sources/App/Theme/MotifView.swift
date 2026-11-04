import SwiftUI

enum MotifStyle: Equatable {
    case orb
    case reel
}

struct MotifView: View {
    var isActive: Bool
    var size: CGFloat

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func isSpinning(reduceMotion: Bool) -> Bool {
        isActive && !reduceMotion
    }

    static func style(for theme: Theme) -> MotifStyle {
        theme.motif == .reel ? .reel : .orb
    }

    var body: some View {
        TimelineView(.animation(paused: !isSpinning(reduceMotion: reduceMotion))) { context in
            let angle = isSpinning(reduceMotion: reduceMotion)
                ? Angle.degrees(context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 6) / 6 * 360)
                : .zero
            mark
                .rotationEffect(angle)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        switch Self.style(for: theme) {
        case .orb:
            Circle()
                .fill(AngularGradient(colors: theme.palette.orbStops, center: .center))
                .overlay(Circle().stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth))
        case .reel:
            let ink = theme.palette.panelSolid
            let ring = size * 3 / 20
            ZStack {
                Circle().strokeBorder(ink, lineWidth: ring)
                Rectangle().fill(ink).frame(width: ring, height: size * 12 / 20)
                Rectangle().fill(ink).frame(width: size * 12 / 20, height: ring)
            }
        }
    }
}
