import AppKit
import Foundation
import GrabberKit
import Observation
import SwiftUI

@MainActor
@Observable
final class DiagnosticsPaneModel {
    enum CanaryResult: Equatable {
        case notRun
        case passed
        case failed
    }

    private(set) var canaryResult: CanaryResult = .notRun
    private(set) var reportText: String = ""
    private(set) var lastRunAt: Date?
    private(set) var isRunningCheck = false
    private(set) var isReinstallingYtDlp = false
    private(set) var latestReport: EnvironmentReport?

    static let emptyPlaceholder = "Not checked yet."

    struct PresentedRow: Equatable {
        let label: String
        let value: String
        let tone: RowTone
    }

    enum RowTone: Equatable {
        case ok, warn, bad, neutral
    }

    var hasReport: Bool {
        lastRunAt != nil
    }

    var presentedRows: [PresentedRow] {
        guard hasReport else { return [] }
        return [
            PresentedRow(label: "Test run", value: canaryValue, tone: canaryTone),
            PresentedRow(label: "Downloader", value: downloaderValue, tone: downloaderTone),
            PresentedRow(label: "Media tools", value: mediaToolsValue, tone: mediaToolsTone)
        ]
    }

    private var canaryValue: String {
        switch canaryResult {
        case .notRun: "not yet run this session"
        case .passed: "passed"
        case .failed: "failed"
        }
    }

    private var canaryTone: RowTone {
        switch canaryResult {
        case .notRun: .neutral
        case .passed: .ok
        case .failed: .bad
        }
    }

    private var downloaderValue: String {
        guard let version = latestReport?.ytDlp?.version else { return "not found" }
        return switch latestReport?.ytDlpDriftVerdict {
        case .current, nil: "\(version) · current"
        case .drift: "\(version) · update available"
        case .unknown: version
        }
    }

    private var downloaderTone: RowTone {
        switch latestReport?.ytDlpDriftVerdict {
        case .current, nil: latestReport?.ytDlp == nil ? .bad : .ok
        case .drift: .warn
        case .unknown: .neutral
        }
    }

    private var mediaToolsValue: String {
        latestReport?.ffmpeg?.version ?? "not found"
    }

    private var mediaToolsTone: RowTone {
        latestReport?.ffmpeg == nil ? .bad : .ok
    }

    private let metadataProbe: MetadataProbing
    private let environmentProbe: EnvironmentProbing
    private let ytDlpUpdater: YtDlpUpdating
    private let sharePresenter: SharePresenting
    private let logReader: LogReading
    private let pasteboardMarker: (String) -> Void

    init(
        metadataProbe: MetadataProbing,
        environmentProbe: EnvironmentProbing,
        ytDlpUpdater: YtDlpUpdating,
        sharePresenter: SharePresenting,
        logReader: LogReading = AppLogReader(),
        pasteboardMarker: @escaping (String) -> Void = { _ in }
    ) {
        self.metadataProbe = metadataProbe
        self.environmentProbe = environmentProbe
        self.ytDlpUpdater = ytDlpUpdater
        self.sharePresenter = sharePresenter
        self.logReader = logReader
        self.pasteboardMarker = pasteboardMarker
    }

    func runCheck() async {
        isRunningCheck = true
        defer { isRunningCheck = false }
        let probeResult = await metadataProbe.probe(CanaryProbe.url)
        canaryResult = probeResult.isCanarySuccess ? .passed : .failed
        let report = await environmentProbe.probe()
        latestReport = report
        reportText = Self.formatReport(canary: canaryResult, report: report)
        lastRunAt = Date()
    }

    func reinstallYtDlp() async {
        isReinstallingYtDlp = true
        defer { isReinstallingYtDlp = false }
        _ = await ytDlpUpdater.reinstallToMinimum()
        await runCheck()
    }

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText, forType: .string)
        pasteboardMarker(reportText)
    }

    func shareDiagnosticBundle() {
        let filename = "MediaGrabber-Diagnostics.zip"
        guard let data = try? DiagnosticBundle.build(
            appLogTail: logReader.appLogTail(),
            jobLog: logReader.mostRecentJobLog(),
            report: reportText
        ) else {
            return
        }
        sharePresenter.share(data: data, filename: filename)
        pasteboardMarker(filename)
    }

    private static func formatReport(canary: CanaryResult, report: EnvironmentReport) -> String {
        var lines: [String] = []
        lines.append("Test run: \(canary == .passed ? "passed" : "failed")")
        if let ytDlp = report.ytDlp {
            lines.append("Downloader: \(ytDlp.version)\(driftSuffix(report))")
        } else {
            lines.append("Downloader: not found")
        }
        if let ffmpeg = report.ffmpeg {
            lines.append("Media tools: \(ffmpeg.version)")
        } else {
            lines.append("Media tools: not found")
        }
        return lines.joined(separator: "\n")
    }

    private static func driftSuffix(_ report: EnvironmentReport) -> String {
        switch report.ytDlpDriftVerdict {
        case .current, nil: " · current"
        case .drift: " · update available"
        case .unknown: ""
        }
    }
}

private extension Result<MediaMetadata, MetadataError> {
    var isCanarySuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

struct DiagnosticsPane: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    @State private var model: DiagnosticsPaneModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(PreferencesPane.diagnostics.subtitle)
                .font(theme.bodyFont(11.5, .regular))
                .foregroundStyle(theme.palette.dim)
                .padding(.bottom, Spacing.s3)
            Divider().overlay(theme.palette.hair)

            if let model {
                lastRunLine(model)
                if model.hasReport {
                    reportRows(model)
                    actionButtons(model)
                } else {
                    Text(DiagnosticsPaneModel.emptyPlaceholder)
                        .font(theme.bodyFont(13, .regular))
                        .foregroundStyle(theme.palette.dim)
                        .padding(.top, Spacing.s3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            if model == nil {
                model = makeModel()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(PreferencesPane.diagnostics.title)
                .font(theme.displayFont(20, .heavy))
                .foregroundStyle(theme.palette.headline)
            Spacer()
            Button {
                Task { await model?.runCheck() }
            } label: {
                Text("Run check")
                    .font(theme.displayFont(13, .bold))
                    .foregroundStyle(theme.palette.onAccent)
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, Spacing.s2)
                    .background(
                        LinearGradient(
                            colors: DiagnosticsPrimaryButton.colors(theme.palette),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: theme.controlRadius)
                    )
            }
            .buttonStyle(.plain)
            .disabled(model?.isRunningCheck ?? true)
        }
        .padding(.bottom, Spacing.s1)
    }

    private func lastRunLine(_ model: DiagnosticsPaneModel) -> some View {
        Text("Last run: \(lastRunText(model.lastRunAt))")
            .font(theme.monoFont(11, .regular))
            .foregroundStyle(theme.palette.faint)
            .padding(.top, Spacing.s3)
    }

    private func lastRunText(_ date: Date?) -> String {
        guard let date else { return "not yet run this session" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func reportRows(_ model: DiagnosticsPaneModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.presentedRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Spacing.s2) {
                    reportRow(row.label, value: row.value, tone: row.tone)
                    if row.label == "Downloader", case .drift = model.latestReport?.ytDlpDriftVerdict {
                        updateButton(model)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.s2)
    }

    private func updateButton(_ model: DiagnosticsPaneModel) -> some View {
        Button {
            Task { await model.reinstallYtDlp() }
        } label: {
            Label("Update", systemImage: "arrow.clockwise")
                .font(theme.bodyFont(11, .semibold))
                .foregroundStyle(theme.palette.warn)
                .padding(.horizontal, Spacing.s2)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.pillRadius)
                        .stroke(theme.palette.warn, lineWidth: theme.hairlineWidth)
                )
        }
        .buttonStyle(.plain)
        .disabled(model.isReinstallingYtDlp)
    }

    private func reportRow(_ key: String, value: String, tone: DiagnosticsPaneModel.RowTone) -> some View {
        HStack {
            Text(key)
                .font(theme.monoFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
            Spacer()
            Text(value)
                .font(theme.monoFont(12, .regular))
                .foregroundStyle(tone.color(theme))
        }
        .padding(.vertical, Spacing.s2)
        .overlay(alignment: .bottom) {
            Divider().overlay(theme.palette.hair)
        }
    }

    private func actionButtons(_ model: DiagnosticsPaneModel) -> some View {
        HStack(spacing: Spacing.s2) {
            actionButton("Copy report") { model.copyReport() }
            actionButton("Share diagnostic bundle") { model.shareDiagnosticBundle() }
        }
        .padding(.top, Spacing.s4)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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

    private func makeModel() -> DiagnosticsPaneModel {
        let ytDlpURL = appModel.latestEnvironmentReport?.ytDlp?.path
        let probe: MetadataProbing = if let ytDlpURL {
            CanaryProbe.makeProbe(ytDlpURL: ytDlpURL, runner: ProcessRunner())
        } else {
            UnavailableMetadataProbe()
        }
        return DiagnosticsPaneModel(
            metadataProbe: probe,
            environmentProbe: appModel.envProbe,
            ytDlpUpdater: appModel.ytDlpUpdater,
            sharePresenter: SharePresenter(),
            pasteboardMarker: { [weak appModel] text in appModel?.incomingLinkController?.markAppPasteboardWrite(text) }
        )
    }
}

enum DiagnosticsPrimaryButton {
    static func colors(_ palette: PaletteTokens) -> [Color] {
        [palette.goFillStart, palette.goFillEnd]
    }
}

private extension DiagnosticsPaneModel.RowTone {
    func color(_ theme: Theme) -> Color {
        switch self {
        case .ok: theme.palette.accent
        case .warn: theme.palette.warn
        case .bad: theme.palette.danger
        case .neutral: theme.palette.text
        }
    }
}

// yt-dlp's path isn't known yet (environment not probed this session) — Run check's own
// environment probe resolves the real path and this stand-in is discarded before it would matter.
private struct UnavailableMetadataProbe: MetadataProbing {
    func probe(
        _: String,
        context _: ExtractorContext,
        onWait _: (@Sendable (Date?) -> Void)?
    ) async -> Result<MediaMetadata, MetadataError> {
        .failure(.ytDlpMissing)
    }

    func probePlaylist(_: String, context _: ExtractorContext) async -> Result<PlaylistDump, MetadataError> {
        .failure(.ytDlpMissing)
    }
}
