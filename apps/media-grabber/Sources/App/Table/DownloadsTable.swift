import GrabberKit
import SwiftUI

struct DownloadsTable: View {
    @Bindable var store: RowStore
    @Binding var columnConfig: ColumnConfig
    @Binding var scrollToRowID: UUID?
    let onAction: (UUID, RowAction) -> Void

    @Environment(\.theme) private var theme

    private var visibleColumns: [ColumnID] {
        columnConfig.orderedVisibleColumns()
    }

    private var tableWidth: CGFloat {
        ColumnMetrics.totalWidth(for: visibleColumns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ColumnsMenu(store: store, columnConfig: $columnConfig)
                .padding(.horizontal, Spacing.s4)
                .padding(.bottom, Spacing.s2)

            if let message = emptyMessage {
                emptyTableBody(message)
            } else {
                tableBody
            }
        }
    }

    private func emptyTableBody(_ message: String) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: true) {
                headerRow
                    .frame(width: tableWidth)
            }
            Text(message)
                .font(theme.skin.bodyFont(13, .regular))
                .foregroundStyle(theme.palette.faint)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.bottom, 80)
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyMessage: String? {
        TablePresentation.emptyBodyMessage(
            rowCount: store.rows.count,
            visibleCount: store.visibleRows.count,
            activeChip: store.activeChip,
            columnFilters: columnConfig.columnFilters
        )
    }

    private var tableBody: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .frame(width: tableWidth)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(store.visibleRows) { row in
                                DownloadRow(
                                    row: row,
                                    columns: visibleColumns,
                                    onAction: { onAction(row.id, $0) }
                                )
                                .id(row.id)
                            }
                        }
                        .frame(width: tableWidth)
                        .padding(.bottom, 80)
                    }
                    .frame(maxHeight: .infinity)
                    .onChange(of: scrollToRowID) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id, anchor: .center)
                        scrollToRowID = nil
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(visibleColumns, id: \.self) { column in
                headerCell(column)
                    .frame(width: ColumnMetrics.width(for: column), alignment: .leading)
                    .padding(.horizontal, Spacing.s2)
            }
        }
        .padding(.vertical, Spacing.s2)
        .background(theme.palette.panelSolid)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.palette.hair)
                .frame(height: theme.skin.hairlineWidth)
        }
    }

    private func headerCell(_ column: ColumnID) -> some View {
        HStack(spacing: Spacing.s1) {
            Text(ColumnMetrics.title(for: column))
                .font(theme.skin.monoFont(10, .semibold))
                .foregroundStyle(theme.palette.dim)
                .lineLimit(1)
            if ColumnMetrics.supportsSort(column) {
                Button {
                    var config = columnConfig
                    config.cycleSort(on: column)
                    columnConfig = config
                    store.setColumnConfig(config)
                } label: {
                    sortIcon(for: column)
                        .foregroundStyle(
                            columnConfig.sortColumn == column
                                ? theme.palette.accent
                                : theme.palette.faint
                        )
                }
                .buttonStyle(.plain)
            }
            if ColumnMetrics.supportsFilter(column) {
                filterMenu(for: column)
            }
            if column != .actions {
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func sortIcon(for column: ColumnID) -> some View {
        if columnConfig.sortColumn == column {
            switch columnConfig.sortDirection {
            case .ascending:
                Icon(kind: .sortAsc, size: 12)
            case .descending:
                Icon(kind: .sortDesc, size: 12)
            case nil:
                Icon(kind: .sortNeutral, size: 12)
            }
        } else {
            Icon(kind: .sortNeutral, size: 12)
        }
    }

    private func filterMenu(for column: ColumnID) -> some View {
        Menu {
            let values = filterValues(for: column)
            if values.isEmpty {
                Button("(none)") {}
                    .disabled(true)
            } else {
                ForEach(values, id: \.self) { value in
                    let selected = columnConfig.columnFilters[column]?.contains(value) == true
                    Button {
                        toggleFilter(column: column, value: value)
                    } label: {
                        if selected {
                            Label(value, systemImage: "checkmark")
                        } else {
                            Text(value)
                        }
                    }
                }
            }
        } label: {
            Icon(kind: .filter, size: 12)
                .foregroundStyle(
                    (columnConfig.columnFilters[column]?.isEmpty == false)
                        ? theme.palette.accent
                        : theme.palette.faint
                )
        }
        .menuStyle(.borderlessButton)
        .frame(width: 16, height: 16)
    }

    private func filterValues(for column: ColumnID) -> [String] {
        let values = store.rows.map { TablePresentation.cellText(for: $0, column: column) }
        return Array(Set(values)).sorted()
    }

    private func toggleFilter(column: ColumnID, value: String) {
        var selected = Set(columnConfig.columnFilters[column] ?? [])
        if selected.contains(value) {
            selected.remove(value)
        } else {
            selected.insert(value)
        }
        var config = columnConfig
        if selected.isEmpty {
            config.columnFilters.removeValue(forKey: column)
        } else {
            config.columnFilters[column] = Array(selected)
        }
        columnConfig = config
        store.setColumnConfig(config)
    }
}
