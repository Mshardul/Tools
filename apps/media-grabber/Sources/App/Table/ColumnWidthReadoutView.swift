import AppKit

enum ColumnWidthReadout {
    static func format(_ width: CGFloat) -> String {
        "\(Int(width.rounded())) pt"
    }
}

final class ColumnWidthReadoutView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
        layer?.cornerRadius = 4
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.setAccessibilityElement(false)
        label.textColor = .labelColor
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(width: CGFloat, near point: NSPoint) {
        label.stringValue = ColumnWidthReadout.format(width)
        label.sizeToFit()
        frame = NSRect(
            x: point.x - label.frame.width / 2 - 6,
            y: point.y - 24,
            width: label.frame.width + 12,
            height: label.frame.height + 4
        )
    }
}
