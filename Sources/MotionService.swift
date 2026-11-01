import Combine
import CoreMotion

final class MotionService: ObservableObject {
    @Published var relativeAltitude: Double?
    var onDistance: ((Double) -> Void)?
    var onEvent: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    var onPause: (() -> Void)?
    var stepLength = 0.75
    private let altimeter = CMAltimeter()
    private let pedometer = CMPedometer()
    private var lastSteps = 0
    private var lastDistance: Double = 0
    private var walking = false
    private let motion = CMMotionManager()
    private var stillSince: Date?
    private var pauseSent = false

    func start() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            if let data { self?.relativeAltitude = data.relativeAltitude.doubleValue }
        }
    }

    func startWalking() {
        guard !walking else { return }
        guard CMPedometer.isStepCountingAvailable() else {
            onEvent?("Шагомер недоступен. Называй расстояния голосом.")
            return
        }
        walking = true
        pauseSent = false; stillSince = nil
        if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 0.25
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, self.walking, let a = data?.acceleration else { return }
                let dynamic = abs(a.x) + abs(a.y) + abs(a.z - 1.0)
                if dynamic < 0.035 {
                    if self.stillSince == nil { self.stillSince = Date() }
                    if !self.pauseSent, let since = self.stillSince, Date().timeIntervalSince(since) >= 8 {
                        self.pauseSent = true; self.onPause?()
                    }
                } else { self.stillSince = nil; self.pauseSent = false }
            }
        }
        lastSteps = 0
        lastDistance = 0
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self, self.walking else { return }
                if let error {
                    self.onFailure?("Шагомер: \(error.localizedDescription). Разреши «Движение и фитнес» в настройках.")
                    return
                }
                guard let data else { return }
                let steps = data.numberOfSteps.intValue
                let distance = data.distance?.doubleValue ?? Double(steps) * self.stepLength
                let delta = max(0, distance - self.lastDistance)
                self.lastSteps = steps
                self.lastDistance = distance
                if delta > 0 { self.onDistance?(delta) }
            }
        }
        onEvent?("Шагомер включён. Пройди несколько шагов: iPhone сообщает их с задержкой.")
    }

    func stopWalking() {
        walking = false
        motion.stopAccelerometerUpdates(); stillSince = nil; pauseSent = false
        pedometer.stopUpdates()
    }
}
