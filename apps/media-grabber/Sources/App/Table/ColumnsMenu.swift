import GrabberKit
import SwiftUI

struct ColumnsMenu: View {
    @Bindable var store: RowStore
    @Binding var columnConfig: ColumnConfig

    @Environment(\.theme) private var theme
    @State private var columnsMenuOpen = false

    var body: some View {
        HStack(spacing: Spacing.s3) {
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
            && store.visibleItems.isEmpty
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
