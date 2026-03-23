import Foundation

final class RecentProjectsStore {
    private let fileManager = FileManager.default
    private let fileURL: URL
    private let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("B-Roll Downloader", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("recent-projects.json")
    }

    func load() -> [RecentProject] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([RecentProject].self, from: data)
        else {
            return []
        }

        let filtered = prune(decoded)
        if filtered != decoded {
            save(filtered)
        }
        return filtered
    }

    func record(name: String) -> [RecentProject] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return load()
        }

        var current = load().filter { $0.name.caseInsensitiveCompare(trimmed) != .orderedSame }
        current.insert(RecentProject(name: trimmed, lastUsedAt: Date()), at: 0)
        let normalized = prune(current)
        save(normalized)
        return normalized
    }

    func remove(name: String) -> [RecentProject] {
        let filtered = load().filter { $0.name.caseInsensitiveCompare(name) != .orderedSame }
        save(filtered)
        return filtered
    }

    private func prune(_ items: [RecentProject]) -> [RecentProject] {
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        return items
            .filter { $0.lastUsedAt >= cutoff }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    private func save(_ items: [RecentProject]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
