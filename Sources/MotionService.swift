import Combine
import CoreMotion

final class MotionService: ObservableObject {
    @Published var relativeAltitude: Double?
    var onDistance: ((Double) -> Void)?
    var onEvent: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    var stepLength = 0.75
    private let altimeter = CMAltimeter()
    private let pedometer = CMPedometer()
    private var lastSteps = 0
    private var lastDistance: Double = 0
    private var walking = false

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
        pedometer.stopUpdates()
    }
}
