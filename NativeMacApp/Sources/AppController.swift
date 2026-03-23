import AppKit
import SwiftUI

@MainActor
final class AppController: ObservableObject {
    @Published var bootstrap = BootstrapSnapshot()
    @Published var isBootstrapVisible = true
    @Published var updateStatus: UpdateStatus = .idle
    @Published var availableUpdate: AppReleaseInfo?
    @Published var installPrompt: InstallPromptInfo?
    @Published var installErrorMessage: String?
    @Published var isInstallingApp = false
    @Published var themeMode: ThemeMode = .system
    @Published var projectRequired = true
    @Published var projectName = ""
    @Published var urlInput = ""
    @Published var inputSummary = InputSummary()
    @Published var queueItems: [QueueItem] = []
    @Published var recentProjects: [RecentProject] = []
    @Published var projectFieldInvalid = false
    @Published var projectValidationToken = 0

    let maxConcurrentDownloads = 3

    private let bootstrapper = ToolchainBootstrapper()
    private let downloaderEngine = DownloaderEngine()
    private let releaseUpdateChecker = ReleaseUpdateChecker()
    private let appInstaller = AppInstaller()
    private let recentProjectsStore = RecentProjectsStore()
    private var toolPaths = ToolPaths()
    private var mainWindow: NSWindow?
    private var metadataTasks: [UUID: Task<Void, Never>] = [:]
    private var downloadTasks: [UUID: Task<Void, Never>] = [:]
    private var activeDownloadItemIDs: Set<UUID> = []
    private var completionSound: NSSound?
    private var didPlayQueueCompleteSound = false
    private var visualOrderCounter = 0

    private let defaults = UserDefaults.standard
    private let themeKey = "theme_mode"

    func launch() {
        Task { await AppLogger.shared.info("App launch") }
        loadPreferences()
        recentProjects = recentProjectsStore.load()
        openMainWindow()
        Task {
            await prepareApplication()
        }
    }

    func retryBootstrap() {
        Task { await AppLogger.shared.info("Retry bootstrap requested") }
        bootstrap = BootstrapSnapshot()
        isBootstrapVisible = true
        Task {
            await prepareApplication()
        }
    }

    func checkForUpdates(manual: Bool = true) {
        Task {
            await performUpdateCheck(manual: manual)
        }
    }

    func dismissUpdatePrompt() {
        availableUpdate = nil
    }

    func dismissInstallPrompt() {
        installPrompt = nil
        installErrorMessage = nil
    }

    func openLatestRelease() {
        guard let url = availableUpdate?.pageURL else { return }
        NSWorkspace.shared.open(url)
    }

    func installCurrentAppToApplications() {
        guard !isInstallingApp else { return }
        isInstallingApp = true
        installErrorMessage = nil

        Task {
            do {
                Task { await AppLogger.shared.info("Install to Applications started") }
                let installedURL = try await appInstaller.installToApplications(appName: "B-Roll Downloader")
                Task { await AppLogger.shared.info("Install to Applications complete: \(installedURL.path)") }
                await MainActor.run {
                    self.installPrompt = nil
                    self.isInstallingApp = false
                }
                await appInstaller.relaunchInstalledApp(at: installedURL)
            } catch {
                Task { await AppLogger.shared.error("Install to Applications failed: \(error.localizedDescription)") }
                await MainActor.run {
                    self.isInstallingApp = false
                    self.installErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func updateInputSummary() {
        let parsed = YouTubeURLParser.parse(urlInput)
        inputSummary = InputSummary(
            validCount: parsed.normalizedURLs.count,
            duplicateCount: parsed.duplicateCount,
            invalidCount: parsed.invalidCount
        )
    }

    func submitBatch() {
        let trimmedProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if projectRequired && trimmedProjectName.isEmpty {
            Task { await AppLogger.shared.info("Submit blocked: missing required project name") }
            projectValidationToken += 1
            withAnimation(.easeInOut(duration: 0.14)) {
                projectFieldInvalid = true
            }
            Task {
                try? await Task.sleep(for: .milliseconds(850))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.18)) {
                        self.projectFieldInvalid = false
                    }
                }
            }
            return
        }

        let parsed = YouTubeURLParser.parse(urlInput)
        inputSummary = InputSummary(
            validCount: parsed.normalizedURLs.count,
            duplicateCount: parsed.duplicateCount,
            invalidCount: parsed.invalidCount
        )

        guard !parsed.normalizedURLs.isEmpty else { return }
        Task { await AppLogger.shared.info("Submitting batch with \(parsed.normalizedURLs.count) URLs") }

        queueItems.removeAll { $0.status == .complete }
        didPlayQueueCompleteSound = false
        projectFieldInvalid = false
        NSApp.keyWindow?.makeFirstResponder(nil)

        if projectRequired {
            recentProjects = recentProjectsStore.record(name: trimmedProjectName)
        }

        let effectiveProjectName = trimmedProjectName
        for normalizedURL in parsed.normalizedURLs {
            visualOrderCounter += 1
            let item = QueueItem(
                id: UUID(),
                visualOrder: visualOrderCounter,
                originalURL: normalizedURL,
                normalizedURL: normalizedURL,
                projectName: effectiveProjectName,
                title: "Resolving YouTube metadata…",
                channel: "Fetching details",
                uploadDate: nil,
                status: .resolving,
                progress: 0.02,
                metadata: nil,
                errorMessage: nil,
                outputPath: nil,
                tempDirectory: nil,
                shortCode: nil,
                estimatedSizeBytes: nil,
                submittedAt: Date()
            )
            queueItems.append(item)
            resolveMetadata(for: item.id)
        }

        urlInput = ""
        inputSummary = InputSummary()
    }

    func cancel(_ itemID: UUID) {
        Task { await AppLogger.shared.info("Cancel requested for item \(itemID.uuidString)") }
        metadataTasks[itemID]?.cancel()
        metadataTasks[itemID] = nil
        downloadTasks[itemID]?.cancel()
        downloadTasks[itemID] = nil
        Task {
            await downloaderEngine.cancel(itemID)
        }
        activeDownloadItemIDs.remove(itemID)

        guard let index = queueItems.firstIndex(where: { $0.id == itemID }) else { return }
        queueItems[index].status = .aborted
        queueItems[index].progress = max(queueItems[index].progress, 0.01)
        queueItems[index].errorMessage = nil
        scheduleDownloadsIfPossible()
        maybePlayCompletionSound()
    }

    func clearQueue() {
        Task { await AppLogger.shared.info("Clear queue requested") }
        let ids = queueItems.map(\.id)
        for id in ids {
            metadataTasks[id]?.cancel()
            downloadTasks[id]?.cancel()
        }
        metadataTasks.removeAll()
        downloadTasks.removeAll()
        Task {
            for id in ids {
                await downloaderEngine.cancel(id)
            }
        }
        activeDownloadItemIDs.removeAll()
        queueItems.removeAll()
        inputSummary = InputSummary()
        didPlayQueueCompleteSound = false
    }

    func setThemeMode(_ mode: ThemeMode) {
        themeMode = mode
        defaults.set(mode.rawValue, forKey: themeKey)
        applyAppearance()
    }

    func setProjectRequired(_ isRequired: Bool) {
        projectRequired = isRequired
    }

    func removeRecentProject(named name: String) {
        recentProjects = recentProjectsStore.remove(name: name)
    }

    func useRecentProject(named name: String) {
        projectName = name
        projectFieldInvalid = false
    }

    var isQueueRunning: Bool {
        queueItems.contains(where: { $0.status.isActive })
    }

    var primaryButtonLabel: String {
        if isQueueRunning && inputSummary.validCount > 0 {
            return "Add to Queue"
        }
        return "Start Download"
    }

    var appVersionLabel: String {
        currentAppVersion
    }

    var buildChannelLabel: String {
        buildChannel == "local" ? "Local Build" : "Release Build"
    }

    var queueStatusSummary: String {
        let downloadingCount = queueItems.filter { $0.status == .downloading }.count
        let convertingCount = queueItems.filter { $0.status == .converting }.count
        let queuedCount = queueItems.filter { $0.status == .queued || $0.status == .resolving }.count

        let parts = [
            downloadingCount > 0 ? "\(downloadingCount) downloading" : nil,
            convertingCount > 0 ? "\(convertingCount) converting" : nil,
            queuedCount > 0 ? "\(queuedCount) queued" : nil
        ].compactMap { $0 }

        return parts.isEmpty ? "Ready for a new batch." : parts.joined(separator: " · ")
    }

    var updateStatusLabel: String {
        switch updateStatus {
        case .idle:
            return "Check for Updates"
        case .checking:
            return "Checking Updates…"
        case .localBuild:
            return "Local Build"
        case .upToDate:
            return "Up to Date"
        case .available:
            return "Update Available"
        case .failed:
            return "Update Check Failed"
        }
    }

    var installPromptDescription: String {
        if let existingVersion = installPrompt?.existingVersion {
            return "Move this build into Applications and replace version \(existingVersion) there."
        }
        return "Move this build into Applications so future updates replace the main copy cleanly."
    }

    private func loadPreferences() {
        if let storedTheme = defaults.string(forKey: themeKey), let themeMode = ThemeMode(rawValue: storedTheme) {
            self.themeMode = themeMode
        }

        projectRequired = true
        applyAppearance()
    }

    private func applyAppearance() {
        switch themeMode {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system:
            NSApp.appearance = nil
        }
    }

    private func prepareApplication() async {
        do {
            bootstrap = BootstrapSnapshot(
                phase: .preparing,
                title: "Preparing download tools",
                detail: "Checking what this Mac already has.",
                progress: 0.08,
                isIndeterminate: false,
                canRetry: false
            )

            let result = try await bootstrapper.ensureReady { [weak self] snapshot in
                Task { @MainActor in
                    self?.bootstrap = snapshot
                }
            }
            Task { await AppLogger.shared.info("Tool bootstrap complete") }

            toolPaths = result.paths
            completionSound = loadCompletionSound()
            installPrompt = await appInstaller.installationPrompt(appName: "B-Roll Downloader")

            try? await Task.sleep(for: .milliseconds(220))
            bootstrap.phase = .ready
            isBootstrapVisible = false
            await performUpdateCheck(manual: false)
        } catch {
            Task { await AppLogger.shared.error("Bootstrap failed: \(error.localizedDescription)") }
            bootstrap = BootstrapSnapshot(
                phase: .failed,
                title: "Setup could not finish",
                detail: error.localizedDescription,
                progress: 1.0,
                isIndeterminate: false,
                canRetry: true
            )
            isBootstrapVisible = true
        }
    }

    private func resolveMetadata(for itemID: UUID) {
        guard let item = queueItems.first(where: { $0.id == itemID }) else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let metadata = try await self.downloaderEngine.fetchMetadata(for: item.normalizedURL, toolPaths: self.toolPaths)
                await MainActor.run {
                    guard let index = self.queueItems.firstIndex(where: { $0.id == itemID }) else { return }
                    self.queueItems[index].metadata = metadata
                    self.queueItems[index].title = metadata.title
                    self.queueItems[index].channel = metadata.channel
                    self.queueItems[index].uploadDate = metadata.uploadDate
                    self.queueItems[index].estimatedSizeBytes = metadata.estimatedSizeBytes
                    self.queueItems[index].status = .queued
                    self.queueItems[index].progress = 0.04
                    self.queueItems[index].errorMessage = nil
                    self.metadataTasks[itemID] = nil
                    Task { await AppLogger.shared.info("Metadata resolved for item \(itemID.uuidString): \(metadata.title)") }
                    self.scheduleDownloadsIfPossible()
                }
            } catch is CancellationError {
                Task { await AppLogger.shared.info("Metadata task cancelled for item \(itemID.uuidString)") }
            } catch {
                await MainActor.run {
                    guard let index = self.queueItems.firstIndex(where: { $0.id == itemID }) else { return }
                    self.queueItems[index].status = .failed
                    self.queueItems[index].progress = 1.0
                    self.queueItems[index].errorMessage = error.localizedDescription
                    self.metadataTasks[itemID] = nil
                    Task { await AppLogger.shared.error("Metadata failed for item \(itemID.uuidString): \(error.localizedDescription)") }
                    self.maybePlayCompletionSound()
                }
            }
        }

        metadataTasks[itemID] = task
    }

    private func scheduleDownloadsIfPossible() {
        guard toolPaths.isReady else { return }

        let activeCount = activeDownloadItemIDs.count
        let candidates = queueItems
            .filter { $0.status == .queued && $0.metadata != nil && downloadTasks[$0.id] == nil }
            .sorted { lhs, rhs in
                let leftSize = lhs.estimatedSizeBytes ?? Int64.max
                let rightSize = rhs.estimatedSizeBytes ?? Int64.max
                if leftSize == rightSize {
                    return lhs.visualOrder < rhs.visualOrder
                }
                return leftSize < rightSize
            }

        Task {
            await AppLogger.shared.info(
                "schedule: activeDownloads=\(activeCount) queuedCandidates=\(candidates.count)"
            )
        }

        guard activeCount < maxConcurrentDownloads else { return }

        for item in candidates.prefix(maxConcurrentDownloads - activeCount) {
            startDownload(for: item.id)
        }
    }

    private func startDownload(for itemID: UUID) {
        guard let item = queueItems.first(where: { $0.id == itemID }), let metadata = item.metadata else { return }
        activeDownloadItemIDs.insert(itemID)

        queueItems = queueItems.map { current in
            guard current.id == itemID else { return current }
            var updated = current
            updated.status = .downloading
            updated.progress = max(updated.progress, 0.06)
            return updated
        }
        didPlayQueueCompleteSound = false
        Task { await AppLogger.shared.info("Starting download for item \(itemID.uuidString)") }

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let artifact = try await self.downloaderEngine.download(
                    itemID: itemID,
                    normalizedURL: item.normalizedURL,
                    projectName: item.projectName,
                    metadata: metadata,
                    toolPaths: self.toolPaths
                ) { update in
                    Task { @MainActor in
                        guard let index = self.queueItems.firstIndex(where: { $0.id == itemID }) else { return }
                        guard !self.queueItems[index].status.isTerminal else { return }
                        switch update.stage {
                        case .downloading:
                            self.queueItems[index].status = .downloading
                            self.queueItems[index].progress = min(max(update.progress, 0.02), 0.99)
                        case .converting:
                            self.activeDownloadItemIDs.remove(itemID)
                            Task {
                                await AppLogger.shared.info(
                                    "schedule: slot-freed item=\(itemID.uuidString) activeDownloads=\(self.activeDownloadItemIDs.count)"
                                )
                            }
                            self.queueItems[index].status = .converting
                            self.queueItems[index].progress = min(max(update.progress, 0.02), 0.99)
                            self.scheduleDownloadsIfPossible()
                        }
                    }
                }

                await MainActor.run {
                    guard let index = self.queueItems.firstIndex(where: { $0.id == itemID }) else { return }
                    self.downloadTasks[itemID] = nil
                    self.activeDownloadItemIDs.remove(itemID)
                    guard self.queueItems[index].status != .aborted else {
                        Task { await AppLogger.shared.info("Download finished after abort for item \(itemID.uuidString)") }
                        self.scheduleDownloadsIfPossible()
                        self.maybePlayCompletionSound()
                        return
                    }
                    self.queueItems[index].status = .complete
                    self.queueItems[index].progress = 1.0
                    self.queueItems[index].outputPath = artifact.outputURL.path
                    self.queueItems[index].shortCode = artifact.shortCode
                    self.queueItems[index].errorMessage = nil
                    Task { await AppLogger.shared.info("Item \(itemID.uuidString) complete") }
                    self.scheduleDownloadsIfPossible()
                    self.maybePlayCompletionSound()
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let index = self.queueItems.firstIndex(where: { $0.id == itemID }) else { return }
                    self.downloadTasks[itemID] = nil
                    self.activeDownloadItemIDs.remove(itemID)
                    guard self.queueItems[index].status != .aborted else {
                        Task { await AppLogger.shared.info("Cancellation observed for item \(itemID.uuidString)") }
                        self.scheduleDownloadsIfPossible()
                        self.maybePlayCompletionSound()
                        return
                    }
                    self.queueItems[index].status = .aborted
                    self.queueItems[index].progress = max(self.queueItems[index].progress, 0.02)
                    self.queueItems[index].errorMessage = nil
                    Task { await AppLogger.shared.info("Item \(itemID.uuidString) marked aborted") }
                    self.scheduleDownloadsIfPossible()
                    self.maybePlayCompletionSound()
                }
            } catch {
                await MainActor.run {
                    guard let index = self.queueItems.firstIndex(where: { $0.id == itemID }) else { return }
                    self.downloadTasks[itemID] = nil
                    self.activeDownloadItemIDs.remove(itemID)
                    guard self.queueItems[index].status != .aborted else {
                        Task { await AppLogger.shared.info("Error observed after abort for item \(itemID.uuidString): \(error.localizedDescription)") }
                        self.scheduleDownloadsIfPossible()
                        self.maybePlayCompletionSound()
                        return
                    }
                    self.queueItems[index].status = .failed
                    self.queueItems[index].progress = 1.0
                    self.queueItems[index].errorMessage = error.localizedDescription
                    Task { await AppLogger.shared.error("Item \(itemID.uuidString) failed: \(error.localizedDescription)") }
                    self.scheduleDownloadsIfPossible()
                    self.maybePlayCompletionSound()
                }
            }
        }

        downloadTasks[itemID] = task
    }

    private func maybePlayCompletionSound() {
        guard !didPlayQueueCompleteSound else { return }
        guard !queueItems.isEmpty else { return }
        guard queueItems.allSatisfy({ $0.status.isTerminal }) else { return }
        completionSound?.stop()
        completionSound?.play()
        didPlayQueueCompleteSound = true
    }

    private func loadCompletionSound() -> NSSound? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("completion-beep.mp3") else {
            return nil
        }
        return NSSound(contentsOf: url, byReference: false)
    }

    private var buildChannel: String {
        (Bundle.main.object(forInfoDictionaryKey: "BRollBuildChannel") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "local"
    }

    private var currentAppVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0.0.0"
    }

    private func performUpdateCheck(manual: Bool) async {
        if buildChannel == "local" {
            await MainActor.run {
                self.updateStatus = .localBuild
            }
            if manual {
                Task { await AppLogger.shared.info("Update check skipped for local build") }
            }
            return
        }

        await MainActor.run {
            self.updateStatus = .checking
        }
        Task { await AppLogger.shared.info("Update check started for version \(currentAppVersion)") }

        do {
            if let release = try await releaseUpdateChecker.check(currentVersion: currentAppVersion) {
                Task { await AppLogger.shared.info("Update available: \(release.version)") }
                await MainActor.run {
                    self.availableUpdate = release
                    self.updateStatus = .available(release)
                }
            } else {
                Task { await AppLogger.shared.info("Update check complete: up to date") }
                await MainActor.run {
                    self.updateStatus = .upToDate
                }
            }
        } catch {
            Task { await AppLogger.shared.error("Update check failed: \(error.localizedDescription)") }
            await MainActor.run {
                self.updateStatus = .failed(error.localizedDescription)
            }
        }
    }

    private func openMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "B-Roll Downloader"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
            window.center()
            window.contentView = NSHostingView(rootView: MainShellView(controller: self))
            window.makeKeyAndOrderFront(nil)
            self.mainWindow = window
        } else {
            mainWindow?.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
    }
}
