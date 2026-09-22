import AppKit
import GrabberKit
import SwiftUI

struct DownloadsGridView: NSViewRepresentable {
    @Bindable var store: RowStore
    @Binding var columnConfig: ColumnConfig
    @Binding var scrollToRowID: UUID?
    let onAction: (UUID, RowAction) -> Void
    let onPlaylistGroupAction: (UUID, PlaylistGroupAction) -> Void
    let onTogglePlaylistGroupCollapsed: (UUID, Bool) -> Void

    @Environment(\.theme) private var theme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        wire(controller: context.coordinator.controller)
        return context.coordinator.controller.rootView
    }

    func updateNSView(_: NSView, context: Context) {
        let controller = context.coordinator.controller
        wire(controller: controller)
        controller.sync(DownloadsGridSyncState(
            items: store.visibleItems,
            visibleColumns: columnConfig.orderedVisibleColumns(),
            columnConfig: columnConfig,
            selectedJobIDs: store.selectedJobIDs,
            selectionAnchorID: store.selectionAnchorID,
            visibleChildOrder: store.visibleChildOrder(),
            scrollToRowID: scrollToRowID,
            tokens: DownloadsGridTokens.make(theme: theme),
            filterValueProvider: { column in
                let values = store.rows.map { TablePresentation.cellText(for: $0, column: column) }
                return Array(Set(values)).sorted()
            }
        ))
    }

    private func wire(controller: DownloadsGridController) {
        controller.onAction = onAction
        controller.onPlaylistGroupAction = onPlaylistGroupAction
        controller.onTogglePlaylistGroupCollapsed = onTogglePlaylistGroupCollapsed
        controller.onClearScrollTarget = {
            scrollToRowID = nil
        }
        controller.onSetSelectedJobIDs = { ids, anchor in
            store.setSelectedJobIDs(ids, anchor: anchor)
        }
        controller.onSelectAllVisible = {
            store.selectAllVisibleChildren()
        }
        controller.onClearSelection = {
            store.clearSelection()
        }
        controller.onColumnWidthChange = { column, width in
            var config = columnConfig
            config.setColumnWidth(column, Double(width))
            columnConfig = config
        }
        controller.onColumnReorder = { source, destination in
            var config = columnConfig
            config.moveColumn(from: source, to: destination)
            columnConfig = config
        }
        controller.onCycleSort = { column in
            var config = columnConfig
            config.cycleSort(on: column)
            columnConfig = config
            store.setColumnConfig(config)
        }
        controller.onToggleFilter = { column, value in
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

    @MainActor
    final class Coordinator {
        let controller = DownloadsGridController()
    }
}
