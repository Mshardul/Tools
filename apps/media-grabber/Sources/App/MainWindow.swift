import GrabberKit
import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var appModel = appModel
        VStack(spacing: 0) {
            brandRow
            Divider().overlay(theme.palette.hair)
            healthStrip
            Divider().overlay(theme.palette.hair)
            page
        }
        .background(theme.palette.ground)
        .frame(minWidth: 760, minHeight: 480)
        .overlay {
            if let request = appModel.pendingConfirmation {
                ConfirmationDialog(request: request) { confirmed, suppress in
                    appModel.resolveConfirmation(confirmed, suppressFutures: suppress)
                }
            }
        }
    }

    private var jobRunning: Bool {
        false
    }

    private var brandRow: some View {
        @Bindable var appModel = appModel
        return HStack(spacing: Spacing.s3) {
            MotifView(isActive: jobRunning, size: 20)
            Text("MediaGrabber")
                .font(theme.skin.displayFont(17, .semibold))
                .foregroundStyle(theme.palette.text)
            Spacer()
            nav(for: $appModel.page)
        }
        .padding(.horizontal, Spacing.s5)
        .padding(.vertical, Spacing.s3)
    }

    private func nav(for page: Binding<AppModel.Page>) -> some View {
        HStack(spacing: Spacing.s1) {
            navButton("Home", .home, page)
            navButton("Preferences", .preferences, page)
            navButton("Diagnostics", .diagnostics, page)
        }
    }

    private func navButton(
        _ label: String,
        _ value: AppModel.Page,
        _ page: Binding<AppModel.Page>
    ) -> some View {
        let active = page.wrappedValue == value
        return Button { page.wrappedValue = value } label: {
            Text(label)
                .font(theme.skin.bodyFont(12, .medium))
                .foregroundStyle(active ? theme.palette.text : theme.palette.dim)
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s1)
                .background(
                    active ? theme.palette.panel : .clear,
                    in: RoundedRectangle(cornerRadius: theme.skin.chipRadius)
                )
        }
        .buttonStyle(.plain)
    }

    private var healthStrip: some View {
        HStack(spacing: Spacing.s2) {
            Circle()
                .fill(theme.palette.accent)
                .frame(width: 7, height: 7)
            Text("online")
                .font(theme.skin.monoFont(11, .regular))
                .foregroundStyle(theme.palette.dim)
            Spacer()
        }
        .padding(.horizontal, Spacing.s5)
        .padding(.vertical, Spacing.s2)
    }

    @ViewBuilder
    private var page: some View {
        switch appModel.page {
        case .home:
            HomeView()
        case .preferences:
            placeholder("Preferences")
        case .diagnostics:
            placeholder("Diagnostics")
        }
    }

    private func placeholder(_ title: String) -> some View {
        VStack {
            Spacer()
            Text(title)
                .font(theme.skin.bodyFont(13, .regular))
                .foregroundStyle(theme.palette.faint)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
