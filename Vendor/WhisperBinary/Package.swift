// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "WhisperBinary",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "WhisperBinary", targets: ["whisper"])],
    targets: [.binaryTarget(name: "whisper", path: "whisper.xcframework")]
)
