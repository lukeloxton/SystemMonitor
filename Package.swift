// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SystemMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SystemMonitorCore",
            path: "SystemMonitorCore"
        ),
        .executableTarget(
            name: "SystemMonitor",
            dependencies: ["SystemMonitorCore"],
            path: "SystemMonitor"
        ),
        .executableTarget(
            name: "Benchmarks",
            dependencies: ["SystemMonitorCore"],
            path: "Benchmarks"
        )
    ]
)
