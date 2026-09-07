import Foundation

public protocol ShieldPinging: Sendable {
    func ping(_ url: URL, timeout: TimeInterval) async -> Bool
}

public protocol LoopbackPortChecking: Sendable {
    func isFree(_ port: Int) -> Bool
}

public struct AlwaysFreePortChecker: LoopbackPortChecking {
    public init() {}

    public func isFree(_: Int) -> Bool {
        true
    }
}

public struct URLSessionShieldPinger: ShieldPinging {
    public init() {}

    public func ping(_ url: URL, timeout: TimeInterval) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        guard let (_, response) = try? await URLSession.shared.data(for: request) else {
            return false
        }
        guard let http = response as? HTTPURLResponse else {
            return false
        }
        return (200 ..< 300).contains(http.statusCode)
    }
}
