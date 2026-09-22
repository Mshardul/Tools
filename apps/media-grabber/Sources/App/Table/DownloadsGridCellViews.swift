import AppKit
import GrabberKit

final class GridStatusCellView: NSTableCellView {
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private let capsule = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func apply(text: String, state: JobState, remark: String, tokens: DownloadsGridTokens) {
        label.stringValue = text
        label.font = tokens.mono11Medium
        label.textColor = tokens.statusTextColor(for: state)
        toolTip = remark
        capsule.layer?.backgroundColor = tokens.panel.cgColor
        capsule.layer?.cornerRadius = 10
        dot.layer?.backgroundColor = tokens.statusDotColor(for: state).cgColor
    }

    private func setup() {
        wantsLayer = true
        capsule.wantsLayer = true
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        label.drawsBackground = false
        label.isBordered = false
        label.lineBreakMode = .byTruncatingTail

        addSubview(capsule)
        capsule.addSubview(dot)
        capsule.addSubview(label)
        capsule.translatesAutoresizingMaskIntoConstraints = false
        dot.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            capsule.centerYAnchor.constraint(equalTo: centerYAnchor),
            capsule.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            capsule.heightAnchor.constraint(equalToConstant: 22),

            dot.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 8),
            dot.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: capsule.centerYAnchor)
        ])
    }
}

final class GridProgressCellView: NSTableCellView {
    private let track = NSView()
    private let fill = NSView()
    private var fillWidth: NSLayoutConstraint?
    private var fraction: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func apply(fraction: CGFloat?, tokens: DownloadsGridTokens) {
        track.layer?.backgroundColor = tokens.panelHi.cgColor
        track.isHidden = fraction == nil
        fill.isHidden = fraction == nil
        self.fraction = max(0, min(1, fraction ?? 0))
        fill.layer?.backgroundColor = tokens.barFillStart.cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = track.bounds.width * fraction
        fillWidth?.constant = width
    }

    private func setup() {
        wantsLayer = true
        track.wantsLayer = true
        fill.wantsLayer = true
        track.layer?.cornerRadius = 2
        fill.layer?.cornerRadius = 2

        addSubview(track)
        track.addSubview(fill)
        track.translatesAutoresizingMaskIntoConstraints = false
        fill.translatesAutoresizingMaskIntoConstraints = false
        let width = fill.widthAnchor.constraint(equalToConstant: 0)
        fillWidth = width

        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            track.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            track.centerYAnchor.constraint(equalTo: centerYAnchor),
            track.heightAnchor.constraint(equalToConstant: 4),

            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            width
        ])
    }
}

final class GridActionsCellView: NSTableCellView {
    private var buttons: [NSButton] = []
    private var onAction: ((RowAction) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButtons()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButtons()
    }

    func apply(
        available: Set<RowAction>,
        tokens: DownloadsGridTokens,
        onAction: @escaping (RowAction) -> Void
    ) {
        self.onAction = onAction
        for (index, action) in RowAction.displayOrder.enumerated() {
            guard index < buttons.count else { break }
            let button = buttons[index]
            let enabled = TablePresentation.isActionEnabled(action, available: available)
            button.isEnabled = enabled
            button.contentTintColor = enabled ? tokens.text : tokens.faint
            button.toolTip = action.accessibilityLabel
            button.tag = index
        }
    }

    private func setupButtons() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        for action in RowAction.displayOrder {
            let button = NSButton(frame: .zero)
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.setButtonType(.momentaryChange)
            button.image = NSImage(
                systemSymbolName: action.iconKind.systemSymbolName,
                accessibilityDescription: action.accessibilityLabel
            )
            button.target = self
            button.action = #selector(handleAction(_:))
            button.setFrameSize(NSSize(width: 24, height: 24))
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
    }

    @objc
    private func handleAction(_ sender: NSButton) {
        let order = RowAction.displayOrder
        guard sender.tag >= 0, sender.tag < order.count, sender.isEnabled else { return }
        onAction?(order[sender.tag])
    }
}

final class GridGroupTitleCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let rollupLabel = NSTextField(labelWithString: "")
    private let track = NSView()
    private let fill = NSView()
    private var fillWidth: NSLayoutConstraint?
    private var fraction: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func apply(group: PlaylistGroup, tokens: DownloadsGridTokens) {
        titleLabel.stringValue = group.title
        titleLabel.font = tokens.body13Semibold
        titleLabel.textColor = tokens.text
        rollupLabel.stringValue = "\(group.totalCount) items · \(group.completedCount) done"
        rollupLabel.font = tokens.mono11
        rollupLabel.textColor = tokens.dim
        track.layer?.backgroundColor = tokens.panelHi.cgColor
        fill.layer?.backgroundColor = tokens.accent.cgColor
        fraction = CGFloat(group.rollupFraction)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        fillWidth?.constant = track.bounds.width * fraction
    }

    private func setup() {
        wantsLayer = true
        track.wantsLayer = true
        fill.wantsLayer = true
        track.layer?.cornerRadius = 2
        fill.layer?.cornerRadius = 2
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false
        titleLabel.lineBreakMode = .byTruncatingTail
        rollupLabel.drawsBackground = false
        rollupLabel.isBordered = false

        let stack = NSStackView(views: [titleLabel, rollupRow()])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func rollupRow() -> NSView {
        let row = NSStackView(views: [rollupLabel, track])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        track.translatesAutoresizingMaskIntoConstraints = false
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)
        let width = fill.widthAnchor.constraint(equalToConstant: 0)
        fillWidth = width
        NSLayoutConstraint.activate([
            track.widthAnchor.constraint(equalToConstant: 86),
            track.heightAnchor.constraint(equalToConstant: 4),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            width
        ])
        return row
    }
}

final class GridGroupActionsCellView: NSTableCellView {
    private let pauseButton = NSButton(title: "Pause all", target: nil, action: nil)
    private let retryButton = NSButton(title: "Retry failed", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel all", target: nil, action: nil)
    private var onAction: ((PlaylistGroupAction) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func apply(
        group: PlaylistGroup,
        tokens: DownloadsGridTokens,
        onAction: @escaping (PlaylistGroupAction) -> Void
    ) {
        self.onAction = onAction
        style(pauseButton, enabled: group.runningCount > 0, tokens: tokens)
        style(retryButton, enabled: group.failedCount > 0, tokens: tokens)
        style(cancelButton, enabled: group.cancellableCount > 0, tokens: tokens)
    }

    private func setup() {
        let stack = NSStackView(views: [pauseButton, retryButton, cancelButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        configure(pauseButton, action: #selector(pauseAll))
        configure(retryButton, action: #selector(retryFailed))
        configure(cancelButton, action: #selector(cancelAll))
    }

    private func configure(_ button: NSButton, action: Selector) {
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.target = self
        button.action = action
    }

    private func style(_ button: NSButton, enabled: Bool, tokens: DownloadsGridTokens) {
        button.isEnabled = enabled
        button.font = tokens.body12Medium
        button.contentTintColor = enabled ? tokens.text : tokens.faint
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: enabled ? tokens.text : tokens.faint,
                .font: tokens.body12Medium
            ]
        )
    }

    @objc private func pauseAll() {
        onAction?(.pauseAll)
    }

    @objc private func retryFailed() {
        onAction?(.retryFailed)
    }

    @objc private func cancelAll() {
        onAction?(.cancelAll)
    }
}
