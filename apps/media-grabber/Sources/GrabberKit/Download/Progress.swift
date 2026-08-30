import Foundation

// Disambiguates from Foundation.Progress at call sites that import both modules.
public typealias DownloadProgress = Progress

public struct Progress: Sendable, Equatable {
    public var fraction: Double {
        didSet { fraction = Self.clamp(fraction) }
    }

    public var speedBytesPerSec: Double?
    public var etaSeconds: Int?
    public var downloadedBytes: Int64
    public var totalBytes: Int64?

    public init(
        fraction: Double,
        speedBytesPerSec: Double? = nil,
        etaSeconds: Int? = nil,
        downloadedBytes: Int64,
        totalBytes: Int64? = nil
    ) {
        self.fraction = Self.clamp(fraction)
        self.speedBytesPerSec = speedBytesPerSec
        self.etaSeconds = etaSeconds
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
    }

    private static func clamp(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
