@testable import GrabberKit
import TestSupport
import XCTest

final class IntegrityCheckTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/tmp/out.mp4")
    private let ffprobe = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")

    private func json(duration: Double, height: Int?) -> String {
        let streams = height.map { "[{\"codec_type\":\"video\",\"height\":\($0)}]" } ?? "[]"
        return "{\"format\":{\"duration\":\"\(duration)\"},\"streams\":\(streams)}"
    }

    private func runner(_ output: String, exitCode: Int32 = 0) -> FakeProcessRunner {
        let fake = FakeProcessRunner()
        fake.script(.stdout(output, exitCode: exitCode), forPathEndingIn: "ffprobe")
        return fake
    }

    private func check(_ fake: FakeProcessRunner, ffprobeURL: URL?) -> IntegrityCheck {
        IntegrityCheck(runner: fake, ffprobeURL: ffprobeURL, isExecutable: { _ in true })
    }

    func test_withinTolerancePasses_andReadsHeight() async {
        let sut = check(runner(json(duration: 600, height: 720)), ffprobeURL: ffprobe)
        let result = await sut.verify(file: file, expectedDurationSeconds: 600)
        XCTAssertEqual(result.verdict, .passed)
        XCTAssertEqual(result.actualQuality, "720p")
    }

    func test_materiallyShortFails() async {
        let sut = check(runner(json(duration: 200, height: 1080)), ffprobeURL: ffprobe)
        let result = await sut.verify(file: file, expectedDurationSeconds: 600)
        guard case let .failed(reason) = result.verdict else { return XCTFail("expected .failed") }
        XCTAssertTrue(reason.contains("400"))
    }

    func test_smallAbsoluteGapUnder10sPasses() async {
        let sut = check(runner(json(duration: 594, height: 720)), ffprobeURL: ffprobe)
        let result = await sut.verify(file: file, expectedDurationSeconds: 600)
        XCTAssertEqual(result.verdict, .passed)
    }

    func test_gapOver10sButUnder5PercentPasses() async {
        let sut = check(runner(json(duration: 3585, height: 1080)), ffprobeURL: ffprobe)
        let result = await sut.verify(file: file, expectedDurationSeconds: 3600)
        XCTAssertEqual(result.verdict, .passed)
    }

    func test_nilExpectedDurationSkipsButStillReadsHeight() async {
        let sut = check(runner(json(duration: 600, height: 480)), ffprobeURL: ffprobe)
        let result = await sut.verify(file: file, expectedDurationSeconds: nil)
        guard case .skipped = result.verdict else { return XCTFail("expected .skipped") }
        XCTAssertEqual(result.actualQuality, "480p")
    }

    func test_audioOnlyJsonHasNilQualityButComputesDuration() async {
        let sut = check(runner(json(duration: 200, height: nil)), ffprobeURL: ffprobe)
        let result = await sut.verify(file: file, expectedDurationSeconds: 600)
        XCTAssertNil(result.actualQuality)
        guard case .failed = result.verdict else {
            return XCTFail("expected .failed on the short duration")
        }
    }

    func test_nilFfprobeURLSkipsWithNoSpawn() async {
        let fake = FakeProcessRunner()
        let sut = IntegrityCheck(runner: fake, ffprobeURL: nil, isExecutable: { _ in true })
        let result = await sut.verify(file: file, expectedDurationSeconds: 600)
        guard case .skipped = result.verdict else { return XCTFail("expected .skipped") }
        XCTAssertTrue(fake.launches.isEmpty)
    }

    func test_nonZeroFfprobeExitSkips() async {
        let sut = check(runner("garbage", exitCode: 1), ffprobeURL: ffprobe)
        let result = await sut.verify(file: file, expectedDurationSeconds: 600)
        guard case .skipped = result.verdict else { return XCTFail("expected .skipped") }
    }
}
