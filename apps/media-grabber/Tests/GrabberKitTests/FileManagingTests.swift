@testable import GrabberKit
import XCTest

final class FileManagingTests: XCTestCase {
    func test_foundation_fileExists_andReadable_forThisSourceFile() {
        let fm = FoundationFileManager()
        let path = #filePath
        XCTAssertTrue(fm.fileExists(atPath: path))
        XCTAssertTrue(fm.dataReadable(at: URL(fileURLWithPath: path)))
        XCTAssertNotNil(fm.fileContents(at: URL(fileURLWithPath: path)))
    }

    func test_foundation_dataReadable_falseForMissingFile() {
        let fm = FoundationFileManager()
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        XCTAssertFalse(fm.dataReadable(at: missing))
        XCTAssertNil(fm.fileContents(at: missing))
    }

    func test_foundation_contentsOfDirectory_emptyArrayForMissingDir() {
        let fm = FoundationFileManager()
        let missing = URL(fileURLWithPath: "/nonexistent-dir-\(UUID().uuidString)")
        XCTAssertEqual(fm.contentsOfDirectory(at: missing), [])
    }

    func test_foundation_contentsOfDirectory_listsRealDir() throws {
        let fm = FoundationFileManager()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-fm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        XCTAssertEqual(fm.contentsOfDirectory(at: dir).map(\.lastPathComponent), ["a.txt"])
    }
}
