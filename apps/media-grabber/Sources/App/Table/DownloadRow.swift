import GrabberKit
import SwiftUI

enum PlaylistSpineSegment {
    case none
    case only
    case first
    case middle
    case last
}

struct DownloadRow: View {
    let row: RowModel
    let columns: [ColumnID]
    let spineSegment: PlaylistSpineSegment
    let onAction: (RowAction) -> Void

    @Environment(\.theme) private var theme

    private var isPlaylistChild: Bool {
        spineSegment != .none
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { column in
                cell(for: column)
                    .frame(width: ColumnMetrics.width(for: column), alignment: .leading)
                    .padding(.horizontal, Spacing.s2)
            }
        }
        .padding(.vertical, Spacing.s2)
        .background(theme.palette.ground)
        .overlay {
            if isPlaylistChild {
                spineOverlay
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.palette.hair)
                .frame(height: theme.hairlineWidth)
                .padding(.leading, isPlaylistChild ? contentIndent : 0)
        }
    }

    private var contentIndent: CGFloat {
        Spacing.s6
    }

    private var spineX: CGFloat {
        Spacing.s4
    }

    private var spineOverlay: some View {
        GeometryReader { proxy in
            let midY = proxy.size.height / 2
            let stroke = theme.palette.stroke
            let width = theme.hairlineWidth

            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: spineX, y: midY))
                path.addLine(to: CGPoint(x: contentIndent, y: midY))
                context.stroke(path, with: .color(stroke), lineWidth: width)

                switch spineSegment {
                case .none, .only:
                    break
                case .first:
                    path = Path()
                    path.move(to: CGPoint(x: spineX, y: midY))
                    path.addLine(to: CGPoint(x: spineX, y: size.height))
                    context.stroke(path, with: .color(stroke), lineWidth: width)
                case .middle:
                    path = Path()
                    path.move(to: CGPoint(x: spineX, y: 0))
                    path.addLine(to: CGPoint(x: spineX, y: size.height))
                    context.stroke(path, with: .color(stroke), lineWidth: width)
                case .last:
                    path = Path()
                    path.move(to: CGPoint(x: spineX, y: 0))
                    path.addLine(to: CGPoint(x: spineX, y: midY))
                    context.stroke(path, with: .color(stroke), lineWidth: width)
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cell(for column: ColumnID) -> some View {
        switch column {
        case .status:
            statusCell
        case .progress:
            progressCell
        case .actions:
            actionBar
        default:
            Text(TablePresentation.cellText(for: row, column: column))
                .font(theme.bodyFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, playlistIndent(for: column))
        }
    }

    private func playlistIndent(for column: ColumnID) -> CGFloat {
        isPlaylistChild && column == .title ? contentIndent - Spacing.s2 : 0
    }

    private var statusCell: some View {
        let deadline = row.snapshot.cooldownUntil ?? row.hostCooldownDeadline
        return HStack(spacing: Spacing.s1) {
            Circle()
                .fill(RowStatusStyle.dotColor(for: row.snapshot.state, palette: theme.palette))
                .frame(width: 6, height: 6)
            if let deadline, deadline > .now {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    statusLabel(
                        "\(TablePresentation.statusDisplay(for: row)) — "
                            + CountdownFormat.mmss(until: deadline, now: context.date)
                    )
                }
            } else {
                statusLabel(TablePresentation.statusDisplay(for: row))
            }
        }
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, Spacing.s1)
        .background(theme.palette.panel, in: Capsule())
    }

    private func statusLabel(_ text: String) -> some View {
        Text(text)
            .font(theme.monoFont(11, .medium))
            .foregroundStyle(
                RowStatusStyle.textColor(for: row.snapshot.state, palette: theme.palette)
            )
            .lineLimit(1)
    }

    @ViewBuilder
    private var progressCell: some View {
        if let fraction = row.snapshot.progress?.fraction, isActiveState {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.palette.panelHi)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [theme.palette.barFillStart, theme.palette.barFillEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, proxy.size.width * fraction))
                }
            }
            .frame(height: 4)
        } else {
            Color.clear.frame(height: 4)
        }
    }

    private var actionBar: some View {
        HStack(spacing: Spacing.s1) {
            ForEach(RowAction.displayOrder, id: \.self) { action in
                actionButton(action)
            }
        }
    }

    private func actionButton(_ action: RowAction) -> some View {
        let enabled = TablePresentation.isActionEnabled(
            action,
            available: row.snapshot.availableActions
        )
        return Button {
            guard enabled else { return }
            onAction(action)
        } label: {
            Icon(kind: action.iconKind, size: 14)
                .foregroundStyle(enabled ? theme.palette.text : theme.palette.faint)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityAddTraits(enabled ? [] : .isButton)
    }

    private var isActiveState: Bool {
        switch row.snapshot.state {
        case .running, .probing, .paused, .waitingForNetwork, .cooldown: true
        default: false
        }
    }
}
