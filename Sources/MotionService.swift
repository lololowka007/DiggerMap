import Combine
import CoreMotion

final class MotionService: ObservableObject {
    @Published var relativeAltitude: Double?
    private let altimeter = CMAltimeter()

    func start() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            if let data { self?.relativeAltitude = data.relativeAltitude.doubleValue }
        }
    }

    func stop() { altimeter.stopRelativeAltitudeUpdates() }
}
