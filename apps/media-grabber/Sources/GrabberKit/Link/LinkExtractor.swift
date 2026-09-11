import Foundation

public enum LinkExtractor {
    public static func extract(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<"), text.hasSuffix(">"), text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }

        guard let range = firstHTTPURLRange(in: text) else {
            return nil
        }

        return URL(string: String(text[range]))
    }

    private static func firstHTTPURLRange(in text: String) -> Range<String.Index>? {
        let schemes = ["https://", "http://"]
        var earliest: Range<String.Index>?

        for scheme in schemes {
            var searchStart = text.startIndex
            while searchStart < text.endIndex {
                guard let found = text.range(of: scheme, range: searchStart ..< text.endIndex) else {
                    break
                }
                let urlEnd = endOfURL(in: text, startingAt: found.lowerBound)
                let range = found.lowerBound ..< urlEnd
                if earliest == nil || range.lowerBound < earliest!.lowerBound {
                    earliest = range
                }
                searchStart = found.upperBound
            }
        }

        return earliest
    }

    private static func endOfURL(in text: String, startingAt start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex, !text[index].isWhitespace, !terminators.contains(text[index]) {
            index = text.index(after: index)
        }
        return index
    }

    // Angle brackets wrap URLs in mail clients and Markdown; a bare URL never contains them.
    private static let terminators: Set<Character> = ["<", ">"]
}
