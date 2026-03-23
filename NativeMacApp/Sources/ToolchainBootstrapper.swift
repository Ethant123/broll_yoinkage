import Foundation

struct ToolchainResult {
    let paths: ToolPaths
    let usingManagedTools: Bool
}

actor ToolchainBootstrapper {
    private enum Tool: CaseIterable {
        case ytDlp
        case ffmpeg
        case ffprobe
    }

    private let fileManager = FileManager.default
    private let userDataDirectory: URL
    private let managedBinDirectory: URL
    private let bundledToolsDirectory: URL?

    private let ytDlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp")!
    private let ffmpegZipURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/zip")!
    private let ffprobeZipURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip")!

    init() {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.userDataDirectory = applicationSupport.appendingPathComponent("B-Roll Downloader", isDirectory: true)
        self.managedBinDirectory = userDataDirectory.appendingPathComponent("toolchain/bin", isDirectory: true)
        self.bundledToolsDirectory = Bundle.main.resourceURL?.appendingPathComponent("Tools", isDirectory: true)
    }

    func ensureReady(progress: @escaping @Sendable (BootstrapSnapshot) -> Void) async throws -> ToolchainResult {
        try ensureDirectories()

        progress(BootstrapSnapshot(
            phase: .preparing,
            title: "Preparing download tools",
            detail: "Checking what this Mac already has.",
            progress: 0.08,
            isIndeterminate: false,
            canRetry: false
        ))

        if let bundledPaths = try installBundledToolsIfPresent(progress: progress) {
            progress(BootstrapSnapshot(
                phase: .ready,
                title: "Ready to launch",
                detail: "Using helper tools packaged with the app.",
                progress: 1.0,
                isIndeterminate: false,
                canRetry: false
            ))
            return ToolchainResult(paths: bundledPaths, usingManagedTools: true)
        }

        if let systemPaths = findCompleteSystemToolchain() {
            progress(BootstrapSnapshot(
                phase: .ready,
                title: "Ready to launch",
                detail: "Using tools that are already installed on this Mac.",
                progress: 1.0,
                isIndeterminate: false,
                canRetry: false
            ))
            return ToolchainResult(paths: systemPaths, usingManagedTools: false)
        }

        let managedPaths = ToolPaths(
            ytDlp: managedBinDirectory.appendingPathComponent("yt-dlp").path,
            ffmpeg: managedBinDirectory.appendingPathComponent("ffmpeg").path,
            ffprobe: managedBinDirectory.appendingPathComponent("ffprobe").path
        )

        let missing = missingManagedTools(for: managedPaths)
        if missing.isEmpty {
            progress(BootstrapSnapshot(
                phase: .ready,
                title: "Ready to launch",
                detail: "All required tools are already installed for this app.",
                progress: 1.0,
                isIndeterminate: false,
                canRetry: false
            ))
            return ToolchainResult(paths: managedPaths, usingManagedTools: true)
        }

        progress(BootstrapSnapshot(
            phase: .preparing,
            title: "Preparing download tools",
            detail: "Installing only the missing tools for this Mac.",
            progress: 0.18,
            isIndeterminate: false,
            canRetry: false
        ))

        let totalSteps = Double(missing.count * 2)
        var completedSteps = 0.0

        for tool in missing {
            switch tool {
            case .ytDlp:
                progress(snapshot(
                    title: "Installing yt-dlp",
                    detail: "Downloading yt-dlp.",
                    completedSteps: completedSteps,
                    totalSteps: totalSteps
                ))
                try await installBinary(from: ytDlpURL, to: URL(fileURLWithPath: managedPaths.ytDlp!))
                completedSteps += 2
            case .ffmpeg:
                progress(snapshot(
                    title: "Installing FFmpeg",
                    detail: "Downloading FFmpeg.",
                    completedSteps: completedSteps,
                    totalSteps: totalSteps
                ))
                try await installZippedBinary(from: ffmpegZipURL, binaryName: "ffmpeg", destination: URL(fileURLWithPath: managedPaths.ffmpeg!))
                completedSteps += 2
            case .ffprobe:
                progress(snapshot(
                    title: "Installing FFprobe",
                    detail: "Downloading FFprobe.",
                    completedSteps: completedSteps,
                    totalSteps: totalSteps
                ))
                try await installZippedBinary(from: ffprobeZipURL, binaryName: "ffprobe", destination: URL(fileURLWithPath: managedPaths.ffprobe!))
                completedSteps += 2
            }
        }

        progress(BootstrapSnapshot(
            phase: .ready,
            title: "Ready to launch",
            detail: "The app is set up and ready.",
            progress: 1.0,
            isIndeterminate: false,
            canRetry: false
        ))
        return ToolchainResult(paths: managedPaths, usingManagedTools: true)
    }

    private func snapshot(title: String, detail: String, completedSteps: Double, totalSteps: Double) -> BootstrapSnapshot {
        let normalized = totalSteps > 0 ? completedSteps / totalSteps : 0
        let progress = min(0.94, 0.18 + normalized * 0.72)
        return BootstrapSnapshot(
            phase: .preparing,
            title: title,
            detail: detail,
            progress: progress,
            isIndeterminate: false,
            canRetry: false
        )
    }

    private func missingManagedTools(for paths: ToolPaths) -> [Tool] {
        var missing: [Tool] = []
        if !isExecutable(paths.ytDlp) { missing.append(.ytDlp) }
        if !isExecutable(paths.ffmpeg) { missing.append(.ffmpeg) }
        if !isExecutable(paths.ffprobe) { missing.append(.ffprobe) }
        return missing
    }

    private func findCompleteSystemToolchain() -> ToolPaths? {
        let ytDlp = firstExecutable(in: [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ])
        let ffmpeg = firstExecutable(in: [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ])
        let ffprobe = firstExecutable(in: [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ])

        guard let ytDlp, let ffmpeg, let ffprobe else { return nil }
        return ToolPaths(ytDlp: ytDlp, ffmpeg: ffmpeg, ffprobe: ffprobe)
    }

    private func firstExecutable(in candidates: [String]) -> String? {
        candidates.first(where: { isExecutable($0) })
    }

    private func isExecutable(_ path: String?) -> Bool {
        guard let path else { return false }
        return fileManager.isExecutableFile(atPath: path)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: userDataDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: managedBinDirectory, withIntermediateDirectories: true)
    }

    private func installBundledToolsIfPresent(progress: @escaping @Sendable (BootstrapSnapshot) -> Void) throws -> ToolPaths? {
        guard let bundledToolsDirectory else { return nil }

        let bundledPaths = ToolPaths(
            ytDlp: bundledToolsDirectory.appendingPathComponent("yt-dlp").path,
            ffmpeg: bundledToolsDirectory.appendingPathComponent("ffmpeg").path,
            ffprobe: bundledToolsDirectory.appendingPathComponent("ffprobe").path
        )

        guard missingManagedTools(for: bundledPaths).isEmpty else {
            return nil
        }

        let managedPaths = ToolPaths(
            ytDlp: managedBinDirectory.appendingPathComponent("yt-dlp").path,
            ffmpeg: managedBinDirectory.appendingPathComponent("ffmpeg").path,
            ffprobe: managedBinDirectory.appendingPathComponent("ffprobe").path
        )

        progress(BootstrapSnapshot(
            phase: .preparing,
            title: "Preparing download tools",
            detail: "Installing bundled helper tools inside the app.",
            progress: 0.34,
            isIndeterminate: false,
            canRetry: false
        ))

        try replaceExecutable(at: URL(fileURLWithPath: bundledPaths.ytDlp!), destination: URL(fileURLWithPath: managedPaths.ytDlp!))
        try replaceExecutable(at: URL(fileURLWithPath: bundledPaths.ffmpeg!), destination: URL(fileURLWithPath: managedPaths.ffmpeg!))
        try replaceExecutable(at: URL(fileURLWithPath: bundledPaths.ffprobe!), destination: URL(fileURLWithPath: managedPaths.ffprobe!))
        return managedPaths
    }

    private func installBinary(from remoteURL: URL, to destination: URL) async throws {
        let tempURL = userDataDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempURL) }

        _ = try await download(remoteURL, to: tempURL)
        try replaceExecutable(at: tempURL, destination: destination)
    }

    private func installZippedBinary(from remoteURL: URL, binaryName: String, destination: URL) async throws {
        let tempZip = userDataDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        let extractDirectory = userDataDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? fileManager.removeItem(at: tempZip)
            try? fileManager.removeItem(at: extractDirectory)
        }

        _ = try await download(remoteURL, to: tempZip)
        try fileManager.createDirectory(at: extractDirectory, withIntermediateDirectories: true)

        try runProcess("/usr/bin/ditto", ["-x", "-k", tempZip.path, extractDirectory.path])
        guard let extractedBinary = try findBinary(named: binaryName, under: extractDirectory) else {
            throw NSError(domain: "ToolchainBootstrapper", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "\(binaryName) could not be found after install."
            ])
        }

        try replaceExecutable(at: extractedBinary, destination: destination)
    }

    private func replaceExecutable(at source: URL, destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try runProcess("/bin/chmod", ["755", destination.path])
        try? runProcess("/usr/bin/xattr", ["-d", "com.apple.quarantine", destination.path])
    }

    private func download(_ remoteURL: URL, to destination: URL) async throws -> URL {
        let (tempFile, response) = try await URLSession.shared.download(from: remoteURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "ToolchainBootstrapper", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not download \(remoteURL.lastPathComponent)."
            ])
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempFile, to: destination)
        return destination
    }

    private func findBinary(named binaryName: String, under directory: URL) throws -> URL? {
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent == binaryName {
                return fileURL
            }
        }
        return nil
    }

    private func runProcess(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown process error."
            throw NSError(domain: "ToolchainBootstrapper", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: output.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
    }
}
