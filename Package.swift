// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexUsage", targets: ["CodexUsageApp"])
    ],
    targets: [
        .executableTarget(
            name: "CodexUsageApp",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
