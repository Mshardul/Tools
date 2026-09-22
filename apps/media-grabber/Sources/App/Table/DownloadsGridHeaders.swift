import AppKit
import GrabberKit

enum GridHeaderHit {
    case sort
    case filter
    case title
}

final class GridHeaderCell: NSTableHeaderCell {
    var tokens = DownloadsGridTokens.aurora
    var showsSort = false
    var showsFilter = false
    var sortKind: IconKind = .sortNeutral
    var sortActive = false
    var filterActive = false

    override func draw(withFrame cellFrame: NSRect, in _: NSView) {
        tokens.panelSolid.setFill()
        cellFrame.fill()

        let title = stringValue as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: tokens.mono10Semibold,
            .foregroundColor: tokens.dim
        ]
        let titleSize = title.size(withAttributes: titleAttrs)
        let titleRect = NSRect(
            x: cellFrame.minX + 8,
            y: cellFrame.midY - titleSize.height / 2,
            width: min(titleSize.width, cellFrame.width - 16 - iconReserve),
            height: titleSize.height
        )
        title.draw(in: titleRect, withAttributes: titleAttrs)

        var iconX = titleRect.maxX + 4
        if showsSort {
            drawSymbol(
                sortKind.systemSymbolName,
                at: NSPoint(x: iconX, y: cellFrame.midY - 6),
                tint: sortActive ? tokens.accent : tokens.faint
            )
            iconX += 14
        }
        if showsFilter {
            drawSymbol(
                IconKind.filter.systemSymbolName,
                at: NSPoint(x: iconX, y: cellFrame.midY - 6),
                tint: filterActive ? tokens.accent : tokens.faint
            )
        }

        tokens.hair.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cellFrame.minX, y: cellFrame.minY + 0.5))
        path.line(to: NSPoint(x: cellFrame.maxX, y: cellFrame.minY + 0.5))
        path.lineWidth = tokens.hairlineWidth
        path.stroke()
    }

    func hitTest(_ point: NSPoint, in cellFrame: NSRect) -> GridHeaderHit {
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: tokens.mono10Semibold]
        let titleWidth = (stringValue as NSString).size(withAttributes: titleAttrs).width
        var iconX = cellFrame.minX + 8 + min(titleWidth, cellFrame.width - 16 - iconReserve) + 4

        if showsSort {
            let sortRect = NSRect(x: iconX, y: cellFrame.minY, width: 14, height: cellFrame.height)
            if sortRect.contains(point) {
                return .sort
            }
            iconX += 14
        }
        if showsFilter {
            let filterRect = NSRect(x: iconX, y: cellFrame.minY, width: 14, height: cellFrame.height)
            if filterRect.contains(point) {
                return .filter
            }
        }
        return .title
    }

    private var iconReserve: CGFloat {
        (showsSort ? 14 : 0) + (showsFilter ? 14 : 0) + 8
    }

    private func drawSymbol(_ name: String, at origin: NSPoint, tint: NSColor) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return
        }
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let sized = image.withSymbolConfiguration(config) ?? image
        sized.tinted(with: tint).draw(
            in: NSRect(origin: origin, size: NSSize(width: 12, height: 12))
        )
    }
}

extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}

final class DownloadsGridHeaderView: NSTableHeaderView {
    var onDoubleClickDivider: ((Int) -> Void)?
    var onHeaderAffordanceClick: ((Int, GridHeaderHit, NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, let columnIndex = resizeHandleColumnIndex(at: point) {
            onDoubleClickDivider?(columnIndex)
            return
        }

        let columnIndex = column(at: point)
        if let headerCell = headerCell(at: columnIndex) {
            let columnFrame = headerRect(ofColumn: columnIndex)
            let hit = headerCell.hitTest(point, in: columnFrame)
            if hit == .sort || hit == .filter {
                onHeaderAffordanceClick?(columnIndex, hit, event)
                return
            }
        }

        super.mouseDown(with: event)
    }

    private func headerCell(at columnIndex: Int) -> GridHeaderCell? {
        guard columnIndex >= 0, let tableView else { return nil }
        guard columnIndex < tableView.tableColumns.count else { return nil }
        return tableView.tableColumns[columnIndex].headerCell as? GridHeaderCell
    }

    private func resizeHandleColumnIndex(at point: NSPoint) -> Int? {
        guard let tableView else { return nil }
        var edgeX: CGFloat = 0
        for (index, column) in tableView.tableColumns.enumerated() {
            edgeX += column.width
            if abs(point.x - edgeX) <= 4 {
                return index
            }
        }
        return nil
    }
}
