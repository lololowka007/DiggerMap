import Foundation

enum MarkerKind: String, Codable, CaseIterable, Identifiable {
    case entrance, note, junction, deadEnd, arrow, uTurn, stairs, danger, photo, sign
    var id: String { rawValue }
    var title: String {
        switch self {
        case .entrance: return "Вход"
        case .note: return "Заметка"
        case .junction: return "Проходы"
        case .deadEnd: return "Тупик"
        case .arrow: return "Стрелка"
        case .uTurn: return "Разворот"
        case .stairs: return "Лестница"
        case .danger: return "Опасность"
        case .photo: return "Фото"
        case .sign: return "Надпись"
        }
    }
    var symbol: String {
        switch self {
        case .entrance: return "door.left.hand.open"
        case .note: return "mappin"
        case .junction: return "arrow.triangle.branch"
        case .deadEnd: return "xmark.octagon.fill"
        case .arrow: return "arrow.up"
        case .uTurn: return "arrow.uturn.down"
        case .stairs: return "stairs"
        case .danger: return "exclamationmark.triangle.fill"
        case .photo: return "camera.fill"
        case .sign: return "text.bubble.fill"
        }
    }
}

struct Passage: Codable, Equatable {
    var angle: Double
    var elevation: Int = 0
    var label: String
}

struct MarkerDraft {
    var kind: MarkerKind
    var title: String
    var detail: String = ""
    var passages: [Passage] = []
}

struct RouteMarker: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var x: Double
    var y: Double
    var level: Int
    var heading: Double
    var kind: MarkerKind
    var title: String
    var detail: String
    var passages: [Passage] = []
    var photos: [String] = []
}
