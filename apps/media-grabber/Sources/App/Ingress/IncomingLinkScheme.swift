import Foundation

enum IncomingLinkSchemeError: Error, Equatable {
    case wrongScheme
    case missingURL
    case malformed
    case notWebURL
}

enum IncomingLinkScheme {
    static let scheme = "mediagrabber"

    static func openURL(from url: URL) -> Result<URL, IncomingLinkSchemeError> {
        guard url.scheme == scheme else {
            return .failure(.wrongScheme)
        }

        guard isOpenAction(url) else {
            return .failure(.malformed)
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.malformed)
        }

        guard let encodedValue = components.percentEncodedQueryItems?
            .first(where: { $0.name == "url" })?
            .value
        else {
            return .failure(.missingURL)
        }

        guard !encodedValue.isEmpty else {
            return .failure(.missingURL)
        }

        guard isValidPercentEncoding(encodedValue),
              let decodedValue = encodedValue.removingPercentEncoding,
              !decodedValue.isEmpty,
              let components = URLComponents(string: decodedValue),
              let webURL = components.url,
              let webScheme = components.scheme?.lowercased(),
              !webScheme.isEmpty
        else {
            return .failure(.malformed)
        }

        guard webScheme == "http" || webScheme == "https" else {
            return .failure(.notWebURL)
        }

        return .success(webURL)
    }

    private static func isValidPercentEncoding(_ value: String) -> Bool {
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "%" {
                let next = value.index(after: index)
                guard next < value.endIndex else {
                    return false
                }
                let following = value.index(after: next)
                guard following < value.endIndex else {
                    return false
                }
                let hex = value[next ... following]
                guard hex.count == 2, hex.allSatisfy(\.isHexDigit) else {
                    return false
                }
                index = value.index(after: following)
            } else {
                index = value.index(after: index)
            }
        }
        return true
    }

    private static func isOpenAction(_ url: URL) -> Bool {
        if url.host == "open", url.path.isEmpty || url.path == "/" {
            return true
        }
        return url.path == "/open"
    }
}
