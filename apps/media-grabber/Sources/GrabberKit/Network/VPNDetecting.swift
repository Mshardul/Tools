import Darwin
import Foundation

public protocol VPNDetecting: Sendable {
    var isVPNActive: Bool { get }
}

public struct InterfaceVPNDetector: VPNDetecting {
    public init() {}

    public var isVPNActive: Bool {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else {
            return false
        }
        defer { freeifaddrs(pointer) }
        return hasVPNInterface(startingAt: pointer)
    }

    private func hasVPNInterface(startingAt pointer: UnsafeMutablePointer<ifaddrs>?) -> Bool {
        var current = pointer
        while let iface = current {
            if Self.isVPNName(String(cString: iface.pointee.ifa_name)) {
                return true
            }
            current = iface.pointee.ifa_next
        }
        return false
    }

    private static func isVPNName(_ name: String) -> Bool {
        name.hasPrefix("utun")
            || name.hasPrefix("ipsec")
            || name.hasPrefix("ppp")
            || name.hasPrefix("wg")
    }
}
