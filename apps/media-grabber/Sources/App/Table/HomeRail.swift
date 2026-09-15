import SwiftUI

struct HomeRail: View {
    @Bindable var store: RowStore

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            railButton("All", .all, count: store.chipCounts.all)
            railButton("Downloading", .downloading, count: store.chipCounts.downloading)
            railButton("Done", .done, count: store.chipCounts.done)
            railButton(
                "Inactive",
                .inactive,
                count: store.chipCounts.inactive,
                showBadge: store.chipCounts.inactive > 0
            )
        }
        .padding(Spacing.s2)
        .frame(width: 160, alignment: .leading)
    }

    private func railButton(
        _ label: String,
        _ value: FilterChip,
        count: Int,
        showBadge: Bool = false
    ) -> some View {
        let active = store.activeChip == value
        return Button {
            store.activeChip = value
        } label: {
            HStack(spacing: Spacing.s1) {
                Text(label)
                Spacer()
                if showBadge {
                    Text("\(count)")
                        .font(theme.monoFont(10, .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(theme.palette.danger, in: Capsule())
                        .foregroundStyle(theme.palette.onAccent)
                }
            }
            .font(theme.bodyFont(12, active ? .semibold : .regular))
            .foregroundStyle(active ? theme.palette.text : theme.palette.dim)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                active ? theme.palette.panel : .clear,
                in: RoundedRectangle(cornerRadius: theme.chipRadius)
            )
        }
        .buttonStyle(.plain)
    }
}
