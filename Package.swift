// swift-tools-version: 6.0
import Foundation
import PackageDescription

var testSwiftSettings: [SwiftSetting] = []

// When running locally under CommandLineTools, provide the plugin-path for Swift Testing macros.
// In CI or under Xcode.app, Xcode SPM automatically supplies the matching plugin.
if ProcessInfo.processInfo.environment["CI"] == nil {
    let cltTestingPluginPath = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
    if FileManager.default.fileExists(atPath: cltTestingPluginPath) {
        testSwiftSettings.append(.unsafeFlags(["-plugin-path", cltTestingPluginPath]))
    }
}

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
            ],
            swiftSettings: testSwiftSettings
        )
    ]
)
