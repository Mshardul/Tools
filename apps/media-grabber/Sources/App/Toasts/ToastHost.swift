import SwiftUI

struct ToastHost: View {
    let items: [ToastItem]
    let onDismiss: (UUID) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .trailing, spacing: Spacing.s2) {
            ForEach(items) { item in
                toastRow(item)
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(!items.isEmpty)
        .onChange(of: items.map(\.id)) { _, _ in
            guard let latest = items.last else { return }
            AccessibilityNotification.Announcement(latest.text).post()
        }
    }

    private func toastRow(_ item: ToastItem) -> some View {
        HStack(spacing: Spacing.s3) {
            Text(item.text)
                .font(theme.bodyFont(13, .regular))
                .foregroundStyle(theme.palette.text)
            if let title = item.actionTitle, let action = item.action {
                Button(title) {
                    Task { await action() }
                    onDismiss(item.id)
                }
                .buttonStyle(.plain)
                .font(theme.bodyFont(13, .semibold))
                .foregroundStyle(theme.palette.accent)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(
            theme.palette.panel,
            in: RoundedRectangle(cornerRadius: theme.cardRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius)
                .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
        )
        .frame(maxWidth: 320, alignment: .leading)
        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }
}
