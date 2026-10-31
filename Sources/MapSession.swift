import Foundation
import Combine
import UIKit

struct JournalEntry: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var text: String
}

@MainActor
final class MapSession: ObservableObject {
    @Published var route = RouteState()
    @Published var journal: [JournalEntry] = []
    @Published var lastAction = "Скажи «налево сто метров» или «иду прямо»."
    @Published var walking = false
    private weak var motion: MotionService?
    private var walkingBaseline: RouteState?
    private var connected = false
    private weak var preferences: CustomizationStore?

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "route-v2"),
           let saved = try? JSONDecoder().decode(RouteState.self, from: data) { route = saved }
        else if let data = defaults.data(forKey: "route-v1"),
                var old = try? JSONDecoder().decode(RouteState.self, from: data) {
            for index in old.points.indices { old.points[index].x *= 0.75; old.points[index].y *= 0.75 }
            if !old.points.isEmpty { old.points[0].label = "Вход" }
            old.totalMeters = zip(old.points, old.points.dropFirst()).reduce(0) {
                $0 + ($1.0.level == $1.1.level ? hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) : 0)
            }
            route = old
        }
        if let data = defaults.data(forKey: "journal-v1"),
           let saved = try? JSONDecoder().decode([JournalEntry].self, from: data) { journal = saved }
        log("DiggerMap 1.3 (4) открыт")
        #if DEBUG
        if ProcessInfo.processInfo.environment["DIGGERMAP_DEMO"] == "1" {
            route = RouteState()
            _ = route.apply([.move(8), .turn(90), .move(8), .turn(90), .move(8),
                             .turn(90), .move(12), .turn(90), .move(4), .turn(90), .move(16)], source: "Демонстрация")
            _ = route.apply(CommandParser.parse("передо мной проход налево выше, направо тупик"), source: "Демонстрация")
            route.addAnnotation(MarkerDraft(kind: .photo, title: "Фото у развилки", detail: "Тестовая фотография для проверки интерфейса"))
            let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 360)).image { context in
                UIColor.darkGray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
                ("ТЕСТОВОЕ ФОТО\nМетка у развилки" as NSString).draw(
                    at: CGPoint(x: 40, y: 120),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 34), .foregroundColor: UIColor.white])
            }
            if let data = image.jpegData(compressionQuality: 0.8), let name = try? PhotoStorage.store(data) {
                route.markers[route.markers.count - 1].photos = [name]
            }
            lastAction = "Проходы и фото сохранены в метках"
            log("Проверка экрана: пересечения и фото")
        }
        #endif
    }

    func connect(speech: SpeechService, motion: MotionService, preferences: CustomizationStore) {
        guard !connected else { return }
        connected = true
        self.motion = motion
        self.preferences = preferences
        speech.onEvent = { [weak self] text in self?.log(text) }
        speech.onCommand = { [weak self] text in self?.apply(text) }
        motion.onEvent = { [weak self] text in self?.log(text) }
        motion.onFailure = { [weak self] text in
            self?.setWalking(false)
            self?.lastAction = text
            self?.log(text)
        }
        motion.onDistance = { [weak self] meters in
            guard let self, self.walking else { return }
            if self.route.apply([.move(meters)], source: "Шагомер") {
                self.lastAction = String(format: "По шагам: +%.1f м · всего %.1f м", meters, self.route.totalMeters)
                self.log(self.lastAction)
                self.save()
            }
        }
        motion.start()
    }

    func apply(_ phrase: String) {
        route.stepLength = preferences?.config.stepLength ?? route.stepLength
        let commands = CommandParser.parse(phrase, stepLength: route.stepLength, smallTurn: preferences?.config.smallTurn ?? 12)
        guard !commands.isEmpty else {
            lastAction = "Не понял. Пример: «налево сто метров»."
            log("Не понял: «\(phrase)». Нужны направление и расстояние либо «иду прямо».")
            return
        }
        let explicitDistance = commands.contains {
            switch $0 { case .move, .backtrack: return true; default: return false }
        }
        if explicitDistance, walking {
            if let baseline = walkingBaseline { route = baseline }
            setWalking(false)
            log("Участок по шагам заменён расстоянием из голосовой команды.")
        }
        var actions: [String] = []
        for command in commands {
            if case .walking(let value) = command {
                setWalking(value)
                actions.append(value ? "Иду: считаю реальные шаги" : "Ходьба остановлена")
            } else if route.apply([command], source: phrase) {
                switch command {
                case .move(let meters): actions.append(String(format: "Добавлено %.1f м", meters))
                case .backtrack(let meters): actions.append(String(format: "Назад %.2f м без разворота", meters))
                case .marker(let draft): actions.append("Метка «\(draft.title)» сохранена")
                case .turn(let degrees): actions.append(String(format: "Поворот %@ %.0f°", degrees < 0 ? "налево" : "направо", abs(degrees)))
                case .note(let name): actions.append("Метка: \(name)")
                case .level(let delta): actions.append(delta > 0 ? "Уровень выше" : "Уровень ниже")
                case .width(let meters):
                    actions.append(String(format: "Ширина %.1f м", meters))
                    preferences?.config.corridorWidth = meters
                case .walking: break
                }
            }
        }
        if walking { walkingBaseline = route }
        lastAction = actions.isEmpty ? "Значение вне допустимого диапазона." : actions.joined(separator: " · ")
        log("Карта: \(lastAction)")
        if !actions.isEmpty, preferences?.config.vibration == true { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        save()
    }

    func setWalking(_ value: Bool) {
        walking = value
        if value {
            walkingBaseline = route
            motion?.stepLength = route.stepLength
            motion?.startWalking()
        } else {
            walkingBaseline = nil
            motion?.stopWalking()
        }
    }

    @discardableResult
    func addMarker(_ name: String) -> UUID? {
        route.addMarker(name.isEmpty ? "Точка" : name)
        lastAction = "Метка: \(name.isEmpty ? "Точка" : name)"
        log(lastAction)
        if walking { walkingBaseline = route }
        save()
        return route.markers.last?.id
    }

    func updateMarker(_ id: UUID, title: String, detail: String, kind: MarkerKind) {
        guard let index = route.markers.firstIndex(where: { $0.id == id }) else { return }
        route.markers[index].title = title.isEmpty ? kind.title : title
        route.markers[index].detail = detail
        route.markers[index].kind = kind
        save()
    }

    func attachPhoto(_ data: Data, to id: UUID) throws {
        guard let index = route.markers.firstIndex(where: { $0.id == id }) else { return }
        let name = try PhotoStorage.store(data)
        route.markers[index].photos.append(name)
        save()
        log("Фото прикреплено к «\(route.markers[index].title)»")
    }

    func removePhoto(_ name: String, from id: UUID) {
        guard let index = route.markers.firstIndex(where: { $0.id == id }) else { return }
        route.markers[index].photos.removeAll { $0 == name }
        save()
    }

    func removeMarker(_ id: UUID) {
        route.markers.removeAll { $0.id == id }
        save()
    }

    func setCorridorWidth(_ value: Double) {
        route.corridorWidth = value
        save()
    }

    func reset() {
        setWalking(false)
        route = RouteState()
        route.corridorWidth = preferences?.config.corridorWidth ?? 2
        lastAction = "Карта сброшена"
        log(lastAction)
        save()
    }

    func log(_ text: String) {
        journal.append(JournalEntry(text: text))
        if journal.count > 200 { journal.removeFirst(journal.count - 200) }
        if let data = try? JSONEncoder().encode(journal) { UserDefaults.standard.set(data, forKey: "journal-v1") }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(route) { UserDefaults.standard.set(data, forKey: "route-v2") }
    }
}
