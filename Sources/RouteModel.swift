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
    var markers = [RouteMarker(x: 0, y: 0, level: 0, heading: 0, kind: .entrance, title: "Вход", detail: "Уровень отсчёта")]

    private enum CodingKeys: String, CodingKey {
        case points, heading, level, totalMeters, corridorWidth, stepLength, lastCommand, markers
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
        if let saved = try values.decodeIfPresent([RouteMarker].self, forKey: .markers) { markers = saved }
        else {
            markers = points.compactMap { point in
                guard let label = point.label else { return nil }
                return RouteMarker(x: point.x, y: point.y, level: point.level, heading: 0,
                                   kind: label == "Вход" || label == "Старт" ? .entrance : .note,
                                   title: label, detail: "Метка из предыдущей версии")
            }
        }
    }

    mutating func apply(_ commands: [RouteCommand], source: String) -> Bool {
        guard !commands.isEmpty else { return false }
        var changed = false
        for command in commands {
            guard let last = points.last else { return false }
            switch command {
            case .walking:
                continue
            case .backtrack(let meters):
                guard meters > 0 && meters <= 500 else { continue }
                let radians = heading * .pi / 180
                points.append(RoutePoint(x: last.x - sin(radians) * meters,
                                         y: last.y - cos(radians) * meters, level: level))
                totalMeters += meters
                addAnnotation(MarkerDraft(kind: .arrow, title: String(format: "Назад %.1f м", meters),
                                          detail: source, passages: [Passage(angle: 180, label: "Назад")]))
            case .marker(let draft):
                addAnnotation(draft)
            case .move(let meters):
                guard meters > 0 && meters <= 500 else { continue }
                let radians = heading * .pi / 180
                let next = RoutePoint(x: last.x + sin(radians) * meters,
                                      y: last.y + cos(radians) * meters, level: level)
                if source == "Шагомер", lastCommand == source, points.count > 1, last.level == level, last.label == nil {
                    points[points.count - 1] = next
                } else { points.append(next) }
                totalMeters += meters
            case .turn(let degrees):
                heading = (heading + degrees + 360).truncatingRemainder(dividingBy: 360)
                if abs(degrees) >= 179 {
                    addAnnotation(MarkerDraft(kind: .uTurn, title: "Разворот 180°", detail: source))
                }
            case .level(let delta):
                level += delta
                points.append(RoutePoint(x: last.x, y: last.y, level: level,
                                         label: delta > 0 ? "Подъём" : "Спуск"))
                addAnnotation(MarkerDraft(kind: .stairs, title: delta > 0 ? "Подъём" : "Спуск", detail: source))
            case .note(let note):
                addAnnotation(MarkerDraft(kind: .note, title: note, detail: source))
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
        addAnnotation(MarkerDraft(kind: .note, title: label))
        lastCommand = "Метка: \(label)"
    }

    mutating func addAnnotation(_ draft: MarkerDraft) {
        guard let last = points.last else { return }
        markers.append(RouteMarker(x: last.x, y: last.y, level: level, heading: heading,
                                   kind: draft.kind, title: draft.title, detail: draft.detail,
                                   passages: draft.passages))
    }
}

enum RouteCommand {
    case walking(Bool)
    case backtrack(Double)
    case marker(MarkerDraft)
    case move(Double)
    case turn(Double)
    case level(Int)
    case note(String)
    case width(Double)
}
