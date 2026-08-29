@testable import GrabberKit
import XCTest

final class EnvironmentProbeTests: XCTestCase {
    private func probe(
        runner: FakeProcessRunner,
        present: Set<String>,
        searchPaths: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]
    ) -> EnvironmentProbe {
        EnvironmentProbe(
            runner: runner,
            extraSearchPaths: searchPaths.map { URL(fileURLWithPath: $0) },
            isExecutable: { url in present.contains(url.path) }
        )
    }

    func test_allToolsPresent_parsesVersions() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("Homebrew 4.3.0\n"), forPathEndingIn: "brew")
        runner.script(.stdout("2025.09.26\n"), forPathEndingIn: "yt-dlp")
        runner.script(
            .stdout("ffmpeg version 8.0 Copyright (c) 2000-2024\n"),
            forPathEndingIn: "ffmpeg"
        )
        let sut = probe(
            runner: runner,
            present: [
                "/opt/homebrew/bin/brew",
                "/opt/homebrew/bin/yt-dlp",
                "/opt/homebrew/bin/ffmpeg"
            ]
        )
        let report = await sut.probe()
        XCTAssertEqual(report.brew?.version, "4.3.0")
        XCTAssertEqual(report.ytDlp?.version, "2025.09.26")
        XCTAssertEqual(report.ffmpeg?.version, "8.0")
        XCTAssertTrue(report.isReadyForDownloads)
    }

    func test_ytDlpMissing_reportsNilAndNotReady() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("Homebrew 4.3.0\n"), forPathEndingIn: "brew")
        runner.script(
            .stdout("ffmpeg version 8.0 Copyright\n"),
            forPathEndingIn: "ffmpeg"
        )
        let sut = probe(
            runner: runner,
            present: ["/opt/homebrew/bin/brew", "/opt/homebrew/bin/ffmpeg"]
        )
        let report = await sut.probe()
        XCTAssertNil(report.ytDlp)
        XCTAssertFalse(report.isReadyForDownloads)
    }

    func test_ffmpegMalformedVersion_treatedAsMissing() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("2025.09.26\n"), forPathEndingIn: "yt-dlp")
        runner.script(.stdout("garbage\n"), forPathEndingIn: "ffmpeg")
        let sut = probe(
            runner: runner,
            present: ["/opt/homebrew/bin/yt-dlp", "/opt/homebrew/bin/ffmpeg"]
        )
        let report = await sut.probe()
        XCTAssertNil(report.ffmpeg)
    }

    func test_firstMatchOnSearchPathWins() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("2025.09.26\n"), forPathEndingIn: "yt-dlp")
        let sut = probe(
            runner: runner,
            present: [
                "/opt/homebrew/bin/yt-dlp",
                "/usr/local/bin/yt-dlp"
            ]
        )
        let report = await sut.probe()
        XCTAssertEqual(
            report.ytDlp?.path,
            URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")
        )
    }

    func test_noRealBrewOrNetwork() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("Homebrew 4.3.0\n"), forPathEndingIn: "brew")
        let sut = probe(runner: runner, present: ["/opt/homebrew/bin/brew"])
        _ = await sut.probe()
        for launch in runner.launches {
            XCTAssertTrue(
                launch.executableURL.path.hasPrefix("/opt/homebrew/bin")
                    || launch.executableURL.path.hasPrefix("/usr/local/bin"),
                "unexpected launch: \(launch.executableURL.path)"
            )
        }
    }
}
