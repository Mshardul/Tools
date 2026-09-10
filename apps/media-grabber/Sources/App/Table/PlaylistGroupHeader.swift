import GrabberKit
import SwiftUI

struct PlaylistGroupHeader: View {
    let group: PlaylistGroup
    let tableWidth: CGFloat
    let onToggleCollapsed: (Bool) -> Void
    let onAction: (PlaylistGroupAction) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s3) {
            disclosureButton
            titleBlock
            Spacer(minLength: Spacing.s4)
            groupActions
        }
        .frame(width: tableWidth, alignment: .leading)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(theme.palette.accent2.opacity(0.10))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.palette.stroke)
                .frame(height: theme.hairlineWidth)
        }
    }

    private var disclosureButton: some View {
        Button {
            onToggleCollapsed(!group.isCollapsed)
        } label: {
            Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.palette.dim)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.isCollapsed ? "Expand playlist" : "Collapse playlist")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(group.title)
                .font(theme.bodyFont(13, .semibold))
                .foregroundStyle(theme.palette.text)
                .lineLimit(1)
            HStack(spacing: Spacing.s2) {
                Text("\(group.totalCount) items · \(group.completedCount) done")
                    .font(theme.monoFont(11, .regular))
                    .foregroundStyle(theme.palette.dim)
                miniProgress
            }
        }
    }

    private var miniProgress: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.palette.panelHi)
                Capsule()
                    .fill(theme.palette.accent)
                    .frame(width: max(0, proxy.size.width * group.rollupFraction))
            }
        }
        .frame(width: 86, height: 4)
    }

    private var groupActions: some View {
        HStack(spacing: Spacing.s2) {
            groupButton("Pause all", action: .pauseAll, enabled: canPauseAll)
            groupButton("Retry failed", action: .retryFailed, enabled: canRetryFailed)
            groupButton("Cancel all", action: .cancelAll, enabled: canCancelAll)
        }
    }

    private func groupButton(
        _ title: String,
        action: PlaylistGroupAction,
        enabled: Bool
    ) -> some View {
        Button(title) {
            guard enabled else { return }
            onAction(action)
        }
        .buttonStyle(.plain)
        .font(theme.bodyFont(12, .medium))
        .foregroundStyle(enabled ? theme.palette.text : theme.palette.faint)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }

    private var canPauseAll: Bool {
        group.runningCount > 0
    }

    private var canRetryFailed: Bool {
        group.failedCount > 0
    }

    private var canCancelAll: Bool {
        group.cancellableCount > 0
    }
}
