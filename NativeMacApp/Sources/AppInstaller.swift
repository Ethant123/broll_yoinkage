import AppKit
import Foundation

actor AppInstaller {
    private let fileManager = FileManager.default

    func installationPrompt(appName: String) -> InstallPromptInfo? {
        guard let bundleURL = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath() as URL? else {
            return nil
        }

        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let destinationURL = applicationsURL.appendingPathComponent("\(appName).app", isDirectory: true)

        if bundleURL.path == destinationURL.path {
            return nil
        }

        if bundleURL.path.hasPrefix(applicationsURL.path + "/") {
            return nil
        }

        let existingVersion = bundleVersion(at: destinationURL)
        return InstallPromptInfo(
            sourcePath: bundleURL.path,
            destinationPath: destinationURL.path,
            existingVersion: existingVersion
        )
    }

    func installToApplications(appName: String) throws -> URL {
        let sourceURL = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        let destinationURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent("\(appName).app", isDirectory: true)
        let stagingURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(appName)-staging-\(UUID().uuidString).app", isDirectory: true)

        try? fileManager.removeItem(at: stagingURL)
        try runProcess("/usr/bin/ditto", [sourceURL.path, stagingURL.path])

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try? fileManager.trashItem(at: destinationURL, resultingItemURL: nil)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
        }

        do {
            try runProcess("/usr/bin/ditto", [stagingURL.path, destinationURL.path])
            try? runProcess("/usr/bin/xattr", ["-cr", destinationURL.path])
            try? fileManager.removeItem(at: stagingURL)
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    func relaunchInstalledApp(at appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if error == nil {
                Task { @MainActor in
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func bundleVersion(at url: URL) -> String? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let bundle = Bundle(url: url) else { return nil }
        return (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runProcess(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown process error."
            throw NSError(
                domain: "AppInstaller",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
    }
}
