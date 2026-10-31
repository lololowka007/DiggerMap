import Foundation
import whisper

/// A single actor owns the C context; audio capture never waits for inference.
actor OfflineRecognizer {
    private let context: OpaquePointer

    private init(path: String) throws {
        var options = whisper_context_default_params()
        options.use_gpu = false
        guard let loaded = path.withCString({ whisper_init_from_file_with_params($0, options) }) else {
            throw NSError(domain: "DiggerMap.Voice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Не удалось загрузить встроенную модель речи."])
        }
        context = loaded
    }

    static func load(path: String) async throws -> OfflineRecognizer {
        try OfflineRecognizer(path: path)
    }

    deinit { whisper_free(context) }

    func transcribe(_ audio: [Float]) throws -> String {
        guard !audio.isEmpty else { return "" }
        var options = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        options.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount - 2)))
        options.translate = false
        options.no_context = true
        options.no_timestamps = true
        options.single_segment = true
        options.print_realtime = false
        options.print_progress = false
        options.print_timestamps = false
        options.print_special = false
        options.max_tokens = 96
        let status = "ru".withCString { language in
            options.language = language
            return audio.withUnsafeBufferPointer { samples in
                whisper_full(context, options, samples.baseAddress, Int32(samples.count))
            }
        }
        guard status == 0 else {
            throw NSError(domain: "DiggerMap.Voice", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Распознавание речи завершилось ошибкой \(status)."])
        }
        return (0..<whisper_full_n_segments(context)).map {
            String(cString: whisper_full_get_segment_text(context, $0))
        }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
