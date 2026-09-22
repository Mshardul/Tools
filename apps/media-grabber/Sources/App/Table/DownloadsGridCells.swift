import AppKit
import GrabberKit

@MainActor
extension DownloadsGridController {
    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn, row >= 0, row < items.count else { return nil }
        let item = items[row]
        let identifier = tableColumn.identifier

        if identifier == DownloadsGridColumns.selectionIdentifier {
            return selectionCell(for: item, tableView: tableView)
        }

        guard let columnID = DownloadsGridColumns.columnID(from: identifier) else { return nil }

        switch item {
        case let .header(group):
            return groupHeaderCell(for: group, column: columnID, tableView: tableView)
        case let .child(rowModel):
            return childCell(for: rowModel, column: columnID, tableView: tableView)
        }
    }

    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        isHeaderRow(row) ? 48 : 36
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("grid-row"),
            owner: nil
        ) as? GridRowView ?? GridRowView()
        view.identifier = NSUserInterfaceItemIdentifier("grid-row")
        view.tokens = tokens
        view.isGroupHeader = isHeaderRow(row)
        return view
    }

    private func selectionCell(for item: VisibleItem, tableView: NSTableView) -> NSView {
        switch item {
        case let .header(group):
            return disclosureCell(for: group, tableView: tableView)
        case let .child(row):
            let field = reusedLabel(
                identifier: NSUserInterfaceItemIdentifier("sel-cell"),
                in: tableView
            )
            applyTextStyle(field, font: tokens.body12, color: tokens.dim)
            field.stringValue = selectedJobIDs.contains(row.id) ? "☑" : "☐"
            field.alignment = .center
            return field
        }
    }

    private func disclosureCell(for group: PlaylistGroup, tableView: NSTableView) -> NSView {
        let button = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("disclosure"),
            owner: nil
        ) as? NSButton ?? makeIconButton(identifier: "disclosure")
        button.image = NSImage(
            systemSymbolName: group.isCollapsed ? "chevron.right" : "chevron.down",
            accessibilityDescription: nil
        )
        button.contentTintColor = tokens.dim
        button.target = self
        button.action = #selector(toggleGroupCollapsed(_:))
        button.tag = items.firstIndex { item in
            if case let .header(candidate) = item {
                return candidate.id == group.id
            }
            return false
        } ?? -1
        return button
    }

    private func childCell(
        for row: RowModel,
        column: ColumnID,
        tableView: NSTableView
    ) -> NSView {
        switch column {
        case .status:
            statusCell(for: row, tableView: tableView)
        case .progress:
            progressCell(for: row, tableView: tableView)
        case .actions:
            actionsCell(for: row, tableView: tableView)
        default:
            textCell(for: row, column: column, tableView: tableView)
        }
    }

    private func textCell(
        for row: RowModel,
        column: ColumnID,
        tableView: NSTableView
    ) -> NSView {
        let field = reusedLabel(
            identifier: NSUserInterfaceItemIdentifier("text-\(column.rawValue)"),
            in: tableView
        )
        applyTextStyle(field, font: tokens.body12, color: tokens.dim)
        field.stringValue = TablePresentation.cellText(for: row, column: column)
        field.toolTip = column == .title ? (row.snapshot.title ?? "") : nil
        return field
    }

    private func statusCell(for row: RowModel, tableView: NSTableView) -> NSView {
        let cell = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("status-cell"),
            owner: nil
        ) as? GridStatusCellView ?? GridStatusCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("status-cell")
        cell.apply(
            text: TablePresentation.statusDisplay(for: row),
            state: row.snapshot.state,
            remark: liveRemarkText(for: row),
            tokens: tokens
        )
        return cell
    }

    private func progressCell(for row: RowModel, tableView: NSTableView) -> NSView {
        let cell = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("progress-cell"),
            owner: nil
        ) as? GridProgressCellView ?? GridProgressCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("progress-cell")
        cell.apply(fraction: activeProgressFraction(for: row), tokens: tokens)
        return cell
    }

    private func actionsCell(for row: RowModel, tableView: NSTableView) -> NSView {
        let cell = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("actions-cell"),
            owner: nil
        ) as? GridActionsCellView ?? GridActionsCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("actions-cell")
        cell.apply(
            available: row.snapshot.availableActions,
            tokens: tokens,
            onAction: { [weak self] action in
                self?.onAction?(row.id, action)
            }
        )
        return cell
    }

    private func groupHeaderCell(
        for group: PlaylistGroup,
        column: ColumnID,
        tableView: NSTableView
    ) -> NSView {
        switch column {
        case .title:
            return groupTitleCell(for: group, tableView: tableView)
        case .actions:
            return groupActionsCell(for: group, tableView: tableView)
        default:
            let field = reusedLabel(
                identifier: NSUserInterfaceItemIdentifier("group-empty"),
                in: tableView
            )
            field.stringValue = ""
            return field
        }
    }

    private func groupTitleCell(for group: PlaylistGroup, tableView: NSTableView) -> NSView {
        let cell = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("group-title"),
            owner: nil
        ) as? GridGroupTitleCellView ?? GridGroupTitleCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("group-title")
        cell.apply(group: group, tokens: tokens)
        return cell
    }

    private func groupActionsCell(for group: PlaylistGroup, tableView: NSTableView) -> NSView {
        let cell = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("group-actions"),
            owner: nil
        ) as? GridGroupActionsCellView ?? GridGroupActionsCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("group-actions")
        cell.apply(
            group: group,
            tokens: tokens,
            onAction: { [weak self] action in
                self?.onPlaylistGroupAction?(group.id, action)
            }
        )
        return cell
    }

    func displayText(for item: VisibleItem, column: ColumnID) -> String {
        switch item {
        case let .header(group):
            guard column == .title || column == visibleColumns.first else { return "" }
            return "\(group.title) · \(group.totalCount) items · \(group.completedCount) done"
        case let .child(row):
            if column == .actions {
                return "…"
            }
            return TablePresentation.cellText(for: row, column: column)
        }
    }

    private func liveRemarkText(for row: RowModel) -> String {
        let text = TablePresentation.remarkDisplay(for: row)
        guard !text.isEmpty else { return TablePresentation.statusDisplay(for: row) }
        return text
    }

    private func activeProgressFraction(for row: RowModel) -> CGFloat? {
        guard let fraction = row.snapshot.progress?.fraction else { return nil }
        switch row.snapshot.state {
        case .running, .probing, .paused, .waitingForNetwork, .cooldown:
            return CGFloat(fraction)
        default:
            return nil
        }
    }

    private func reusedLabel(
        identifier: NSUserInterfaceItemIdentifier,
        in tableView: NSTableView
    ) -> NSTextField {
        (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField)
            ?? makeLabel(identifier: identifier)
    }

    private func makeLabel(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.identifier = identifier
        field.lineBreakMode = .byTruncatingTail
        field.drawsBackground = false
        field.isBordered = false
        field.isEditable = false
        field.isSelectable = false
        return field
    }

    private func applyTextStyle(_ field: NSTextField, font: NSFont, color: NSColor) {
        field.font = font
        field.textColor = color
        field.drawsBackground = false
    }

    private func makeIconButton(identifier: String) -> NSButton {
        let button = NSButton(frame: .zero)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        return button
    }

    @objc
    private func toggleGroupCollapsed(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < items.count, case let .header(group) = items[row] else { return }
        onTogglePlaylistGroupCollapsed?(group.id, !group.isCollapsed)
    }
}

final class GridTableView: NSTableView {
    var onRowClick: ((Int, Int, NSEvent.ModifierFlags) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        let column = column(at: point)
        guard row >= 0 else {
            super.mouseDown(with: event)
            return
        }
        onRowClick?(row, column, event.modifierFlags)
    }
}

final class GridRowView: NSTableRowView {
    var tokens = DownloadsGridTokens.aurora
    var isGroupHeader = false

    override func drawBackground(in dirtyRect: NSRect) {
        let fill = isGroupHeader
            ? tokens.accent2.withAlphaComponent(0.10)
            : tokens.ground
        fill.setFill()
        dirtyRect.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        tokens.accent.withAlphaComponent(0.18).setFill()
        dirtyRect.fill()
    }

    override func drawSeparator(in _: NSRect) {
        let color = isGroupHeader ? tokens.stroke : tokens.hair
        color.setStroke()
        let path = NSBezierPath()
        let lineY = bounds.minY + tokens.hairlineWidth / 2
        path.move(to: NSPoint(x: bounds.minX, y: lineY))
        path.line(to: NSPoint(x: bounds.maxX, y: lineY))
        path.lineWidth = tokens.hairlineWidth
        path.stroke()
    }
}
