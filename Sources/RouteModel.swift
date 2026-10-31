import Foundation

struct RoutePoint: Identifiable, Codable {
    var id = UUID()
    var x: Double
    var y: Double
    var level: Int
    var label: String?
}

struct RouteState: Codable {
    var points: [RoutePoint] = [RoutePoint(x: 0, y: 0, level: 0, label: "Старт")]
    var heading: Double = 0
    var level: Int = 0
    var totalSteps: Int = 0
    var lastCommand: String = ""

    mutating func apply(_ command: RouteCommand, source: String) -> Bool {
        guard let last = points.last else { return false }
        switch command {
        case .move(let steps):
            guard steps > 0 && steps <= 500 else { return false }
            let radians = heading * .pi / 180
            points.append(RoutePoint(x: last.x + sin(radians) * Double(steps),
                                     y: last.y + cos(radians) * Double(steps), level: level))
            totalSteps += steps
        case .turn(let degrees):
            heading = (heading + degrees + 360).truncatingRemainder(dividingBy: 360)
        case .level(let delta):
            level += delta
            points.append(RoutePoint(x: last.x, y: last.y, level: level,
                                     label: delta > 0 ? "Подъём" : "Спуск"))
        case .note(let note):
            points.append(RoutePoint(x: last.x, y: last.y, level: level, label: note))
        case .unknown:
            return false
        }
        lastCommand = source
        return true
    }
}

enum RouteCommand {
    case move(Int)
    case turn(Double)
    case level(Int)
    case note(String)
    case unknown
}
