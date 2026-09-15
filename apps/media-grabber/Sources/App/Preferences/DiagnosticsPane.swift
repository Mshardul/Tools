import AppKit
import Foundation
import GrabberKit
import Observation
import SwiftUI

// Tails the app log and the most-recent job log for DiagnosticBundle; kept behind a protocol so
// tests can inject a fake instead of touching the real files under ~/Library/Logs/MediaGrabber.
protocol LogReading: Sendable {
    func appLogTail() -> String
    func mostRecentJobLog() -> String?
}

struct AppLogReader: LogReading {
    private let appLogDirectory: URL
    private let jobLogDirectory: URL
    private let tailLineCount: Int

    init(
        appLogDirectory: URL = LogWriter.defaultDirectory,
        jobLogDirectory: URL = JobLog.defaultDir,
        tailLineCount: Int = 200
    ) {
        self.appLogDirectory = appLogDirectory
        self.jobLogDirectory = jobLogDirectory
        self.tailLineCount = tailLineCount
    }

    func appLogTail() -> String {
        let fileURL = appLogDirectory.appendingPathComponent("app.log")
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(tailLineCount).joined(separator: "\n")
    }

    func mostRecentJobLog() -> String? {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: jobLogDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return nil
        }
        let newest = entries
            .filter { $0.pathExtension == "log" }
            .max { lhs, rhs in
                modificationDate(lhs, fileManager: fileManager) < modificationDate(rhs, fileManager: fileManager)
            }
        guard let newest else { return nil }
        return try? String(contentsOf: newest, encoding: .utf8)
    }

    private func modificationDate(_ url: URL, fileManager: FileManager) -> Date {
        (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
    }
}

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
        lines.append("Canary probe: \(canary == .passed ? "passed" : "failed")")
        if let ytDlp = report.ytDlp {
            lines.append("yt-dlp: \(ytDlp.version)\(driftSuffix(report))")
        } else {
            lines.append("yt-dlp: not found")
        }
        if let ffmpeg = report.ffmpeg {
            lines.append("ffmpeg: \(ffmpeg.version)")
        } else {
            lines.append("ffmpeg: not found")
        }
        return lines.joined(separator: "\n")
    }

    private static func driftSuffix(_ report: EnvironmentReport) -> String {
        switch report.ytDlpDriftVerdict {
        case .current, nil: " · current"
        case let .drift(_, minimum): " · update available (min \(minimum))"
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
                reportRows(model)
                actionButtons(model)
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
                    .background(theme.palette.accent, in: RoundedRectangle(cornerRadius: theme.controlRadius))
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
            reportRow(
                "Canary probe",
                value: canaryValueText(model.canaryResult),
                verdict: canaryVerdict(model.canaryResult)
            )
            if let ytDlp = model.latestReport?.ytDlp {
                ytDlpRow(model, ytDlp: ytDlp)
            } else {
                reportRow("yt-dlp", value: "not found", verdict: .bad)
            }
            if let ffmpeg = model.latestReport?.ffmpeg {
                reportRow("ffmpeg", value: ffmpeg.version, verdict: .ok)
            } else {
                reportRow("ffmpeg", value: "not found", verdict: .bad)
            }
        }
        .padding(.vertical, Spacing.s2)
    }

    private func ytDlpRow(_ model: DiagnosticsPaneModel, ytDlp _: ToolInfo) -> some View {
        HStack(spacing: Spacing.s2) {
            reportRow("yt-dlp", value: ytDlpValueText(model.latestReport), verdict: ytDlpVerdict(model.latestReport))
            if case .drift = model.latestReport?.ytDlpDriftVerdict {
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
        }
    }

    private func reportRow(_ key: String, value: String, verdict: RowVerdict) -> some View {
        HStack {
            Text(key)
                .font(theme.monoFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
            Spacer()
            Text(value)
                .font(theme.monoFont(12, .regular))
                .foregroundStyle(verdict.color(theme))
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

    private func canaryValueText(_ result: DiagnosticsPaneModel.CanaryResult) -> String {
        switch result {
        case .notRun: "not yet run this session"
        case .passed: "passed"
        case .failed: "failed"
        }
    }

    private func canaryVerdict(_ result: DiagnosticsPaneModel.CanaryResult) -> RowVerdict {
        switch result {
        case .notRun: .neutral
        case .passed: .ok
        case .failed: .bad
        }
    }

    private func ytDlpValueText(_ report: EnvironmentReport?) -> String {
        guard let version = report?.ytDlp?.version else { return "not found" }
        return switch report?.ytDlpDriftVerdict {
        case .current, nil: "\(version) · current"
        case let .drift(_, minimum): "\(version) · update available (min \(minimum))"
        case .unknown: version
        }
    }

    private func ytDlpVerdict(_ report: EnvironmentReport?) -> RowVerdict {
        switch report?.ytDlpDriftVerdict {
        case .current, nil: .ok
        case .drift: .warn
        case .unknown: .neutral
        }
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
            sharePresenter: SharePresenter()
        )
    }
}

private enum RowVerdict {
    case ok
    case warn
    case bad
    case neutral

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
    func probe(_: String, context _: ExtractorContext) async -> Result<MediaMetadata, MetadataError> {
        .failure(.ytDlpMissing)
    }

    func probePlaylist(_: String, context _: ExtractorContext) async -> Result<PlaylistDump, MetadataError> {
        .failure(.ytDlpMissing)
    }
}
