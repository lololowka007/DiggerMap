import Foundation
import AVFoundation
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
            verbose: true, logLevel: .debug, prewarm: false, load: true, download: false)
        let kit = try await WhisperKit(config)
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[2]),
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let conversion = try AudioConversion(source: file.processingFormat)
        var segmenter = UtteranceSegmenter()
        var phrases: [[Float]] = []
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2048)!
            try file.read(into: buffer)
            if let phrase = segmenter.consume(try conversion.convert(buffer)).phrase { phrases.append(phrase) }
        }
        if let phrase = segmenter.finish() { phrases.append(phrase) }
        precondition(phrases.count == 1, "Microphone processing must detect exactly one phrase")
        let audio = phrases[0]
        let rms = sqrt(audio.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(audio.count, 1)))
        print("AUDIO: \(audio.count) samples, RMS \(rms)")
        precondition(audio.count > 16000 && rms > 0.005, "Test fixture must contain audible speech")
        let results: [TranscriptionResult] = try await kit.transcribe(
            audioArray: audio,
            decodeOptions: DecodingOptions(verbose: true, language: "ru", temperatureFallbackCount: 0,
                sampleLength: 96, usePrefillCache: false, skipSpecialTokens: true, withoutTimestamps: true,
                firstTokenLogProbThreshold: nil, noSpeechThreshold: nil))
        for result in results {
            print("DECODE: loops=\(result.timings.totalDecodingLoops), segments=\(result.segments.count), seconds=\(result.timings.inputAudioSeconds)")
        }
        let phrase = results.map(\.text).joined(separator: " ")
        print("AUDIO → TEXT: \(phrase)")
        try phrase.write(toFile: CommandLine.arguments[3], atomically: true, encoding: .utf8)
    }
}
