import Foundation

enum YouTubeURLParser {
    static func parse(_ text: String) -> ParsedURLBatch {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        var normalizedURLs: [String] = []
        var duplicateCount = 0
        var invalidCount = 0

        for line in lines {
            guard let normalized = normalize(line) else {
                invalidCount += 1
                continue
            }

            if seen.contains(normalized) {
                duplicateCount += 1
                continue
            }

            seen.insert(normalized)
            normalizedURLs.append(normalized)
        }

        return ParsedURLBatch(
            normalizedURLs: normalizedURLs,
            duplicateCount: duplicateCount,
            invalidCount: invalidCount
        )
    }

    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = withHTTPSIfNeeded(trimmed)
        guard let components = URLComponents(string: candidate) else {
            return extractFallbackID(from: trimmed).map(canonicalURL)
        }

        let host = (components.host ?? "")
            .lowercased()
            .replacingOccurrences(of: "www.", with: "")
            .replacingOccurrences(of: "m.", with: "")

        if host == "youtu.be" {
            let pathComponents = components.path.split(separator: "/").map(String.init)
            guard let first = pathComponents.first, isVideoID(first) else { return nil }
            return canonicalURL(first)
        }

        guard host.contains("youtube.com") || host.contains("youtube-nocookie.com") else {
            return nil
        }

        if let queryID = components.queryItems?.first(where: { $0.name == "v" })?.value, isVideoID(queryID) {
            return canonicalURL(queryID)
        }

        let pathComponents = components.path.split(separator: "/").map(String.init)
        if pathComponents.count >= 2 {
            let leading = pathComponents[0].lowercased()
            let value = pathComponents[1]
            if ["shorts", "embed", "live", "watch"].contains(leading), isVideoID(value) {
                return canonicalURL(value)
            }
        }

        return extractFallbackID(from: trimmed).map(canonicalURL)
    }

    private static func withHTTPSIfNeeded(_ value: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        return "https://\(value)"
    }

    private static func canonicalURL(_ videoID: String) -> String {
        "https://www.youtube.com/watch?v=\(videoID)"
    }

    private static func isVideoID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
    }

    private static func extractFallbackID(from value: String) -> String? {
        guard let range = value.range(of: #"([A-Za-z0-9_-]{11})"#, options: .regularExpression) else {
            return nil
        }
        let candidate = String(value[range])
        return isVideoID(candidate) ? candidate : nil
    }
}
