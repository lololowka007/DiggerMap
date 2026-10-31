// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "VoiceCheck",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../Vendor/WhisperBinary")],
    targets: [.executableTarget(name: "VoiceCheck",
        dependencies: [.product(name: "WhisperBinary", package: "WhisperBinary")], path: "Sources")]
)
