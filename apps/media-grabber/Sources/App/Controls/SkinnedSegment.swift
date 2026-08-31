import SwiftUI

struct SkinnedSegment<Option: Hashable>: View {
    @Environment(\.theme) private var theme
    private let options: [Option]
    @Binding private var selection: Option
    private let label: (Option) -> String

    init(_ options: [Option], selection: Binding<Option>, label: @escaping (Option) -> String) {
        self.options = options
        _selection = selection
        self.label = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                segment(option)
            }
        }
        .padding(2)
        .background(theme.palette.panel, in: shape)
        .overlay(shape.stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth))
        .fixedSize()
        .focusable()
        .onMoveCommand(perform: move)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Segmented control")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.chipRadius)
    }

    private func segment(_ option: Option) -> some View {
        let selected = option == selection
        return Text(label(option))
            .font(theme.bodyFont(12, .medium))
            .foregroundStyle(selected ? theme.palette.text : theme.palette.dim)
            .frame(minWidth: 52)
            .padding(.horizontal, Spacing.s2)
            .padding(.vertical, Spacing.s1)
            .background(selected ? theme.palette.panelSolid : .clear, in: shape)
            .contentShape(Rectangle())
            .onTapGesture { selection = option }
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(label(option))
    }

    private func move(_ direction: MoveCommandDirection) {
        guard let index = options.firstIndex(of: selection) else { return }
        if direction == .left, index > 0 {
            selection = options[index - 1]
        }
        if direction == .right, index < options.count - 1 {
            selection = options[index + 1]
        }
    }
}
