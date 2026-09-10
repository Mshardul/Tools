import GrabberKit
import SwiftUI
import UniformTypeIdentifiers

struct MainWindow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(IncomingLinkController.self) private var incomingLinks
    @Environment(\.theme) private var theme
    @State private var bannerHeight: CGFloat = 0

    var body: some View {
        @Bindable var appModel = appModel
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                brandRow
                Divider().overlay(theme.palette.hair)
                HealthStrip(chips: appModel.healthChips) { chip in
                    if chip.id == "shield" {
                        Task { await appModel.restartShield() }
                    }
                }
                Divider().overlay(theme.palette.hair)
                page
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear.frame(
                            height: appModel.bannerContent == nil ? 0 : bannerHeight + Spacing.s4
                        )
                    }
            }
            .background(theme.palette.ground)
            .frame(minWidth: 820, minHeight: 560)
            .onDrop(of: [.url, .plainText], isTargeted: nil) { providers in
                handleDrop(providers)
            }

            WarningBanner(content: appModel.bannerContent)
                .onPreferenceChange(BannerHeightKey.self) { bannerHeight = $0 }
        }
        .overlay {
            if let request = appModel.pendingConfirmation {
                ConfirmationDialog(request: request) { confirmed, suppress in
                    appModel.resolveConfirmation(confirmed, suppressFutures: suppress)
                }
            }
        }
    }

    private var jobRunning: Bool {
        appModel.rowStore.rows.contains { $0.snapshot.state == .running }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in await incomingLinks.handlePlainText(url.absoluteString) }
            }
            return true
        }
        if provider.canLoadObject(ofClass: String.self) {
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                guard let text else { return }
                Task { @MainActor in await incomingLinks.handlePlainText(text) }
            }
            return true
        }
        return false
    }

    private var brandRow: some View {
        @Bindable var appModel = appModel
        return HStack(spacing: Spacing.s3) {
            MotifView(isActive: jobRunning, size: 20)
            Text("MediaGrabber")
                .font(theme.displayFont(17, .semibold))
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
            navButton("Preferences", .preferences(), page)
            navButton("Diagnostics", .diagnostics, page)
        }
    }

    private func isActive(_ page: AppModel.Page, _ target: AppModel.Page) -> Bool {
        switch (page, target) {
        case (.preferences, .preferences): true
        default: page == target
        }
    }

    private func navButton(
        _ label: String,
        _ value: AppModel.Page,
        _ page: Binding<AppModel.Page>
    ) -> some View {
        let active = isActive(page.wrappedValue, value)
        return Button { page.wrappedValue = value } label: {
            Text(label)
                .font(theme.bodyFont(12, .medium))
                .foregroundStyle(active ? theme.palette.text : theme.palette.dim)
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s1)
                .background(
                    active ? theme.palette.panel : .clear,
                    in: RoundedRectangle(cornerRadius: theme.chipRadius)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var page: some View {
        switch appModel.page {
        case .home:
            HomeView()
        case let .preferences(pane):
            PreferencesView(initialPane: pane)
        case .diagnostics:
            placeholder("Diagnostics")
        }
    }

    private func placeholder(_ title: String) -> some View {
        VStack {
            Spacer()
            Text(title)
                .font(theme.bodyFont(13, .regular))
                .foregroundStyle(theme.palette.faint)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
