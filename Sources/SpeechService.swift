import AVFoundation
import Combine
import Speech

final class SpeechService: ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var status = "Нажми «Начать запись» перед маршрутом."
    @Published var inputName = "Микрофон iPhone"

    var onCommand: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var commitWork: DispatchWorkItem?
    private var rotationWork: DispatchWorkItem?
    private var generation = 0
    private var hasTap = false
    private var wantsListening = false

    func toggle() {
        if wantsListening { stop(); return }
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
            status = "Локальное распознавание русского недоступно на этом iPhone."
            return
        }
        guard recognizer.isAvailable else {
            status = "Распознавание речи сейчас недоступно."
            return
        }
        wantsListening = true
        startCapture()
    }

    private func startCapture() {
        guard wantsListening, let recognizer else { return }
        generation += 1
        let currentGeneration = generation
        transcript = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth])
            try session.setActive(true)
            inputName = session.currentRoute.inputs.first?.portName ?? "Микрофон iPhone"
            let newRequest = SFSpeechAudioBufferRecognitionRequest()
            newRequest.requiresOnDeviceRecognition = true
            newRequest.shouldReportPartialResults = true
            request = newRequest
            let input = audioEngine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                newRequest.append(buffer)
            }
            hasTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            status = "Слушаю и добавляю команды автоматически"
            task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.wantsListening, self.generation == currentGeneration else { return }
                    if let result {
                        let phrase = result.bestTranscription.formattedString
                        if phrase != self.transcript {
                            self.transcript = phrase
                            self.scheduleCommit()
                        }
                        if result.isFinal {
                            self.commitAndRestart()
                            return
                        }
                    }
                    if let error {
                        self.status = "Распознавание остановилось: \(error.localizedDescription)"
                        self.stopCapture()
                        self.wantsListening = false
                    }
                }
            }
            rotationWork?.cancel()
            let rotation = DispatchWorkItem { [weak self] in self?.commitAndRestart() }
            rotationWork = rotation
            DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: rotation)
        } catch {
            stopCapture()
            wantsListening = false
            status = "Не удалось включить микрофон: \(error.localizedDescription)"
        }
    }

    private func scheduleCommit() {
        commitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commitAndRestart() }
        commitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func commitAndRestart() {
        guard wantsListening else { return }
        let phrase = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phrase.isEmpty { onCommand?(phrase) }
        stopCapture(deactivateSession: false)
        startCapture()
    }

    func stop() {
        wantsListening = false
        stopCapture()
        status = "Запись остановлена. Карта сохранена."
    }

    private func stopCapture(deactivateSession: Bool = true) {
        generation += 1
        commitWork?.cancel()
        rotationWork?.cancel()
        commitWork = nil
        rotationWork = nil
        if audioEngine.isRunning { audioEngine.stop() }
        if hasTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }
}
