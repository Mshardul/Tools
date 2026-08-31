import SwiftUI

struct MotifView: View {
    var isActive: Bool
    var size: CGFloat

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func isSpinning(reduceMotion: Bool) -> Bool {
        isActive && !reduceMotion
    }

    var body: some View {
        TimelineView(.animation(paused: !isSpinning(reduceMotion: reduceMotion))) { context in
            let angle = isSpinning(reduceMotion: reduceMotion)
                ? Angle.degrees(context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 6) / 6 * 360)
                : .zero
            Circle()
                .fill(AngularGradient(colors: theme.palette.orbStops, center: .center))
                .frame(width: size, height: size)
                .rotationEffect(angle)
                .overlay(
                    Circle().stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
                )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
