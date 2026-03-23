import Foundation

struct DownloadProgressUpdate: Sendable {
    enum Stage: Sendable {
        case downloading
        case converting
    }

    var stage: Stage
    var progress: Double
}

struct DownloadArtifact: Sendable {
    var outputURL: URL
    var shortCode: String?
}

private struct FFprobeResult: Decodable {
    var streams: [FFprobeStream]
    var format: FFprobeFormat?
}

private struct FFprobeStream: Decodable {
    var codecName: String?
    var codecType: String?

    enum CodingKeys: String, CodingKey {
        case codecName = "codec_name"
        case codecType = "codec_type"
    }
}

private struct FFprobeFormat: Decodable {
    var formatName: String?
    var duration: String?

    enum CodingKeys: String, CodingKey {
        case formatName = "format_name"
        case duration
    }
}

private struct YTDLPMetadata: Decodable {
    var id: String
    var title: String?
    var uploader: String?
    var channel: String?
    var uploadDate: String?
    var duration: Double?
    var filesize: Int64?
    var filesizeApprox: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case uploader
        case channel
        case uploadDate = "upload_date"
        case duration
        case filesize
        case filesizeApprox = "filesize_approx"
    }
}

private struct ProcessCapture {
    var stdout: String
    var stderr: String
}

private struct MediaInspection {
    var videoCodec: String?
    var audioCodec: String?
    var durationSeconds: Double?
    var formatNames: [String]
    var sourceExtension: String
}

private enum OutputAction {
    case keepOriginal
    case remuxToMP4
    case transcodeAudioToAAC
    case transcodeVideoAndAudio
}

private final class ProcessBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

    func appendStdout(_ data: Data, callback: (@Sendable (String) -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        consume(data, aggregate: &stdoutData, buffer: &stdoutBuffer, callback: callback)
    }

    func appendStderr(_ data: Data, callback: (@Sendable (String) -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        consume(data, aggregate: &stderrData, buffer: &stderrBuffer, callback: callback)
    }

    func finish(stdoutCallback: (@Sendable (String) -> Void)?, stderrCallback: (@Sendable (String) -> Void)?) -> ProcessCapture {
        lock.lock()
        defer { lock.unlock() }

        if !stdoutBuffer.isEmpty,
           let line = String(data: stdoutBuffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty {
            stdoutCallback?(line)
        }

        if !stderrBuffer.isEmpty,
           let line = String(data: stderrBuffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty {
            stderrCallback?(line)
        }

        return ProcessCapture(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private func consume(
        _ data: Data,
        aggregate: inout Data,
        buffer: inout Data,
        callback: (@Sendable (String) -> Void)?
    ) {
        aggregate.append(data)
        buffer.append(data)

        while let newlineRange = buffer.range(of: Data([0x0a])) {
            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0...newlineRange.lowerBound)
            if let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !line.isEmpty {
                callback?(line)
            }
        }
    }
}

actor DownloaderEngine {
    private let fileManager = FileManager.default
    private let appSupportDirectory: URL
    private let jobsDirectory: URL
    private let outputDirectory: URL
    private let processorCount = max(ProcessInfo.processInfo.processorCount, 1)
    private var activeProcesses: [UUID: [Process]] = [:]
    private var activeOutputURLs: [UUID: URL] = [:]

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.appSupportDirectory = appSupport.appendingPathComponent("B-Roll Downloader", isDirectory: true)
        self.jobsDirectory = appSupportDirectory.appendingPathComponent("jobs", isDirectory: true)
        self.outputDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("B-Roll", isDirectory: true)
    }

    func fetchMetadata(for normalizedURL: String, toolPaths: ToolPaths) async throws -> VideoMetadata {
        guard let ytDlp = toolPaths.ytDlp else {
            throw NSError(domain: "DownloaderEngine", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "yt-dlp is not available yet."
            ])
        }

        try ensureDirectories()
        await AppLogger.shared.info("fetchMetadata:start url=\(normalizedURL)")

        let capture = try await runProcess(
            executable: ytDlp,
            arguments: ["--dump-single-json", "--skip-download", "--no-warnings", normalizedURL],
            itemID: nil
        )

        guard let data = capture.stdout.data(using: .utf8) else {
            throw NSError(domain: "DownloaderEngine", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not read YouTube metadata."
            ])
        }

        let decoded = try JSONDecoder().decode(YTDLPMetadata.self, from: data)
        let formattedDate = Self.formatUploadDate(decoded.uploadDate) ?? Self.todayString()
        return VideoMetadata(
            id: decoded.id,
            title: Self.cleanLabel(decoded.title, fallback: "Untitled Video"),
            channel: Self.cleanLabel(decoded.channel ?? decoded.uploader, fallback: "Unknown Channel"),
            uploadDate: formattedDate,
            duration: decoded.duration,
            estimatedSizeBytes: decoded.filesize ?? decoded.filesizeApprox
        )
    }

    func download(
        itemID: UUID,
        normalizedURL: String,
        projectName: String,
        metadata: VideoMetadata,
        toolPaths: ToolPaths,
        progress: @escaping @Sendable (DownloadProgressUpdate) -> Void
    ) async throws -> DownloadArtifact {
        guard
            let ytDlp = toolPaths.ytDlp,
            let ffmpeg = toolPaths.ffmpeg
        else {
            throw NSError(domain: "DownloaderEngine", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "The download tools are not ready yet."
            ])
        }

        try ensureDirectories()
        await AppLogger.shared.info("download:start item=\(itemID.uuidString) url=\(normalizedURL)")

        let tempDirectory = jobsDirectory.appendingPathComponent(itemID.uuidString, isDirectory: true)
        try? fileManager.removeItem(at: tempDirectory)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let shortCode = await generateShortCode(for: normalizedURL)
        let finalOutputURL = uniqueOutputURL(for: metadata, projectName: projectName, shortCode: shortCode)
        activeOutputURLs[itemID] = finalOutputURL

        let template = tempDirectory.appendingPathComponent("source.%(ext)s").path
        _ = try await runProcess(
            executable: ytDlp,
            arguments: [
                "--newline",
                "-f", "bv*+ba/b",
                "--merge-output-format", "mkv",
                "-o", template,
                normalizedURL
            ],
            itemID: itemID,
            onStdoutLine: { line in
                if let percent = Self.parsePercent(from: line) {
                    progress(DownloadProgressUpdate(stage: .downloading, progress: min(max(percent / 100.0, 0.0), 1.0)))
                }
            },
            onStderrLine: { line in
                if let percent = Self.parsePercent(from: line) {
                    progress(DownloadProgressUpdate(stage: .downloading, progress: min(max(percent / 100.0, 0.0), 1.0)))
                }
            }
        )

        let sourceURL = try locateDownloadedMedia(in: tempDirectory)
        await AppLogger.shared.info("download:source-ready item=\(itemID.uuidString) source=\(sourceURL.lastPathComponent)")
        progress(DownloadProgressUpdate(stage: .converting, progress: 0.0))

        let inspection = try await inspectMedia(at: sourceURL, ffprobePath: toolPaths.ffprobe)
        let durationSeconds = metadata.duration ?? inspection.durationSeconds
        let outputAction = Self.chooseOutputAction(for: inspection)
        await AppLogger.shared.info("download:action item=\(itemID.uuidString) action=\(String(describing: outputAction)) video=\(inspection.videoCodec ?? "nil") audio=\(inspection.audioCodec ?? "nil") ext=\(inspection.sourceExtension)")

        switch outputAction {
        case .keepOriginal:
            progress(DownloadProgressUpdate(stage: .converting, progress: 0.2))
            if fileManager.fileExists(atPath: finalOutputURL.path) {
                try fileManager.removeItem(at: finalOutputURL)
            }
            try fileManager.moveItem(at: sourceURL, to: finalOutputURL)
        case .remuxToMP4:
            progress(DownloadProgressUpdate(stage: .converting, progress: 0.05))
            _ = try await runProcess(
                executable: ffmpeg,
                arguments: [
                    "-y",
                    "-i", sourceURL.path,
                    "-c", "copy",
                    "-movflags", "+faststart",
                    "-progress", "pipe:1",
                    "-nostats",
                    finalOutputURL.path
                ],
                itemID: itemID,
                onStdoutLine: { line in
                    if let ratio = Self.parseFFmpegProgress(line: line, durationSeconds: durationSeconds) {
                        progress(DownloadProgressUpdate(stage: .converting, progress: ratio))
                    }
                }
            )
        case .transcodeAudioToAAC:
            progress(DownloadProgressUpdate(stage: .converting, progress: 0.05))
            _ = try await runProcess(
                executable: ffmpeg,
                arguments: transcodeAudioArguments(
                    sourcePath: sourceURL.path,
                    outputPath: finalOutputURL.path,
                    hasAudio: inspection.audioCodec != nil
                ),
                itemID: itemID,
                onStdoutLine: { line in
                    if let ratio = Self.parseFFmpegProgress(line: line, durationSeconds: durationSeconds) {
                        progress(DownloadProgressUpdate(stage: .converting, progress: ratio))
                    }
                }
            )
        case .transcodeVideoAndAudio:
            progress(DownloadProgressUpdate(stage: .converting, progress: 0.05))
            _ = try await runProcess(
                executable: ffmpeg,
                arguments: transcodeVideoArguments(
                    sourcePath: sourceURL.path,
                    outputPath: finalOutputURL.path,
                    hasAudio: inspection.audioCodec != nil
                ),
                itemID: itemID,
                onStdoutLine: { line in
                    if let ratio = Self.parseFFmpegProgress(line: line, durationSeconds: durationSeconds) {
                        progress(DownloadProgressUpdate(stage: .converting, progress: ratio))
                    }
                }
            )
        }

        try? fileManager.removeItem(at: tempDirectory)
        activeOutputURLs[itemID] = nil
        await AppLogger.shared.info("download:done item=\(itemID.uuidString) output=\(finalOutputURL.lastPathComponent)")
        return DownloadArtifact(outputURL: finalOutputURL, shortCode: shortCode)
    }

    func cleanupJob(_ itemID: UUID) {
        let tempDirectory = jobsDirectory.appendingPathComponent(itemID.uuidString, isDirectory: true)
        try? fileManager.removeItem(at: tempDirectory)
        if let outputURL = activeOutputURLs[itemID] {
            try? fileManager.removeItem(at: outputURL)
            activeOutputURLs[itemID] = nil
        }
    }

    func cancel(_ itemID: UUID) {
        Task { await AppLogger.shared.info("engine:cancel item=\(itemID.uuidString)") }
        let processes = activeProcesses[itemID] ?? []
        for process in processes where process.isRunning {
            process.terminate()
        }
        activeProcesses[itemID] = nil
        cleanupJob(itemID)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: jobsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    private func locateDownloadedMedia(in directory: URL) throws -> URL {
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            let filename = fileURL.lastPathComponent.lowercased()
            if filename.hasSuffix(".part") || filename.hasSuffix(".ytdl") {
                continue
            }
            if fileURL.pathExtension.lowercased() == "json" {
                continue
            }
            return fileURL
        }

        throw NSError(domain: "DownloaderEngine", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "The downloaded media file could not be found."
        ])
    }

    private func inspectMedia(at inputURL: URL, ffprobePath: String?) async throws -> MediaInspection {
        guard let ffprobePath else {
            return MediaInspection(
                videoCodec: nil,
                audioCodec: nil,
                durationSeconds: nil,
                formatNames: [],
                sourceExtension: inputURL.pathExtension.lowercased()
            )
        }

        await AppLogger.shared.info("inspectMedia:start path=\(inputURL.lastPathComponent)")
        let capture = try await runProcess(
            executable: ffprobePath,
            arguments: [
                "-v", "error",
                "-print_format", "json",
                "-show_streams",
                "-show_format",
                inputURL.path
            ],
            itemID: nil
        )

        guard let data = capture.stdout.data(using: .utf8) else {
            throw NSError(domain: "DownloaderEngine", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Could not inspect media."
            ])
        }

        let decoded = try JSONDecoder().decode(FFprobeResult.self, from: data)

        let videoCodec = decoded.streams.first(where: { $0.codecType == "video" })?.codecName?.lowercased()
        let audioCodec = decoded.streams.first(where: { $0.codecType == "audio" })?.codecName?.lowercased()
        let durationSeconds = decoded.format?.duration.flatMap(Double.init)
        let formatNames = decoded.format?.formatName?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } ?? []

        return MediaInspection(
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            durationSeconds: durationSeconds,
            formatNames: formatNames,
            sourceExtension: inputURL.pathExtension.lowercased()
        )
    }

    private func transcodeAudioArguments(sourcePath: String, outputPath: String, hasAudio: Bool) -> [String] {
        var arguments = [
            "-y",
            "-i", sourcePath,
            "-threads", "\(processorCount)",
            "-c:v", "copy"
        ]

        if hasAudio {
            arguments.append(contentsOf: [
                "-c:a", "aac",
                "-b:a", "192k"
            ])
        } else {
            arguments.append("-an")
        }

        arguments.append(contentsOf: [
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
            outputPath
        ])

        return arguments
    }

    private func transcodeVideoArguments(sourcePath: String, outputPath: String, hasAudio: Bool) -> [String] {
        var arguments = [
            "-y",
            "-i", sourcePath,
            "-threads", "\(processorCount)",
            "-c:v", "libx264",
            "-preset", "medium",
            "-crf", "18"
        ]

        if hasAudio {
            arguments.append(contentsOf: [
                "-c:a", "aac",
                "-b:a", "192k"
            ])
        } else {
            arguments.append("-an")
        }

        arguments.append(contentsOf: [
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
            outputPath
        ])

        return arguments
    }

    private func uniqueOutputURL(for metadata: VideoMetadata, projectName: String, shortCode: String?) -> URL {
        let baseName = Self.buildFilename(
            title: metadata.title,
            channel: metadata.channel,
            uploadDate: metadata.uploadDate,
            videoID: metadata.id,
            shortCode: shortCode,
            projectName: projectName
        )

        var candidate = outputDirectory.appendingPathComponent(baseName).appendingPathExtension("mp4")
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = outputDirectory
                .appendingPathComponent("\(baseName) (\(index))")
                .appendingPathExtension("mp4")
            index += 1
        }
        return candidate
    }

    private func generateShortCode(for normalizedURL: String) async -> String? {
        guard var components = URLComponents(string: "https://is.gd/create.php") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "format", value: "simple"),
            URLQueryItem(name: "url", value: normalizedURL)
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                let body = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !body.lowercased().contains("error")
            else {
                return nil
            }

            if let shortURL = URL(string: body), !shortURL.path.isEmpty {
                return shortURL.path.replacingOccurrences(of: "/", with: "")
            }

            return body.replacingOccurrences(of: "https://is.gd/", with: "")
                .replacingOccurrences(of: "http://is.gd/", with: "")
                .replacingOccurrences(of: "/", with: "")
        } catch {
            return nil
        }
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        itemID: UUID?,
        onStdoutLine: (@Sendable (String) -> Void)? = nil,
        onStderrLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessCapture {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let buffer = ProcessBuffer()

        await AppLogger.shared.info("runProcess:start executable=\((executable as NSString).lastPathComponent) item=\(itemID?.uuidString ?? "none")")

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        handle.readabilityHandler = nil
                        return
                    }

                    buffer.appendStdout(data, callback: onStdoutLine)
                }

                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        handle.readabilityHandler = nil
                        return
                    }

                    buffer.appendStderr(data, callback: onStderrLine)
                }

                do {
                    try process.run()
                    Task { self.register(process: process, for: itemID) }

                    DispatchQueue.global(qos: .userInitiated).async {
                        process.waitUntilExit()
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil

                        let capture = buffer.finish(stdoutCallback: onStdoutLine, stderrCallback: onStderrLine)

                        Task { await self.unregister(process: process, for: itemID) }

                        if process.terminationReason == .uncaughtSignal {
                            Task { await AppLogger.shared.info("runProcess:cancelled executable=\((executable as NSString).lastPathComponent) item=\(itemID?.uuidString ?? "none")") }
                            continuation.resume(throwing: CancellationError())
                            return
                        }

                        guard process.terminationStatus == 0 else {
                            let message = [capture.stderr, capture.stdout]
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .first(where: { !$0.isEmpty }) ?? "Command failed."
                            continuation.resume(throwing: NSError(
                                domain: "DownloaderEngine",
                                code: Int(process.terminationStatus),
                                userInfo: [NSLocalizedDescriptionKey: message]
                            ))
                            Task { await AppLogger.shared.error("runProcess:failed executable=\((executable as NSString).lastPathComponent) item=\(itemID?.uuidString ?? "none") status=\(process.terminationStatus) message=\(message)") }
                            return
                        }

                        Task { await AppLogger.shared.info("runProcess:done executable=\((executable as NSString).lastPathComponent) item=\(itemID?.uuidString ?? "none")") }
                        continuation.resume(returning: capture)
                    }
                } catch {
                    Task { await AppLogger.shared.error("runProcess:launch-failed executable=\((executable as NSString).lastPathComponent) item=\(itemID?.uuidString ?? "none") message=\(error.localizedDescription)") }
                    continuation.resume(throwing: error)
                }
            }
        }, onCancel: {
            process.terminate()
        })
    }

    private func register(process: Process, for itemID: UUID?) {
        guard let itemID else { return }
        activeProcesses[itemID, default: []].append(process)
    }

    private func unregister(process: Process, for itemID: UUID?) {
        guard let itemID else { return }
        activeProcesses[itemID]?.removeAll { $0 === process }
        if activeProcesses[itemID]?.isEmpty == true {
            activeProcesses[itemID] = nil
        }
    }

    private static func buildFilename(
        title: String,
        channel: String,
        uploadDate: String,
        videoID: String,
        shortCode: String?,
        projectName: String
    ) -> String {
        let archiveBlock = shortCode.map { "[\(videoID)] [\($0)]" } ?? "[\(videoID)]"
        let parts = [
            sanitize(title),
            sanitize(channel),
            sanitize(uploadDate),
            archiveBlock,
            sanitize(projectName)
        ]
        .filter { !$0.isEmpty }
        return parts.joined(separator: " - ")
    }

    private static func sanitize(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = value
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }

    private static func cleanLabel(_ value: String?, fallback: String) -> String {
        guard let value else { return fallback }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func parsePercent(from line: String) -> Double? {
        guard let range = line.range(of: #"([0-9]+(?:\.[0-9]+)?)%"#, options: .regularExpression) else {
            return nil
        }
        let value = String(line[range]).replacingOccurrences(of: "%", with: "")
        return Double(value)
    }

    private static func parseFFmpegProgress(line: String, durationSeconds: Double?) -> Double? {
        if line == "progress=end" {
            return 1.0
        }

        guard let durationSeconds, durationSeconds > 0 else { return nil }

        if line.hasPrefix("out_time_us="),
           let microseconds = Double(line.replacingOccurrences(of: "out_time_us=", with: "")) {
            return min(max(microseconds / 1_000_000.0 / durationSeconds, 0.0), 1.0)
        }

        if line.hasPrefix("out_time_ms="),
           let milliseconds = Double(line.replacingOccurrences(of: "out_time_ms=", with: "")) {
            return min(max(milliseconds / 1_000_000.0 / durationSeconds, 0.0), 1.0)
        }

        return nil
    }

    private static func chooseOutputAction(for inspection: MediaInspection) -> OutputAction {
        let videoCodec = inspection.videoCodec ?? ""
        let audioCodec = inspection.audioCodec
        let sourceIsMP4 = inspection.sourceExtension == "mp4"

        let premiereFriendlyVideo = Set(["h264"])
        let premiereFriendlyAudio = Set(["aac", "pcm_s16le", "pcm_s24le", "pcm_f32le", "alac"])
        let mp4SafeVideo = Set(["h264"])
        let mp4SafeAudio = Set(["aac", "alac", "ac3", "eac3", "mp3"])

        let videoIsFriendly = premiereFriendlyVideo.contains(videoCodec)
        let audioIsFriendly = audioCodec == nil || premiereFriendlyAudio.contains(audioCodec!)
        let videoCanBeCopiedIntoMP4 = mp4SafeVideo.contains(videoCodec)
        let audioCanBeCopiedIntoMP4 = audioCodec == nil || mp4SafeAudio.contains(audioCodec!)

        if sourceIsMP4 && videoIsFriendly && audioIsFriendly {
            return .keepOriginal
        }

        if videoIsFriendly && !audioIsFriendly {
            return .transcodeAudioToAAC
        }

        if videoCanBeCopiedIntoMP4 && audioCanBeCopiedIntoMP4 {
            return .remuxToMP4
        }

        return .transcodeVideoAndAudio
    }

    private static func formatUploadDate(_ raw: String?) -> String? {
        guard let raw, raw.count == 8 else { return nil }
        let year = raw.prefix(4)
        let month = raw.dropFirst(4).prefix(2)
        let day = raw.suffix(2)
        return "\(year)-\(month)-\(day)"
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
