// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentsHub",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentsHubApp", targets: ["AgentsHub"]),
        .executable(name: "agentshub", targets: ["AgentsHubCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", "1.3.0"..<"1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentsHub",
            dependencies: ["AgentsHubCore"],
            path: "Sources/AgentsHub",
            exclude: ["Info.plist"]
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
            path: "Sources/AgentsHubCore"
        ),
        .testTarget(
            name: "AgentsHubCoreTests",
            dependencies: ["AgentsHubCore"],
            path: "Tests/AgentsHubCoreTests"
        ),
    ]
)
