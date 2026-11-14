// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenshotEditing",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ScreenshotEditing", targets: ["ScreenshotEditing"])],
    targets: [.target(name: "ScreenshotEditing")]
)
