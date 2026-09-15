import Foundation

public struct DiagnosticBundle: Sendable {
    public static func build(appLogTail: String, jobLog: String?, report: String) throws -> Data {
        var entries: [ZipEntry] = [
            ZipEntry(name: "app-log-tail.txt", contents: LogRedaction.redact(appLogTail)),
            ZipEntry(name: "report.txt", contents: LogRedaction.redact(report))
        ]
        if let jobLog {
            entries.append(ZipEntry(name: "job-log.txt", contents: LogRedaction.redact(jobLog)))
        }
        return StoreOnlyZipWriter.write(entries: entries)
    }
}

private struct ZipEntry {
    let name: String
    let contents: String
}

// Minimal store-only (uncompressed) zip writer: no external zip dependency is linked in this project.
private enum StoreOnlyZipWriter {
    private static let localFileHeaderSignature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
    private static let centralDirectorySignature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
    private static let endOfCentralDirectorySignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
    private static let versionNeededToExtract: UInt16 = 20
    private static let versionMadeBy: UInt16 = 20
    private static let generalPurposeFlags: UInt16 = 0
    private static let storedCompressionMethod: UInt16 = 0
    private static let dosModTimeAndDate: [UInt8] = [0, 0, 0, 0]

    static func write(entries: [ZipEntry]) -> Data {
        var fileData = Data()
        var centralDirectory = Data()
        var localHeaderOffset = UInt32(0)

        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            let contentBytes = Data(entry.contents.utf8)
            let checksum = crc32(contentBytes)

            fileData.append(localFileHeader(nameBytes: nameBytes, contentBytes: contentBytes, checksum: checksum))
            fileData.append(contentBytes)

            centralDirectory.append(centralDirectoryEntry(
                nameBytes: nameBytes,
                contentBytes: contentBytes,
                checksum: checksum,
                localHeaderOffset: localHeaderOffset
            ))

            localHeaderOffset += UInt32(localFileHeaderSize + nameBytes.count) + UInt32(contentBytes.count)
        }

        let endRecord = endOfCentralDirectoryRecord(
            entryCount: entries.count,
            centralDirectorySize: UInt32(centralDirectory.count),
            centralDirectoryOffset: localHeaderOffset
        )

        return fileData + centralDirectory + endRecord
    }

    private static let localFileHeaderSize = 30

    private static func localFileHeader(nameBytes: Data, contentBytes: Data, checksum: UInt32) -> Data {
        var header = Data()
        header.append(contentsOf: localFileHeaderSignature)
        header.append(littleEndian: versionNeededToExtract)
        header.append(littleEndian: generalPurposeFlags)
        header.append(littleEndian: storedCompressionMethod)
        header.append(contentsOf: dosModTimeAndDate)
        header.append(littleEndian: checksum)
        header.append(littleEndian: UInt32(contentBytes.count))
        header.append(littleEndian: UInt32(contentBytes.count))
        header.append(littleEndian: UInt16(nameBytes.count))
        header.append(littleEndian: UInt16(0))
        header.append(nameBytes)
        return header
    }

    private static func centralDirectoryEntry(
        nameBytes: Data,
        contentBytes: Data,
        checksum: UInt32,
        localHeaderOffset: UInt32
    ) -> Data {
        var entry = Data()
        entry.append(contentsOf: centralDirectorySignature)
        entry.append(littleEndian: versionMadeBy)
        entry.append(littleEndian: versionNeededToExtract)
        entry.append(littleEndian: generalPurposeFlags)
        entry.append(littleEndian: storedCompressionMethod)
        entry.append(contentsOf: dosModTimeAndDate)
        entry.append(littleEndian: checksum)
        entry.append(littleEndian: UInt32(contentBytes.count))
        entry.append(littleEndian: UInt32(contentBytes.count))
        entry.append(littleEndian: UInt16(nameBytes.count))
        entry.append(littleEndian: UInt16(0))
        entry.append(littleEndian: UInt16(0))
        entry.append(littleEndian: UInt16(0))
        entry.append(littleEndian: UInt16(0))
        entry.append(littleEndian: UInt32(0))
        entry.append(littleEndian: localHeaderOffset)
        entry.append(nameBytes)
        return entry
    }

    private static func endOfCentralDirectoryRecord(
        entryCount: Int,
        centralDirectorySize: UInt32,
        centralDirectoryOffset: UInt32
    ) -> Data {
        var record = Data()
        record.append(contentsOf: endOfCentralDirectorySignature)
        record.append(littleEndian: UInt16(0))
        record.append(littleEndian: UInt16(0))
        record.append(littleEndian: UInt16(entryCount))
        record.append(littleEndian: UInt16(entryCount))
        record.append(littleEndian: centralDirectorySize)
        record.append(littleEndian: centralDirectoryOffset)
        record.append(littleEndian: UInt16(0))
        return record
    }

    private static func crc32(_ data: Data) -> UInt32 {
        let polynomial: UInt32 = 0xEDB8_8320
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ polynomial : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    mutating func append(littleEndian value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }
}
