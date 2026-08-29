import Foundation

public enum ProgressEvent: Sendable, Equatable {
    case progress(Progress)
    case postProcessing
    case ignored
}

public enum ProgressParser {
    public static func parseStdout(_ line: String) -> ProgressEvent {
        if line.hasPrefix("MG|") {
            return parseProgress(line) ?? .ignored
        }
        if isPostProcessing(line) {
            return .postProcessing
        }
        return .ignored
    }

    private static func isPostProcessing(_ line: String) -> Bool {
        line.contains("[Merger]")
            || line.contains("[ExtractAudio]")
            || line.hasPrefix("Deleting original file")
    }

    public static func classifyStderr(_ line: String) -> ErrorClass? {
        if line.contains("Unable to download"), containsNetworkSignature(line) {
            return .networkDown
        }
        if line.hasPrefix("ERROR:") {
            return .unknown(raw: line)
        }
        return nil
    }

    private static func parseProgress(_ line: String) -> ProgressEvent? {
        let fields = line.components(separatedBy: "|")
        guard fields.count == 6 else { return nil }

        let percentStr = fields[1].trimmingCharacters(in: .whitespaces)
        let speedStr = fields[2].trimmingCharacters(in: .whitespaces)
        let etaStr = fields[3].trimmingCharacters(in: .whitespaces)
        let downloadedStr = fields[4].trimmingCharacters(in: .whitespaces)
        let totalStr = fields[5].trimmingCharacters(in: .whitespaces)

        guard let fraction = parsePercent(percentStr) else { return nil }

        return .progress(Progress(
            fraction: fraction,
            speedBytesPerSec: parseSpeed(speedStr),
            etaSeconds: parseETA(etaStr),
            downloadedBytes: Int64(downloadedStr) ?? 0,
            totalBytes: totalStr == "NA" ? nil : Int64(totalStr)
        ))
    }

    private static func parsePercent(_ raw: String) -> Double? {
        let stripped = raw.replacingOccurrences(of: "%", with: "")
        guard let value = Double(stripped) else { return nil }
        return value / 100
    }

    private static func parseSpeed(_ raw: String) -> Double? {
        if raw.contains("Unknown") {
            return nil
        }
        let trimmed = raw.hasSuffix("/s") ? String(raw.dropLast(2)) : raw
        let units: [(String, Double)] = [
            ("GiB", 1_073_741_824),
            ("MiB", 1_048_576),
            ("KiB", 1024),
            ("B", 1)
        ]
        for (suffix, multiplier) in units where trimmed.hasSuffix(suffix) {
            let numberPart = trimmed.dropLast(suffix.count)
                .trimmingCharacters(in: .whitespaces)
            guard let value = Double(numberPart) else { return nil }
            return value * multiplier
        }
        return Double(trimmed.trimmingCharacters(in: .whitespaces))
    }

    private static func parseETA(_ raw: String) -> Int? {
        if raw.contains("Unknown") || raw == "NA" {
            return nil
        }
        let parts = raw.split(separator: ":").map { Int($0) }
        guard parts.allSatisfy({ $0 != nil }) else { return nil }
        let values = parts.compactMap(\.self)
        switch values.count {
        case 2: return values[0] * 60 + values[1]
        case 3: return values[0] * 3600 + values[1] * 60 + values[2]
        default: return nil
        }
    }

    private static let networkSignatures = [
        "getaddrinfo",
        "Network is unreachable",
        "Temporary failure in name resolution",
        "Connection reset",
        "Failed to resolve",
        "nodename nor servname provided",
        "Could not connect to server",
        "The Internet connection appears to be offline"
    ]

    private static func containsNetworkSignature(_ line: String) -> Bool {
        networkSignatures.contains { line.contains($0) }
    }
}
