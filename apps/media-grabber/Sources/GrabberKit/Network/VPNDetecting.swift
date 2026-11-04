import Darwin
import Foundation

public protocol VPNDetecting: Sendable {
    var isVPNActive: Bool { get }
}

public struct InterfaceRecord: Equatable, Sendable {
    public var name: String
    public var isUp: Bool
    public var address: String

    public init(name: String, isUp: Bool, address: String) {
        self.name = name
        self.isUp = isUp
        self.address = address
    }
}

public struct InterfaceVPNDetector: VPNDetecting {
    public init() {}

    public var isVPNActive: Bool {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else {
            return false
        }
        defer { freeifaddrs(pointer) }
        return Self.carriesTraffic(Self.records(startingAt: pointer))
    }

    public static func carriesTraffic(_ interfaces: [InterfaceRecord]) -> Bool {
        interfaces.contains { record in
            record.isUp && isTunnelName(record.name) && isRoutable(record.address)
        }
    }

    static func records(startingAt pointer: UnsafeMutablePointer<ifaddrs>?) -> [InterfaceRecord] {
        var records: [InterfaceRecord] = []
        var current = pointer
        while let iface = current {
            let name = String(cString: iface.pointee.ifa_name)
            let isUp = (iface.pointee.ifa_flags & UInt32(IFF_UP)) != 0
            if let address = iface.pointee.ifa_addr, let presentation = presentation(of: address) {
                records.append(InterfaceRecord(name: name, isUp: isUp, address: presentation))
            }
            current = iface.pointee.ifa_next
        }
        return records
    }

    private static func isTunnelName(_ name: String) -> Bool {
        name.hasPrefix("utun")
            || name.hasPrefix("ipsec")
            || name.hasPrefix("ppp")
            || name.hasPrefix("wg")
    }

    private static func isRoutable(_ address: String) -> Bool {
        let value = address.lowercased()
        if value.isEmpty || value == "0.0.0.0" || value == "::" || value == "::1" {
            return false
        }
        if value.hasPrefix("127.") || value.hasPrefix("169.254.") || value.hasPrefix("fe80:") {
            return false
        }
        return true
    }

    private static func presentation(of address: UnsafePointer<sockaddr>) -> String? {
        switch Int32(address.pointee.sa_family) {
        case AF_INET:
            var copy = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &copy.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buffer)
        case AF_INET6:
            var copy = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &copy.sin6_addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buffer)
        default:
            return nil
        }
    }
}
