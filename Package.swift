// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClipboardMgr",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipboardMgr",
            path: "Sources/ClipboardMgr"
        )
    ]
)
