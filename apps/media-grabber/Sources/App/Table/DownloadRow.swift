import GrabberKit
import SwiftUI

struct DownloadRow: View {
    let row: RowModel
    let columns: [ColumnID]
    let onAction: (RowAction) -> Void

    @Environment(\.theme) private var theme

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
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.palette.hair)
                .frame(height: theme.skin.hairlineWidth)
        }
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
                .font(theme.skin.bodyFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var statusCell: some View {
        HStack(spacing: Spacing.s1) {
            Circle()
                .fill(RowStatusStyle.dotColor(for: row.snapshot.state, palette: theme.palette))
                .frame(width: 6, height: 6)
            Text(TablePresentation.statusDisplay(for: row))
                .font(theme.skin.monoFont(11, .medium))
                .foregroundStyle(
                    RowStatusStyle.textColor(for: row.snapshot.state, palette: theme.palette)
                )
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, Spacing.s1)
        .background(theme.palette.panel, in: Capsule())
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
