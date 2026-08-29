import Foundation

public enum YtDlpArguments {
    static let progressTemplate = "download:MG|%(progress._percent_str)s|"
        + "%(progress._speed_str)s|%(progress._eta_str)s|"
        + "%(progress.downloaded_bytes)s|%(progress.total_bytes)s"

    public static func build(for request: DownloadRequest) -> [String] {
        var argv: [String] = []
        argv += ["-P", request.destFolder.path]
        argv += ["-o", request.outputTemplate]
        argv += formatSelector(for: request)
        argv += ["--newline", "--progress", "--progress-template", progressTemplate]
        argv += ["--no-playlist"]
        argv += ["--no-warnings"]
        argv += [request.url]
        return argv
    }

    // Seam for later phases (cookies, proxy creds); identical to build() in Phase 1.
    public static func redacted(for request: DownloadRequest) -> [String] {
        build(for: request)
    }

    private static func formatSelector(for request: DownloadRequest) -> [String] {
        switch request.kind {
        case let .video(maxHeight: height):
            var tokens = [
                "-f",
                "bv*[height<=\(height)][ext=mp4]+ba[ext=m4a]"
                    + "/bv*[height<=\(height)]+ba"
                    + "/b[height<=\(height)]"
            ]
            if let container = request.container {
                tokens += ["--merge-output-format", container]
            }
            return tokens
        case let .audio(codec: codec):
            return ["-x", "--audio-format", codec.rawValue]
        }
    }
}
