import GrabberKit
import SwiftUI

struct DownloadsTable: View {
    @Bindable var store: RowStore
    @Binding var columnConfig: ColumnConfig
    @Binding var scrollToRowID: UUID?
    let onAction: (UUID, RowAction) -> Void
    let onBatchAction: (RowAction) -> Void
    let onClearSelection: () -> Void
    let onPlaylistGroupAction: (UUID, PlaylistGroupAction) -> Void
    let onTogglePlaylistGroupCollapsed: (UUID, Bool) -> Void

    @Environment(\.theme) private var theme

    private var visibleColumns: [ColumnID] {
        columnConfig.orderedVisibleColumns()
    }

    private var tableWidth: CGFloat {
        ColumnMetrics.totalWidth(for: visibleColumns, config: columnConfig)
            + DownloadsGridColumns.selectionWidth
    }

    private var selectedSnapshots: [JobSnapshot] {
        let ids = store.selectedJobIDs
        return store.rows.compactMap { row in
            ids.contains(row.id) ? row.snapshot : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ColumnsMenu(store: store, columnConfig: $columnConfig)
                .padding(.horizontal, Spacing.s4)
                .padding(.bottom, Spacing.s2)

            SelectionBar(
                selectedCount: store.selectedJobIDs.count,
                verbs: BatchEligibility.offeredVerbs(snapshots: selectedSnapshots),
                onAction: onBatchAction,
                onClear: onClearSelection
            )

            if let message = emptyMessage {
                emptyTableBody(message)
            } else {
                DownloadsGridView(
                    store: store,
                    columnConfig: $columnConfig,
                    scrollToRowID: $scrollToRowID,
                    onAction: onAction,
                    onPlaylistGroupAction: onPlaylistGroupAction,
                    onTogglePlaylistGroupCollapsed: onTogglePlaylistGroupCollapsed
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func emptyTableBody(_ message: String) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: true) {
                emptyHeaderRow
                    .frame(width: tableWidth)
            }
            Text(message)
                .font(theme.bodyFont(13, .regular))
                .foregroundStyle(theme.palette.faint)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.bottom, 80)
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyMessage: String? {
        TablePresentation.emptyBodyMessage(
            rowCount: store.rows.count,
            visibleCount: store.visibleItems.count,
            activeChip: store.activeChip,
            columnFilters: columnConfig.columnFilters
        )
    }

    private var emptyHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: DownloadsGridColumns.selectionWidth)
            ForEach(visibleColumns, id: \.self) { column in
                Text(ColumnMetrics.title(for: column))
                    .font(theme.monoFont(10, .semibold))
                    .foregroundStyle(theme.palette.dim)
                    .lineLimit(1)
                    .frame(
                        width: ColumnMetrics.resolvedWidth(for: column, config: columnConfig),
                        alignment: .leading
                    )
                    .padding(.horizontal, Spacing.s2)
            }
        }
        .padding(.vertical, Spacing.s2)
        .background(theme.palette.panelSolid)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.palette.hair)
                .frame(height: theme.hairlineWidth)
        }
    }
}
