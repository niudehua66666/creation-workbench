// swift-tools-version: 5.9
import PackageDescription

// Only the libraries used by Creation Workbench are distributed here.
let package = Package(
    name: "RecentFiles",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ScreenshotWatching", targets: ["ScreenshotWatching"])],
    targets: [
        .target(name: "RecentFilesCore"),
        .target(name: "ScreenshotWatching", dependencies: ["RecentFilesCore"])
    ]
)
