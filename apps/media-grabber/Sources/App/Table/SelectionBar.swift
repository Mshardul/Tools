import GrabberKit
import SwiftUI

struct SelectionBar: View {
    let selectedCount: Int
    let verbs: [RowAction]
    let onAction: (RowAction) -> Void
    let onClear: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        if selectedCount > 0 {
            HStack(spacing: Spacing.s3) {
                Text("\(selectedCount) selected")
                    .font(theme.bodyFont(12, .medium))
                    .foregroundStyle(theme.palette.text)

                ForEach(verbs, id: \.self) { verb in
                    Button(verb.accessibilityLabel) {
                        onAction(verb)
                    }
                    .buttonStyle(.plain)
                    .font(theme.bodyFont(12, .medium))
                    .foregroundStyle(theme.palette.accent)
                    .accessibilityLabel(verb.accessibilityLabel)
                }

                Spacer(minLength: 0)

                Button("Clear", action: onClear)
                    .buttonStyle(.plain)
                    .font(theme.bodyFont(12, .regular))
                    .foregroundStyle(theme.palette.dim)
                    .accessibilityLabel("Clear selection")
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
            .background(theme.palette.panelSolid)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.palette.hair)
                    .frame(height: theme.hairlineWidth)
            }
        }
    }
}
