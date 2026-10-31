import Foundation
import AVFoundation

@main
struct VoiceCheck {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let kit = try await OfflineRecognizer.load(path: root.appendingPathComponent("ggml-base.bin").path)
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
        let phrase = try await kit.transcribe(phrases[0])
        print("AUDIO → TEXT: \(phrase)")
        try phrase.write(toFile: CommandLine.arguments[3], atomically: true, encoding: .utf8)
    }
}
