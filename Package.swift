// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClaudeCodeMonitor",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeCodeMonitor",
            path: "Sources/ClaudeCodeMonitor",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "ClaudeCodeMonitorTests",
            dependencies: ["ClaudeCodeMonitor"],
            path: "Tests/ClaudeCodeMonitorTests"
        )
    ]
)
