import GrabberKit
import SwiftUI

@MainActor
protocol SuppressionStore {
    func isSuppressed(_ key: String) -> Bool
    func setSuppressed(_ key: String)
}

struct UserDefaultsSuppressionStore: SuppressionStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isSuppressed(_ key: String) -> Bool {
        defaults.bool(forKey: "mg.confirm.suppress.\(key)")
    }

    func setSuppressed(_ key: String) {
        defaults.set(true, forKey: "mg.confirm.suppress.\(key)")
    }
}

struct ConfirmationDialog: View {
    let request: ConfirmationRequest
    let onResolve: (_ confirmed: Bool, _ suppressFutures: Bool) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var suppressFutures = false
    @State private var shown = false

    var showsCancel: Bool {
        request.showsCancel
    }

    var body: some View {
        ZStack {
            theme.palette.ground.opacity(0.6)
                .ignoresSafeArea()

            card
                .scaleEffect(shown || reduceMotion ? 1 : 0.96)
                .opacity(shown || reduceMotion ? 1 : 0)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.16)) { shown = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("\(request.title). \(request.message)")
        .onExitCommand { onResolve(false, false) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            if request.isDestructive {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.palette.danger)
                    .font(.system(size: 20))
            }
            Text(request.title)
                .font(theme.skin.displayFont(15, .semibold))
                .foregroundStyle(theme.palette.headline)
            Text(request.message)
                .font(theme.skin.bodyFont(13, .regular))
                .foregroundStyle(theme.palette.dim)
                .fixedSize(horizontal: false, vertical: true)

            if request.suppressionKey != nil {
                Toggle("Don't ask again", isOn: $suppressFutures)
                    .font(theme.skin.bodyFont(12, .regular))
                    .foregroundStyle(theme.palette.dim)
            }

            HStack(spacing: Spacing.s2) {
                Spacer()
                if let cancelTitle = request.cancelTitle {
                    Button(cancelTitle) { onResolve(false, false) }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.plain)
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, Spacing.s2)
                        .background(theme.palette.panel, in: rounded)
                }
                Button(request.confirmTitle) { onResolve(true, suppressFutures) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.palette.onAccent)
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, Spacing.s2)
                    .background(confirmFill, in: rounded)
            }
        }
        .padding(Spacing.s5)
        .frame(maxWidth: 420)
        .background(theme.palette.panelSolid, in: cardShape)
        .overlay(cardShape.stroke(theme.palette.stroke, lineWidth: theme.skin.hairlineWidth))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }

    private var confirmFill: Color {
        request.isDestructive ? theme.palette.danger : theme.palette.accent
    }

    private var rounded: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.skin.controlRadius)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.skin.cardRadius)
    }
}
