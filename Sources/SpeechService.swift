import AVFoundation
import Combine
import Speech

final class SpeechService: ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var status = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isListening { stop(); return }
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            guard authorization == .authorized else {
                DispatchQueue.main.async { self?.status = "Разреши распознавание речи в настройках iPhone." }
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                DispatchQueue.main.async {
                    guard allowed else {
                        self?.status = "Разреши доступ к микрофону в настройках iPhone."
                        return
                    }
                    self?.start()
                }
            }
        }
    }

    private func start() {
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            status = "Локальная русская модель речи недоступна. Введи команду текстом."
            return
        }
        guard recognizer.isAvailable else {
            status = "Распознавание сейчас недоступно. Введи команду текстом."
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
            try AVAudioSession.sharedInstance().setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            let input = audioEngine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            status = "Слушаю…"
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let result { self?.transcript = result.bestTranscription.formattedString }
                    if let error { self?.status = "Речь: \(error.localizedDescription)"; self?.stop() }
                }
            }
        } catch {
            inputCleanup()
            status = "Не удалось включить микрофон: \(error.localizedDescription)"
        }
    }

    func stop() {
        inputCleanup()
        status = "Проверь текст и нажми «Добавить»."
    }

    private func inputCleanup() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
