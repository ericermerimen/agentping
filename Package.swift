// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentsHub",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentsHub", targets: ["AgentsHub"]),
        .executable(name: "agentshub", targets: ["AgentsHubCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentsHub",
            dependencies: ["AgentsHubCore"],
            path: "Sources/AgentsHub"
        ),
        .executableTarget(
            name: "AgentsHubCLI",
            dependencies: [
                "AgentsHubCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AgentsHubCLI"
        ),
        .target(
            name: "AgentsHubCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AgentsHubCore"
        ),
        .testTarget(
            name: "AgentsHubCoreTests",
            dependencies: ["AgentsHubCore"],
            path: "Tests/AgentsHubCoreTests"
        ),
    ]
)
