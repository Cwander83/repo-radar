// swift-tools-version: 6.0
import PackageDescription
import Foundation

var testSwiftSettings: [SwiftSetting] = []
let cltTestingPluginPath = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
if FileManager.default.fileExists(atPath: cltTestingPluginPath) {
    testSwiftSettings.append(.unsafeFlags(["-plugin-path", cltTestingPluginPath]))
}

let package = Package(
    name: "RepoRadarCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RepoRadarCore", targets: ["RepoRadarCore"])],
    targets: [
        .target(name: "RepoRadarCore", path: "Sources/RepoRadarCore"),
        .testTarget(
            name: "RepoRadarCoreTests",
            dependencies: ["RepoRadarCore"],
            path: "Tests/RepoRadarCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: testSwiftSettings
        )
    ]
)
