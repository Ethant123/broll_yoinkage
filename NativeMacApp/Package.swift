// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BRollDownloaderNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "B-Roll Downloader", targets: ["BRollDownloaderNative"])
    ],
    targets: [
        .executableTarget(
            name: "BRollDownloaderNative",
            path: "Sources"
        )
    ]
)
