import AVFoundation

/// The same conversion is exercised by the audio integration check and the microphone.
final class AudioConversion {
    private let source: AVAudioFormat
    private let target: AVAudioFormat
    private let converter: AVAudioConverter

    init(source: AVAudioFormat) throws {
        guard source.sampleRate > 0, source.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else {
            throw NSError(domain: "DiggerMap.Audio", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Микрофон не передаёт звук. Переподключи гарнитуру."])
        }
        self.source = source
        self.target = target
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16000 / source.sampleRate + 32)
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        guard let channel = converted.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
    }
}
