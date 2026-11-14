// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LightRecorder",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "LightRecorder", targets: ["LightRecorder"])],
    dependencies: [.package(path: "../screenshot-editor-mac"), .package(path: "../recent-files-mac")],
    targets: [
        .target(name: "RecorderCore"),
        .executableTarget(name: "LightRecorder", dependencies: [
            "RecorderCore",
            .product(name: "ScreenshotEditing", package: "screenshot-editor-mac"),
            .product(name: "ScreenshotWatching", package: "recent-files-mac")
        ]),
        .testTarget(name: "RecorderCoreTests", dependencies: ["RecorderCore", .product(name: "ScreenshotEditing", package: "screenshot-editor-mac")])
    ]
)
