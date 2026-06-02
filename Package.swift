// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FocusTracker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FocusTracker",
            path: "Sources/FocusTracker",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
