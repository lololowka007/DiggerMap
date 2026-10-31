import Foundation
import CoreML
import WhisperKit

@main
struct VoiceCheck {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let config = WhisperKitConfig(
            modelFolder: root.appendingPathComponent("openai_whisper-base").path,
            tokenizerFolder: root.appendingPathComponent("Tokenizers"),
            computeOptions: ModelComputeOptions(melCompute: .cpuOnly, audioEncoderCompute: .cpuOnly, textDecoderCompute: .cpuOnly),
            verbose: false, prewarm: false, load: true, download: false)
        let kit = try await WhisperKit(config)
        let results: [TranscriptionResult] = try await kit.transcribe(
            audioPath: CommandLine.arguments[2],
            decodeOptions: DecodingOptions(language: "ru", temperatureFallbackCount: 0,
                sampleLength: 96, usePrefillCache: false, skipSpecialTokens: true, withoutTimestamps: true))
        let phrase = results.map(\.text).joined(separator: " ")
        print("AUDIO → TEXT: \(phrase)")
        try phrase.write(toFile: CommandLine.arguments[3], atomically: true, encoding: .utf8)
    }
}
