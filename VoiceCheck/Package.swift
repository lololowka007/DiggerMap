// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "VoiceCheck",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "0.9.4")],
    targets: [.executableTarget(name: "VoiceCheck",
        dependencies: [.product(name: "WhisperKit", package: "whisperkit")], path: "Sources")]
)
