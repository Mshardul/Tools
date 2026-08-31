import AppKit
import GrabberKit
import SwiftUI

struct DownloadsPane: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    @State private var namingPreset: FileNamingPreset = .title
    @State private var customTemplate = ""

    private static let qualityLadder: [(label: String, height: Int)] = [
        ("2160p", 2160),
        ("1440p", 1440),
        ("1080p", 1080),
        ("720p", 720),
        ("480p", 480),
        ("Best available", Int.max)
    ]

    var body: some View {
        @Bindable var prefs = appModel.prefs
        return VStack(alignment: .leading, spacing: 0) {
            PrefPaneHeader(.downloads)

            PrefRow("Downloads folder") {
                folderButton(prefs)
            }

            PrefRow(
                "Simultaneous downloads",
                helper: "Automatically reduced if a site rate-limits you."
            ) {
                VStack(alignment: .trailing, spacing: Spacing.s1) {
                    Stepper(
                        "\(prefs.maxConcurrentDownloads)",
                        value: $prefs.maxConcurrentDownloads,
                        in: 1 ... 6
                    )
                    .labelsHidden()
                    Text("\(prefs.maxConcurrentDownloads)")
                        .font(theme.monoFont(12, .regular))
                        .foregroundStyle(theme.palette.dim)
                    if shouldShowConcurrencyNote(
                        newValue: prefs.maxConcurrentDownloads,
                        runningCount: runningCount
                    ) {
                        ConcurrencyNote(runningCount: runningCount)
                    }
                }
            }

            PrefRow(
                "Automatic retries",
                helper: "Attempts before the app asks you what to do."
            ) {
                Stepper("\(prefs.maxAutoRetries)", value: $prefs.maxAutoRetries, in: 1 ... 5)
                    .labelsHidden()
                    .overlay(alignment: .trailing) {
                        Text("\(prefs.maxAutoRetries)")
                            .font(theme.monoFont(12, .regular))
                            .foregroundStyle(theme.palette.dim)
                            .offset(x: -44)
                    }
            }

            PrefRow("Media type") {
                SkinnedSegment(
                    [MediaType.video, .audio],
                    selection: $prefs.defaultMediaType
                ) { $0 == .video ? "Video" : "Audio" }
            }

            PrefRow(
                "Video quality",
                helper: "Highest available if the exact height isn't offered."
            ) {
                SkinnedPicker(
                    caption: "Resolution",
                    rows: Self.qualityLadder.map {
                        SkinnedPickerRow(id: $0.height, title: $0.label, subtitle: nil)
                    },
                    selection: $prefs.defaultVideoHeight,
                    triggerLabel: qualityLabel(prefs.defaultVideoHeight)
                )
            }

            PrefRow("Audio format") {
                SkinnedSegment(
                    [AudioFormat.m4a, .mp3],
                    selection: $prefs.defaultAudioFormat
                ) { $0.rawValue.uppercased() }
            }

            PrefRow("Filename format") {
                filenameControl(prefs)
            }

            PrefRow(
                "Clipboard detection",
                helper: "Offer to grab links you copy."
            ) {
                Toggle("", isOn: $prefs.detectClipboardLinks)
                    .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            namingPreset = FileNamingPreset.matching(appModel.prefs.filenameTemplate)
            customTemplate = appModel.prefs.filenameTemplate
        }
    }

    private var runningCount: Int {
        appModel.rowStore.rows.filter { $0.snapshot.state == .running }.count
    }

    private func qualityLabel(_ height: Int) -> String {
        Self.qualityLadder.first { $0.height == height }?.label ?? "\(height)p"
    }

    private func folderButton(_ prefs: Preferences) -> some View {
        let shown = (prefs.defaultDownloadFolder.path as NSString).abbreviatingWithTildeInPath
        return Button {
            chooseDefaultFolder(prefs)
        } label: {
            Text(shown)
                .font(theme.bodyFont(12, .medium))
                .foregroundStyle(theme.palette.text)
                .padding(.horizontal, Spacing.s2)
                .padding(.vertical, Spacing.s1)
                .background(
                    theme.palette.panel,
                    in: RoundedRectangle(cornerRadius: theme.controlRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: theme.controlRadius)
                        .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
                )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func filenameControl(_ prefs: Preferences) -> some View {
        VStack(alignment: .trailing, spacing: Spacing.s2) {
            SkinnedPicker(
                caption: "File naming",
                rows: FileNamingPreset.allCases.map {
                    SkinnedPickerRow(id: $0, title: $0.rowLabel, subtitle: $0.exampleSubtitle)
                },
                selection: Binding(
                    get: { namingPreset },
                    set: { applyPreset($0, prefs) }
                ),
                triggerLabel: namingPreset.rowLabel
            )
            if namingPreset == .custom {
                TextField("", text: $customTemplate)
                    .textFieldStyle(.plain)
                    .font(theme.monoFont(12, .regular))
                    .foregroundStyle(theme.palette.text)
                    .frame(width: 260)
                    .padding(Spacing.s1)
                    .background(
                        theme.palette.panel,
                        in: RoundedRectangle(cornerRadius: theme.controlRadius)
                    )
                    .onSubmit { commitCustom(prefs) }
            }
        }
    }

    private func applyPreset(_ preset: FileNamingPreset, _ prefs: Preferences) {
        namingPreset = preset
        if let template = preset.template {
            prefs.filenameTemplate = template
            customTemplate = template
        }
    }

    private func commitCustom(_ prefs: Preferences) {
        let trimmed = customTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            customTemplate = prefs.filenameTemplate
        } else {
            prefs.filenameTemplate = trimmed
        }
    }

    private func chooseDefaultFolder(_ prefs: Preferences) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            prefs.defaultDownloadFolder = url
        }
    }
}
