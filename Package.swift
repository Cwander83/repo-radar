// swift-tools-version: 6.0
import Foundation
import PackageDescription

let package = Package(
    name: "RepoRadarCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "RepoRadarCore",
            targets: ["RepoRadarCore"]
        )
    ],
    targets: [
        .target(
            name: "RepoRadarCore",
            path: "Sources/RepoRadarCore"
        ),
        .testTarget(
            name: "RepoRadarCoreTests",
            dependencies: ["RepoRadarCore"],
            path: "Tests/RepoRadarCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
