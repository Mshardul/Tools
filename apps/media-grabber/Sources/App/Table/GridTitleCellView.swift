import AppKit
import GrabberKit

final class GridTitleCellView: NSTableCellView {
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func apply(title: String, state: JobState, tokens: DownloadsGridTokens) {
        label.stringValue = title
        label.font = tokens.cell
        label.textColor = tokens.text
        label.toolTip = title
        dot.layer?.backgroundColor = tokens.statusDotColor(for: state).cgColor
    }

    var cueColor: NSColor? {
        guard let color = dot.layer?.backgroundColor else { return nil }
        return NSColor(cgColor: color)
    }

    private func setup() {
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        label.drawsBackground = false
        label.isBordered = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(dot)
        addSubview(label)
        dot.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
