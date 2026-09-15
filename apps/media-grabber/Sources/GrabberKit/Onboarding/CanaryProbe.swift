import Foundation

public enum CanaryProbe {
    // Same fixture used by the opt-in live-network integration tests (MG_LIVE_TESTS=1).
    public static let url = "https://archive.org/details/BigBuckBunny_124"

    public static func run(ytDlpPath: URL?, runner: ProcessRunning) async -> Result<MediaMetadata, MetadataError> {
        guard let ytDlpPath else {
            return .failure(.ytDlpMissing)
        }
        return await makeProbe(ytDlpURL: ytDlpPath, runner: runner).probe(url)
    }

    // Shared with production DiagnosticsPaneModel construction so there is one line that builds this probe.
    public static func makeProbe(ytDlpURL: URL, runner: ProcessRunning) -> MetadataProbing {
        MetadataProbe(ytDlpURL: ytDlpURL, runner: runner)
    }
}
