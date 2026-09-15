import SwiftUI

// Placeholders — real profile/site URLs pending, developer to fill in later.
private enum DeveloperLinks {
    static let repoOwner = "Mshardul"
    static let repoName = "Tools"
    static let githubProfile = URL(string: "https://github.com/\(repoOwner)")!
    // static let linkedIn = URL(string: "https://linkedin.com/in/TODO")!
    // static let personalSite = URL(string: "https://TODO")!
    // static let xProfile = URL(string: "https://x.com/TODO")!
    static let sourceCode = URL(string: "https://github.com/\(repoOwner)/\(repoName)")!
    static let issues = URL(string: "https://github.com/\(repoOwner)/\(repoName)/issues")!
    static let license = URL(string: "https://github.com/\(repoOwner)/\(repoName)/blob/main/LICENSE")!
}

struct DeveloperView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            avatar
                .padding(.bottom, Spacing.s3)
            Text("Shardul Lingwal")
                .font(theme.displayFont(20, .heavy))
                .foregroundStyle(theme.palette.headline)
            Text("Solo developer, building in the open.")
                .font(theme.bodyFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
                .padding(.top, 2)
                .padding(.bottom, Spacing.s4)
            Divider().overlay(theme.palette.hair)

            VStack(alignment: .leading, spacing: 0) {
                connectRow
                creditRow(title: "Source code", buttonTitle: "GitHub") {
                    appModel.openURLSink.open(DeveloperLinks.sourceCode)
                }
                creditRow(title: "Report an issue", buttonTitle: "GitHub Issues") {
                    appModel.openURLSink.open(DeveloperLinks.issues)
                }
                creditRow(title: "License", buttonTitle: "Open", showsDivider: false) {
                    appModel.openURLSink.open(DeveloperLinks.license)
                }
            }
            .padding(.top, Spacing.s2)
        }
        .frame(maxWidth: .infinity)
    }

    private var avatar: some View {
        Circle()
            .fill(theme.palette.panel)
            .overlay(Circle().stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth))
            .overlay(
                Text("SL")
                    .font(theme.displayFont(20, .bold))
                    .foregroundStyle(theme.palette.text)
            )
            .frame(width: 56, height: 56)
    }

    private var connectRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Connect with me")
                .font(theme.monoFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
            Spacer()
            HStack(spacing: Spacing.s2) {
                iconLink(title: "GitHub", glyph: "GH") {
                    appModel.openURLSink.open(DeveloperLinks.githubProfile)
                }
                // LinkedIn/personal site/X links pending real URLs — rows omitted until provided.
            }
        }
        .padding(.vertical, Spacing.s2)
        .overlay(alignment: .bottom) {
            Divider().overlay(theme.palette.hair)
        }
    }

    private func iconLink(title: String, glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(theme.bodyFont(11, .semibold))
                .foregroundStyle(theme.palette.text)
                .frame(width: 28, height: 28)
                .background(theme.palette.panel, in: Circle())
                .overlay(Circle().stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func creditRow(
        title: String,
        buttonTitle: String,
        showsDivider: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(theme.monoFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
            Spacer()
            Button(action: action) {
                Text(buttonTitle)
                    .font(theme.displayFont(12, .semibold))
                    .foregroundStyle(theme.palette.text)
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, Spacing.s2)
                    .background(theme.palette.panel, in: RoundedRectangle(cornerRadius: theme.chipRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.chipRadius)
                            .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Spacing.s2)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider().overlay(theme.palette.hair)
            }
        }
    }
}
