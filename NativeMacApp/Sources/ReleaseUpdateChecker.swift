import Foundation

private struct GitHubLatestReleaseResponse: Decodable {
    var tagName: String
    var htmlURL: URL
    var publishedAt: Date?
    var draft: Bool
    var prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case draft
        case prerelease
    }
}

actor ReleaseUpdateChecker {
    private let session: URLSession
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/Ethant123/broll_yoinkage/releases/latest")!

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: configuration)
    }

    func check(currentVersion: String) async throws -> AppReleaseInfo? {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("B-Roll Downloader", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "ReleaseUpdateChecker",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not check GitHub releases right now."]
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let latest = try decoder.decode(GitHubLatestReleaseResponse.self, from: data)

        guard !latest.draft, !latest.prerelease else { return nil }

        let latestVersion = Self.normalizeVersion(latest.tagName)
        let installedVersion = Self.normalizeVersion(currentVersion)

        guard Self.isVersion(latestVersion, newerThan: installedVersion) else {
            return nil
        }

        return AppReleaseInfo(
            version: latestVersion,
            pageURL: latest.htmlURL,
            publishedAt: latest.publishedAt
        )
    }

    private static func normalizeVersion(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
    }

    private static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsParts = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left != right {
                return left > right
            }
        }

        return false
    }
}
