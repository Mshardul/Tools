import SwiftUI

func shouldShowConcurrencyNote(newValue: Int, runningCount: Int) -> Bool {
    newValue < runningCount
}

struct ConcurrencyNote: View {
    @Environment(\.theme) private var theme
    let runningCount: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s1) {
            Icon(kind: .warning, size: 12)
                .foregroundStyle(theme.palette.warn)
            Text("\(runningCount) still running \u{2014} the new limit applies as they finish.")
                .font(theme.bodyFont(11.5, .regular))
                .foregroundStyle(theme.palette.dim)
        }
    }
}
