import GrabberKit
import SwiftUI

struct SkinnedPickerRow<Option: Hashable>: Identifiable {
    var id: Option
    var title: String
    var subtitle: String?
}

struct SkinnedPicker<Option: Hashable>: View {
    @Environment(\.theme) private var theme

    private let caption: String
    private let rows: [SkinnedPickerRow<Option>]
    @Binding private var selection: Option
    private let triggerLabelOverride: String?

    @State private var isPresented = false
    @State private var highlighted: Option?

    init(
        caption: String,
        rows: [SkinnedPickerRow<Option>],
        selection: Binding<Option>,
        triggerLabel: String? = nil
    ) {
        self.caption = caption
        self.rows = rows
        _selection = selection
        triggerLabelOverride = triggerLabel
    }

    var body: some View {
        Button {
            highlighted = selection
            isPresented.toggle()
        } label: {
            HStack(spacing: Spacing.s1) {
                Text(currentLabel)
                    .font(theme.bodyFont(12, .medium))
                    .foregroundStyle(theme.palette.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.palette.dim)
            }
            .padding(.horizontal, Spacing.s2)
            .padding(.vertical, Spacing.s1)
            .background(theme.palette.panel, in: triggerShape)
            .overlay(triggerShape.stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(currentLabel)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverBody
        }
    }

    private var currentLabel: String {
        triggerLabelOverride
            ?? rows.first { $0.id == selection }?.title
            ?? ""
    }

    private var triggerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.controlRadius)
    }

    private var popoverWidth: CGFloat {
        let longest = rows
            .flatMap { [$0.title, $0.subtitle ?? "", caption] }
            .map(\.count)
            .max() ?? 0
        let estimated = CGFloat(longest) * 7 + 56
        return min(340, max(180, estimated))
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .font(theme.monoFont(10, .medium))
                .textCase(.uppercase)
                .foregroundStyle(theme.palette.faint)
                .padding(.horizontal, Spacing.s3)
                .padding(.top, Spacing.s3)
                .padding(.bottom, Spacing.s1)
            Divider().overlay(theme.palette.hair)
            ForEach(rows) { row in
                rowView(row)
            }
            .padding(.vertical, 2)
        }
        .frame(width: popoverWidth, alignment: .leading)
        .background(theme.palette.panelSolid)
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius)
                .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius))
        .shadow(
            color: elevationColor,
            radius: theme.kind == .aurora ? 20 : 0,
            x: theme.kind == .aurora ? 0 : 3,
            y: theme.kind == .aurora ? 0 : 3
        )
        .accessibilityElement(children: .contain)
        .onKeyPress(.upArrow) { moveHighlight(-1); return .handled }
        .onKeyPress(.downArrow) { moveHighlight(1); return .handled }
        .onKeyPress(.return) { commitHighlight(); return .handled }
        .onKeyPress(.escape) { isPresented = false; return .handled }
    }

    private var elevationColor: Color {
        theme.kind == .aurora ? theme.palette.glowB : .black.opacity(0.35)
    }

    private func rowView(_ row: SkinnedPickerRow<Option>) -> some View {
        let isSelected = row.id == selection
        let isHighlighted = row.id == highlighted
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.palette.accent)
                .opacity(isSelected ? 1 : 0)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(theme.bodyFont(12, .regular))
                    .foregroundStyle(theme.palette.text)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(theme.bodyFont(11, .regular))
                        .foregroundStyle(theme.palette.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s1)
        .background(isHighlighted ? theme.palette.accent.opacity(0.12) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { select(row.id) }
        .onHover { hovering in
            if hovering {
                highlighted = row.id
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(row.title)
    }

    private func select(_ option: Option) {
        selection = option
        isPresented = false
    }

    private func moveHighlight(_ delta: Int) {
        let ids = rows.map(\.id)
        guard !ids.isEmpty else { return }
        let current = highlighted.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = min(max(current + delta, 0), ids.count - 1)
        highlighted = ids[next]
    }

    private func commitHighlight() {
        if let highlighted {
            select(highlighted)
        }
    }
}
