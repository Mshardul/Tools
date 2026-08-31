import SwiftUI

struct PrefRow<Control: View>: View {
    @Environment(\.theme) private var theme

    private let label: String
    private let helper: String?
    private let control: () -> Control

    init(_ label: String, helper: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.helper = helper
        self.control = control
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(label)
                        .font(theme.bodyFont(13, .semibold))
                        .foregroundStyle(theme.palette.text)
                    if let helper {
                        Text(helper)
                            .font(theme.bodyFont(11.5, .regular))
                            .foregroundStyle(theme.palette.dim)
                    }
                }
                Spacer(minLength: Spacing.s4)
                control()
            }
            .padding(.vertical, Spacing.s3)
            Divider().overlay(theme.palette.hair)
        }
    }
}

struct PrefPaneHeader: View {
    @Environment(\.theme) private var theme
    private let pane: PreferencesPane

    init(_ pane: PreferencesPane) {
        self.pane = pane
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(pane.subtitle)
                .font(theme.bodyFont(11.5, .regular))
                .foregroundStyle(theme.palette.dim)
            Text(pane.title)
                .font(theme.displayFont(20, .heavy))
                .foregroundStyle(theme.palette.headline)
            Divider().overlay(theme.palette.hair)
        }
        .padding(.bottom, Spacing.s2)
    }
}

struct PrefSteplessPane: View {
    @Environment(\.theme) private var theme
    private let pane: PreferencesPane
    private let line: String

    init(_ pane: PreferencesPane, line: String) {
        self.pane = pane
        self.line = line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            PrefPaneHeader(pane)
            Text(line)
                .font(theme.bodyFont(12, .regular))
                .foregroundStyle(theme.palette.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
