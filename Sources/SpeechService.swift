import AVFoundation
import Combine

@MainActor
final class SpeechService: ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var isStarting = false
    @Published var isProcessing = false
    @Published var status = "Готов к записи · распознавание на телефоне"
    @Published var inputName = "Микрофон iPhone"
    @Published var level: Float = 0
    var onCommand: ((String) -> Void)?
    var onEvent: ((String) -> Void)?

    private var recognizer: OfflineRecognizer?
    private var capture: VoiceCapture?
    private var pending: [[Float]] = []
    private var decodeGeneration = 0
    private var captureGeneration = 0
    private var audioFrames = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
            Task { @MainActor in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue, self.isListening {
                    self.stop()
                    self.status = "Запись прервана звонком или другим приложением. Нажми «Слушать»."
                    self.onEvent?(self.status)
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue ||
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in
                guard let self, self.isListening else { return }
                self.stop()
                self.onEvent?("Аудиоустройство изменилось. Перезапускаю микрофон.")
                self.toggle()
            }
        })
    }

    func toggle() {
        if isStarting { return }
        if isListening { stop(); return }
        isStarting = true
        Task {
            do {
                if recognizer == nil {
                    status = "Загружаю встроенную русскую модель…"
                    onEvent?(status)
                    guard let root = Bundle.main.url(forResource: "VoiceModels", withExtension: nil) else {
                        throw VoiceError.message("В IPA отсутствует папка голосовой модели.")
                    }
                    recognizer = try await OfflineRecognizer.load(path: root.appendingPathComponent("ggml-base.bin").path)
                    onEvent?("Локальная модель Whisper загружена. Интернет для речи не нужен.")
                }
                let allowed = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
                }
                guard allowed else { throw VoiceError.message("Нет доступа к микрофону. Разреши его в Настройки → DiggerMap.") }
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth])
                try session.setActive(true)
                if let external = session.availableInputs?.first(where: { $0.portType == .headsetMic || $0.portType == .bluetoothHFP }) {
                    try session.setPreferredInput(external)
                }
                inputName = session.currentRoute.inputs.first?.portName ?? "Микрофон iPhone"
                let audio = VoiceCapture()
                captureGeneration += 1
                audioFrames = 0
                let captureID = captureGeneration
                audio.onLevel = { [weak self] value in
                    Task { @MainActor in
                        guard let self, captureID == self.captureGeneration else { return }
                        self.audioFrames += 1
                        self.level = value
                    }
                }
                audio.onPhrase = { [weak self] samples in
                    Task { @MainActor in
                        guard let self else { return }
                        guard captureID == self.captureGeneration else { return }
                        self.onEvent?("Микрофон: фраза \(String(format: "%.1f", Double(samples.count) / 16000)) с → распознавание")
                        self.pending.append(samples)
                        self.processNext()
                    }
                }
                audio.onIssue = { [weak self] text in
                    Task { @MainActor in
                        guard let self, captureID == self.captureGeneration else { return }
                        self.stop(discardPending: true)
                        self.status = text
                        self.onEvent?("Микрофон: \(text)")
                    }
                }
                capture = audio
                try audio.start()
                isListening = true
                status = "Слушаю · говори и делай паузу после команды"
                onEvent?("Запись включена: \(inputName)")
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if captureID == self.captureGeneration, self.isListening, self.audioFrames == 0 {
                        self.stop(discardPending: true)
                        self.status = "Из микрофона не поступает звук. Переподключи гарнитуру и повтори."
                        self.onEvent?(self.status)
                    }
                }
            } catch {
                status = error.localizedDescription
                onEvent?("Ошибка: \(status)")
                capture?.stop()
                capture = nil
                isListening = false
            }
            isStarting = false
        }
    }

    private func processNext() {
        guard !isProcessing, !pending.isEmpty, let recognizer else { return }
        isProcessing = true
        let audio = pending.removeFirst()
        let generation = decodeGeneration
        Task {
            do {
                let recognized = try await recognizer.transcribe(audio)
                if generation == decodeGeneration {
                    let phrase = recognized
                    transcript = phrase
                    if phrase.isEmpty {
                        onEvent?("Речь не разобрана. Поднеси микрофон ближе и повтори.")
                    } else {
                        onEvent?("Услышал: «\(phrase)»")
                        onCommand?(phrase)
                    }
                }
            } catch {
                if generation == decodeGeneration { onEvent?("Ошибка распознавания: \(error.localizedDescription)") }
            }
            isProcessing = false
            processNext()
        }
    }

    func stop(discardPending: Bool = false) {
        capture?.stop(flush: !discardPending)
        capture = nil
        isListening = false
        level = 0
        status = "Запись остановлена"
        if discardPending {
            captureGeneration += 1
            pending = []
            decodeGeneration += 1
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onEvent?(status)
    }
}

private enum VoiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// The capture engine stays running while individual phrases are decoded.
private final class VoiceCapture {
    var onLevel: ((Float) -> Void)?
    var onPhrase: (([Float]) -> Void)?
    var onIssue: ((String) -> Void)?
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "app.diggermap.voice-segments")
    private var segmenter = UtteranceSegmenter()
    private var hasTap = false
    private var frameCounter = 0
    private var reportedError = false

    func start() throws {
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        let conversion = try AudioConversion(source: source)
        input.installTap(onBus: 0, bufferSize: 2048, format: source) { [weak self] buffer, _ in
            guard let self else { return }
            let samples: [Float]
            do { samples = try conversion.convert(buffer) }
            catch {
                self.queue.async {
                    if !self.reportedError {
                        self.reportedError = true
                        self.onIssue?("Не удалось прочитать звук из выбранного микрофона. Переподключи гарнитуру.")
                    }
                }
                return
            }
            self.queue.async {
                let output = self.segmenter.consume(samples)
                self.frameCounter += 1
                if self.frameCounter % 3 == 0 { self.onLevel?(output.level) }
                if let phrase = output.phrase { self.onPhrase?(phrase) }
            }
        }
        hasTap = true
        engine.prepare()
        try engine.start()
    }

    func stop(flush: Bool = true) {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        queue.async {
            let phrase = self.segmenter.finish()
            if flush, let phrase { self.onPhrase?(phrase) }
        }
    }
}
