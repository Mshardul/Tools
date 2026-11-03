import AppKit

final class GridQualityCellView: NSTableCellView {
    private let mark = NSView()
    private let label = GridLabelField(labelWithString: "")
    private var markWidth: NSLayoutConstraint?
    private var labelLead: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func apply(text: String, pickedAsBest: Bool, tokens: DownloadsGridTokens) {
        label.stringValue = text
        label.font = tokens.cell
        label.textColor = tokens.dim
        mark.isHidden = !pickedAsBest
        mark.layer?.backgroundColor = tokens.accent.cgColor
        markWidth?.constant = pickedAsBest ? 6 : 0
        labelLead?.constant = pickedAsBest ? 6 : 0
        toolTip = pickedAsBest ? "Picked as the best available" : nil
        let spoken = pickedAsBest ? "\(text). Picked as the best available" : text
        label.setAccessibilityLabel(spoken)
        setAccessibilityLabel(spoken)
    }

    private func setup() {
        wantsLayer = true
        mark.wantsLayer = true
        mark.setAccessibilityElement(false)
        mark.layer?.cornerRadius = 3
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail

        addSubview(mark)
        addSubview(label)
        mark.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        let width = mark.widthAnchor.constraint(equalToConstant: 0)
        let lead = label.leadingAnchor.constraint(equalTo: mark.trailingAnchor)
        markWidth = width
        labelLead = lead

        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: leadingAnchor),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.heightAnchor.constraint(equalToConstant: 6),
            width,
            lead,
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
