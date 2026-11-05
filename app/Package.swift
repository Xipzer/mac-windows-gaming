// swift-tools-version: 6.2
import Foundation
import PackageDescription
let testsPath = "Tests/SteamBridgeAppTests"
let payloadPath = "Sources/SteamBridgeApp/Resources/payload"
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let hasTests = FileManager.default.fileExists(
    atPath: packageRoot.appendingPathComponent(testsPath).path)

let hasPayload = FileManager.default.fileExists(
    atPath: packageRoot.appendingPathComponent(payloadPath).path)
let package = Package(
    name: "SteamBridgeApp",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "SteamBridgeApp",
            path: "Sources/SteamBridgeApp",
            resources: (hasPayload ? [.copy("Resources/payload")] : []) + [
                .copy("Resources/payload.manifest"),
                .copy("Resources/valve-packages.manifest"),
                .copy("Resources/detour2.bin"),
                .copy("Resources/detour32.bin"),
                .copy("Resources/detour32-fex.bin"),
                .copy("Resources/detour64-fex.bin"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ] + (hasTests ? [
        .testTarget(
            name: "SteamBridgeAppTests",
            dependencies: ["SteamBridgeApp"],
            path: testsPath
        ),
    ] : [])
)
