// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ClaudePulse",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "ClaudePulseCore",
            path: "Sources/ClaudePulseCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "ClaudePulse",
            dependencies: [
                "ClaudePulseCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
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
