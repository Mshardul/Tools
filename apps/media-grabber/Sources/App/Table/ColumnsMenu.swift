import GrabberKit
import SwiftUI

struct ColumnsMenu: View {
    @Bindable var store: RowStore
    @Binding var columnConfig: ColumnConfig

    @Environment(\.theme) private var theme
    @State private var columnsMenuOpen = false

    var body: some View {
        HStack(spacing: Spacing.s3) {
            chipRow
            Spacer()
            if showsClearFilters {
                Button("Clear filters", action: clearFilters)
                    .buttonStyle(.plain)
                    .font(theme.bodyFont(12, .regular))
                    .foregroundStyle(theme.palette.accent)
            }
            columnsButton
        }
    }

    private var chipRow: some View {
        HStack(spacing: Spacing.s2) {
            chip("All", .all, count: store.chipCounts.all)
            chip("Downloading", .downloading, count: store.chipCounts.downloading)
            chip("Done", .done, count: store.chipCounts.done)
            chip(
                "Needs attention",
                .needsAttention,
                count: store.chipCounts.needsAttention,
                showBadge: store.chipCounts.needsAttention > 0
            )
        }
    }

    private func chip(
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
            .padding(.vertical, Spacing.s1)
            .background(
                active ? theme.palette.panel : .clear,
                in: RoundedRectangle(cornerRadius: theme.chipRadius)
            )
        }
        .buttonStyle(.plain)
    }

    private var columnsButton: some View {
        Menu {
            ForEach(ColumnID.allCases, id: \.self) { column in
                let pinned = column == .actions || column == .title
                let visible = columnConfig.visibleColumns.contains(column)
                Button {
                    toggleColumn(column)
                } label: {
                    if visible {
                        Label(ColumnMetrics.title(for: column), systemImage: "checkmark")
                    } else {
                        Text(ColumnMetrics.title(for: column))
                    }
                }
                .disabled(pinned && column == .actions)
            }
        } label: {
            HStack(spacing: Spacing.s1) {
                Icon(kind: .columnsMenu, size: 14)
                Text("Columns")
            }
            .font(theme.bodyFont(12, .medium))
            .foregroundStyle(theme.palette.dim)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .background(
                theme.palette.panel,
                in: RoundedRectangle(cornerRadius: theme.chipRadius)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var showsClearFilters: Bool {
        !store.rows.isEmpty
            && store.visibleRows.isEmpty
            && TablePresentation.hasActiveFilters(
                activeChip: store.activeChip,
                columnFilters: columnConfig.columnFilters
            )
    }

    private func toggleColumn(_ column: ColumnID) {
        var config = columnConfig
        config.setColumnVisible(column, visible: !config.visibleColumns.contains(column))
        columnConfig = config
        store.setColumnConfig(config)
    }

    private func clearFilters() {
        store.activeChip = .all
        var config = columnConfig
        config.columnFilters = [:]
        columnConfig = config
        store.setColumnConfig(config)
    }
}
