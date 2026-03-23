import Foundation

enum ThemeMode: String, CaseIterable, Codable {
    case light
    case dark
    case system
}

struct AppReleaseInfo: Equatable {
    var version: String
    var pageURL: URL
    var publishedAt: Date?
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case localBuild
    case upToDate
    case available(AppReleaseInfo)
    case failed(String)
}

struct InstallPromptInfo: Equatable {
    var sourcePath: String
    var destinationPath: String
    var existingVersion: String?
}

enum BootstrapPhase: Equatable {
    case preparing
    case ready
    case failed
}

struct ToolPaths: Equatable, Codable {
    var ytDlp: String?
    var ffmpeg: String?
    var ffprobe: String?

    var isReady: Bool {
        ytDlp != nil && ffmpeg != nil && ffprobe != nil
    }
}

struct BootstrapSnapshot: Equatable {
    var phase: BootstrapPhase = .preparing
    var title: String = "Preparing download tools"
    var detail: String = "Checking what this Mac already has."
    var progress: Double = 0.06
    var isIndeterminate: Bool = false
    var canRetry: Bool = false
}

enum QueueItemState: String, Codable {
    case resolving
    case queued
    case downloading
    case converting
    case complete
    case aborted
    case failed

    var label: String {
        switch self {
        case .resolving:
            return "Queued"
        case .queued:
            return "Queued"
        case .downloading:
            return "Downloading"
        case .converting:
            return "Converting"
        case .complete:
            return "Complete"
        case .aborted:
            return "Aborted"
        case .failed:
            return "Failed"
        }
    }

    var isActive: Bool {
        switch self {
        case .resolving, .queued, .downloading, .converting:
            return true
        case .complete, .aborted, .failed:
            return false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .complete, .aborted, .failed:
            return true
        case .resolving, .queued, .downloading, .converting:
            return false
        }
    }
}

struct VideoMetadata: Equatable {
    var id: String
    var title: String
    var channel: String
    var uploadDate: String
    var duration: Double?
    var estimatedSizeBytes: Int64?
}

struct QueueItem: Identifiable, Equatable {
    let id: UUID
    let visualOrder: Int
    let originalURL: String
    let normalizedURL: String
    let projectName: String

    var title: String
    var channel: String
    var uploadDate: String?
    var status: QueueItemState
    var progress: Double
    var metadata: VideoMetadata?
    var errorMessage: String?
    var outputPath: String?
    var tempDirectory: String?
    var shortCode: String?
    var estimatedSizeBytes: Int64?
    var submittedAt: Date

    var serviceLabel: String {
        "YouTube"
    }
}

struct InputSummary: Equatable {
    var validCount: Int = 0
    var duplicateCount: Int = 0
    var invalidCount: Int = 0
}

struct ParsedURLBatch: Equatable {
    var normalizedURLs: [String]
    var duplicateCount: Int
    var invalidCount: Int
}

struct RecentProject: Identifiable, Codable, Equatable {
    var name: String
    var lastUsedAt: Date

    var id: String {
        name.lowercased()
    }
}
