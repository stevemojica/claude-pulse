// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ClaudePulse",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClaudePulseCore",
            path: "Sources/ClaudePulseCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "ClaudePulse",
            dependencies: ["ClaudePulseCore"],
            path: "Sources/ClaudePulse",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
            ]
        ),
        .executableTarget(
            name: "ClaudePulseCLI",
            dependencies: ["ClaudePulseCore"],
            path: "Sources/ClaudePulseCLI"
        ),
    ]
)
