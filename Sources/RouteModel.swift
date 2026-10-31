import Foundation

struct RoutePoint: Identifiable, Codable {
    var id = UUID()
    var x: Double
    var y: Double
    var level: Int
    var label: String?
}

struct RouteState: Codable {
    var points: [RoutePoint] = [RoutePoint(x: 0, y: 0, level: 0, label: "Вход")]
    var heading: Double = 0
    var level: Int = 0
    var totalMeters: Double = 0
    var corridorWidth: Double = 2
    var stepLength: Double = 0.75
    var lastCommand: String = ""

    private enum CodingKeys: String, CodingKey {
        case points, heading, level, totalMeters, corridorWidth, stepLength, lastCommand
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        points = try values.decodeIfPresent([RoutePoint].self, forKey: .points) ?? points
        heading = try values.decodeIfPresent(Double.self, forKey: .heading) ?? 0
        level = try values.decodeIfPresent(Int.self, forKey: .level) ?? 0
        totalMeters = try values.decodeIfPresent(Double.self, forKey: .totalMeters) ?? 0
        corridorWidth = try values.decodeIfPresent(Double.self, forKey: .corridorWidth) ?? 2
        stepLength = try values.decodeIfPresent(Double.self, forKey: .stepLength) ?? 0.75
        lastCommand = try values.decodeIfPresent(String.self, forKey: .lastCommand) ?? ""
    }

    mutating func apply(_ commands: [RouteCommand], source: String) -> Bool {
        guard !commands.isEmpty else { return false }
        var changed = false
        for command in commands {
            guard let last = points.last else { return false }
            switch command {
            case .walking:
                continue
            case .move(let meters):
                guard meters > 0 && meters <= 500 else { continue }
                let radians = heading * .pi / 180
                points.append(RoutePoint(x: last.x + sin(radians) * meters,
                                         y: last.y + cos(radians) * meters, level: level))
                totalMeters += meters
            case .turn(let degrees):
                heading = (heading + degrees + 360).truncatingRemainder(dividingBy: 360)
            case .level(let delta):
                level += delta
                points.append(RoutePoint(x: last.x, y: last.y, level: level,
                                         label: delta > 0 ? "Подъём" : "Спуск"))
            case .note(let note):
                points.append(RoutePoint(x: last.x, y: last.y, level: level, label: note))
            case .width(let meters):
                guard meters >= 0.5 && meters <= 20 else { continue }
                corridorWidth = meters
            }
            changed = true
        }
        if changed { lastCommand = source }
        return changed
    }

    mutating func addMarker(_ label: String) {
        guard let last = points.last else { return }
        points.append(RoutePoint(x: last.x, y: last.y, level: level, label: label))
        lastCommand = "Метка: \(label)"
    }
}

enum RouteCommand {
    case walking(Bool)
    case move(Double)
    case turn(Double)
    case level(Int)
    case note(String)
    case width(Double)
}
