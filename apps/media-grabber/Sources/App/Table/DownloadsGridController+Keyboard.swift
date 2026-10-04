import AppKit
import GrabberKit

@MainActor
extension DownloadsGridController {
    func toggleSelectAllFromHeader() {
        if allVisibleChildrenSelected || visibleChildOrder.isEmpty {
            onClearSelection?()
        } else {
            onSelectAllVisible?()
        }
    }

    func clampKeyboardFocus() {
        if items.isEmpty {
            keyboardFocusRow = -1
        } else if keyboardFocusRow >= items.count {
            keyboardFocusRow = items.count - 1
        }
    }

    func tableBecameFirstResponder() {
        if keyboardFocusRow < 0, !items.isEmpty {
            keyboardFocusRow = 0
        }
        refreshKeyboardChrome()
    }

    func handleKeyboard(_ command: GridKeyboard.Command) {
        switch command {
        case let .move(delta, extending):
            moveKeyboardFocus(delta: delta, extending: extending)
        case .toggleSelection:
            toggleKeyboardSelection()
        case let .enterRowActions(reverse):
            // Shift-tab leaves the table. Tab enters this row's actions.
            if reverse {
                tableView.window?.selectPreviousKeyView(tableView)
            } else if !enterRowActions() {
                exitKeyboardRowForward()
            }
        case .ignored:
            break
        }
    }

    func moveKeyboardFocus(delta: Int, extending: Bool) {
        guard let next = GridKeyboardFocus.destination(
            from: keyboardFocusRow,
            delta: delta,
            rowCount: items.count
        ) else { return }
        keyboardFocusRow = next
        if extending {
            extendSelection(to: next)
        }
        tableView.scrollRowToVisible(next)
        refreshKeyboardChrome()
        announceKeyboardRow()
    }

    func toggleKeyboardSelection() {
        guard let id = childJobID(at: keyboardFocusRow) else { return }
        let next = RowSelection.toggle(id, in: selectedJobIDs)
        onSetSelectedJobIDs?(next, anchorAfterToggle(id, in: next))
    }

    func extendSelection(to row: Int) {
        guard let id = childJobID(at: row) else { return }
        let next = RowSelection.rangeSelecting(
            from: selectionAnchorID,
            to: id,
            visibleChildOrder: visibleChildOrder,
            replacing: selectedJobIDs
        )
        onSetSelectedJobIDs?(next, selectionAnchorID ?? id)
    }

    func refreshKeyboardChrome() {
        let rowCount = tableView.numberOfRows
        for row in 0 ..< rowCount {
            let focused = row == keyboardFocusRow
            if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) as? GridRowView {
                if rowView.isKeyboardFocused != focused {
                    rowView.isKeyboardFocused = focused
                    rowView.needsDisplay = true
                }
                if focused {
                    rowView.setAccessibilityLabel(accessibilitySummary(for: row))
                }
            }
            for button in focusButtons(in: row, makeIfNecessary: focused) {
                button.refusesFirstResponder = GridKeyView.refusesFirstResponder(
                    enabled: button.isEnabled,
                    rowIsKeyboardFocus: focused
                )
                button.focusRingType = .default
                button.onTab = { [weak self, weak button] reverse in
                    guard let self, let button else { return }
                    tab(from: button, reverse: reverse)
                }
            }
        }
    }

    func enterRowActions() -> Bool {
        guard keyboardFocusRow >= 0 else { return false }
        guard let first = focusButtons(in: keyboardFocusRow, makeIfNecessary: true).first(where: \.isEnabled) else {
            return false
        }
        return tableView.window?.makeFirstResponder(first) ?? false
    }

    func tab(from button: GridFocusButton, reverse: Bool) {
        let row = tableView.row(for: button)
        let enabled = focusButtons(in: row, makeIfNecessary: false).filter(\.isEnabled)
        guard let index = enabled.firstIndex(where: { $0 === button }) else {
            exitKeyboardRow(reverse: reverse)
            return
        }
        let next = reverse ? index - 1 : index + 1
        if enabled.indices.contains(next) {
            tableView.window?.makeFirstResponder(enabled[next])
            return
        }
        exitKeyboardRow(reverse: reverse)
    }

    func exitKeyboardRow(reverse: Bool) {
        if reverse {
            tableView.window?.makeFirstResponder(tableView)
            return
        }
        exitKeyboardRowForward()
    }

    func exitKeyboardRowForward() {
        let rowButtons = focusButtons(in: keyboardFocusRow, makeIfNecessary: false)
        let saved = rowButtons.map(\.refusesFirstResponder)
        rowButtons.forEach { $0.refusesFirstResponder = true }
        tableView.window?.selectNextKeyView(tableView)
        for (button, flag) in zip(rowButtons, saved) {
            button.refusesFirstResponder = flag
        }
    }

    func focusButtons(in row: Int, makeIfNecessary: Bool) -> [GridFocusButton] {
        guard row >= 0, row < tableView.numberOfRows else { return [] }
        var found: [GridFocusButton] = []
        for column in 0 ..< tableView.numberOfColumns {
            guard let view = tableView.view(atColumn: column, row: row, makeIfNecessary: makeIfNecessary) else {
                continue
            }
            collectFocusButtons(in: view, into: &found)
        }
        return found
    }

    func collectFocusButtons(in view: NSView, into found: inout [GridFocusButton]) {
        if let button = view as? GridFocusButton {
            found.append(button)
        }
        for subview in view.subviews {
            collectFocusButtons(in: subview, into: &found)
        }
    }

    func announceKeyboardRow() {
        let message = accessibilitySummary(for: keyboardFocusRow)
        guard !message.isEmpty else { return }
        NSAccessibility.post(
            element: tableView,
            notification: .announcementRequested,
            userInfo: [.announcement: message]
        )
    }

    func accessibilitySummary(for row: Int) -> String {
        guard row >= 0, row < items.count else { return "" }
        switch items[row] {
        case let .header(group):
            let state = group.isCollapsed ? "collapsed" : "expanded"
            return "\(group.title), playlist, \(state)"
        case let .child(model):
            let title = model.snapshot.title ?? "Download"
            let spoken = GridStatusAccessibility.label(
                status: TablePresentation.statusDisplay(for: model),
                remark: TablePresentation.remarkDisplay(for: model)
            )
            return "\(title), \(spoken)"
        }
    }
}
