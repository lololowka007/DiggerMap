import Foundation

/// Audio is mono Float32 at 16 kHz. Keep leading audio so the first word isn't cut off.
struct UtteranceSegmenter {
    private var lead: [Float] = []
    private var utterance: [Float] = []
    private var quietSamples = 0
    private var voicedSamples = 0
    private var noise: Float = 0.001
    private(set) var isSpeaking = false

    mutating func consume(_ samples: [Float]) -> (level: Float, phrase: [Float]?) {
        guard !samples.isEmpty else { return (0, nil) }
        let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count))
        let threshold = max(0.003, min(0.018, noise * 2.8))
        let voiced = rms > threshold
        if !isSpeaking {
            if voiced {
                isSpeaking = true
                utterance = lead
                quietSamples = 0
                voicedSamples = 0
            } else {
                noise = noise * 0.98 + min(rms, 0.006) * 0.02
                lead.append(contentsOf: samples)
                if lead.count > 4800 { lead.removeFirst(lead.count - 4800) }
                return (min(1, rms * 25), nil)
            }
        }
        utterance.append(contentsOf: samples)
        if voiced { voicedSamples += samples.count; quietSamples = 0 }
        else { quietSamples += samples.count }
        if quietSamples >= 14400 || utterance.count >= 192000 {
            return (min(1, rms * 25), finish())
        }
        return (min(1, rms * 25), nil)
    }

    mutating func finish() -> [Float]? {
        let result = voicedSamples >= 3200 ? utterance : nil
        utterance = []
        lead = []
        quietSamples = 0
        voicedSamples = 0
        isSpeaking = false
        return result
    }
}
