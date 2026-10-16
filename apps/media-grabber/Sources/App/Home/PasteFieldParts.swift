import SwiftUI

struct ResolvedLinkTitle: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.palette.accent)
                .accessibilityHidden(true)
            Text(appModel.resolved?.title ?? "")
                .font(theme.bodyFont(14, .medium))
                .foregroundStyle(theme.palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(-1)
    }
}

struct ClearLinkButton: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            appModel.homeFieldText = ""
            appModel.clearResolved()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.palette.faint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear link")
    }
}
