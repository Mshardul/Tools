import Foundation
@testable import GrabberKit

final class FakeEnvironmentProbe: EnvironmentProbing, @unchecked Sendable {
    private let reports: LockedBox<[EnvironmentReport]>
    private let callCount = LockedBox(0)

    init(_ reports: EnvironmentReport...) {
        precondition(!reports.isEmpty)
        self.reports = LockedBox(reports)
    }

    var probeCount: Int {
        callCount.read { $0 }
    }

    func setReports(_ next: EnvironmentReport...) {
        reports.mutate { $0 = next }
        callCount.mutate { $0 = 0 }
    }

    func probe() async -> EnvironmentReport {
        let index = callCount.mutate { count -> Int in
            let current = count
            count += 1
            return current
        }
        return reports.read { list in
            list[min(index, list.count - 1)]
        }
    }
}

extension EnvironmentReport {
    static func with(
        brew: Bool = false,
        ytDlp: Bool = false,
        ffmpeg: Bool = false
    ) -> EnvironmentReport {
        func tool(_ name: String, _ present: Bool) -> ToolInfo? {
            present
                ? ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"), version: "0")
                : nil
        }
        return EnvironmentReport(
            brew: tool("brew", brew),
            ytDlp: tool("yt-dlp", ytDlp),
            ffmpeg: tool("ffmpeg", ffmpeg)
        )
    }
}
