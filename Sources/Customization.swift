import SwiftUI
import UIKit

enum DashboardBlock: String, Codable, CaseIterable, Identifiable {
    case stats, map, voice
    var id: String { rawValue }
    var title: String { self == .stats ? "Показатели" : self == .map ? "Карта" : "Распознавание и журнал" }
}
enum ControlAction: String, Codable, CaseIterable, Identifiable {
    case markers, journal, settings
    var id: String { rawValue }
    var title: String { self == .markers ? "Метки" : self == .journal ? "Журнал" : "Вид" }
    var symbol: String { self == .markers ? "mappin.and.ellipse" : self == .journal ? "list.bullet.rectangle" : "slider.horizontal.3" }
}

struct UIConfiguration: Codable {
    var accent = "#66F0B8"
    var background = "#09131B"
    var panel = "#132129"
    var text = "#F5FAFA"
    var muted = "#95B3B8"
    var walls = "#66F0B8"
    var position = "#FFAB14"
    var route = "#DAE7E7"
    var grid = "#95B3B8"
    var fontScale = 1.0
    var labelSize = 12.0
    var wallThickness = 3.0
    var gridOpacity = 0.12
    var showGrid = true
    var showLengths = true
    var showLabels = true
    var showRoute = true
    var showPassages = true
    var mapHeight = 400.0
    var mapAutoFit = true
    var voiceHeight = 154.0
    var statsHeight = 65.0
    var gap = 12.0
    var cornerRadius = 20.0
    var buttonHeight = 60.0
    var controlsAtTop = false
    var recordFirst = false
    var compactRecord = false
    var vibration = true
    var stepLength = 0.75
    var smallTurn = 12.0
    var corridorWidth = 2.0
    var blocks: [DashboardBlock] = [.stats, .map, .voice]
    var controls: [ControlAction] = [.journal, .markers, .settings]
}

@MainActor
final class CustomizationStore: ObservableObject {
    @Published var config: UIConfiguration {
        didSet { if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: "customization-v1") } }
    }
    init() {
        if let data = UserDefaults.standard.data(forKey: "customization-v1"),
           let saved = try? JSONDecoder().decode(UIConfiguration.self, from: data) { config = saved }
        else { config = UIConfiguration() }
    }
    func color(_ key: KeyPath<UIConfiguration, String>) -> Color { Color(hex: config[keyPath: key]) }
    func move(_ block: DashboardBlock, to destination: DashboardBlock) {
        guard let from = config.blocks.firstIndex(of: block), let to = config.blocks.firstIndex(of: destination), from != to else { return }
        config.blocks.remove(at: from)
        config.blocks.insert(block, at: to)
    }
    func shift(_ block: DashboardBlock, by delta: Int) {
        guard let index = config.blocks.firstIndex(of: block) else { return }
        let destination = min(max(0, index + delta), config.blocks.count - 1)
        config.blocks.swapAt(index, destination)
    }
    func preset(_ name: String) {
        switch name {
        case "Янтарь":
            config.accent = "#FFC36B"; config.walls = "#FFC36B"; config.background = "#19130D"; config.panel = "#2B2219"
            config.text = "#FFF7EA"; config.muted = "#BDAF9C"
        case "Лёд":
            config.accent = "#73D9FF"; config.walls = "#73D9FF"; config.background = "#081522"; config.panel = "#122C40"
            config.text = "#F1FAFF"; config.muted = "#9CBCCF"
        case "Светлая":
            config.accent = "#006A55"; config.walls = "#006A55"; config.background = "#EFF5F3"; config.panel = "#FFFFFF"
            config.text = "#142922"; config.muted = "#536D63"
        default:
            let original = UIConfiguration()
            config.accent = original.accent; config.walls = original.walls; config.background = original.background
            config.panel = original.panel; config.text = original.text; config.muted = original.muted
        }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x66F0B8
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

struct CustomizationView: View {
    @ObservedObject var preferences: CustomizationStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Темы") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(["Мята", "Янтарь", "Лёд", "Светлая"], id: \.self) { name in
                            Button(name) { preferences.preset(name) }.buttonStyle(.bordered)
                        } }
                    }
                }
                Section("Цвета") {
                    colorPicker("Акцент и кнопки", \.accent)
                    colorPicker("Фон", \.background)
                    colorPicker("Окна", \.panel)
                    colorPicker("Текст", \.text)
                    colorPicker("Подписи", \.muted)
                    colorPicker("Стены", \.walls)
                    colorPicker("Моё положение", \.position)
                    colorPicker("Линия маршрута", \.route)
                    colorPicker("Сетка", \.grid)
                }
                Section("Текст и размеры") {
                    Toggle("Автоподгонка карты под экран", isOn: $preferences.config.mapAutoFit)
                    slider("Масштаб текста", $preferences.config.fontScale, 0.8...1.5)
                    slider("Подписи карты", $preferences.config.labelSize, 9...24)
                    slider("Высота карты", $preferences.config.mapHeight, 220...750)
                    slider("Высота окна речи", $preferences.config.voiceHeight, 120...350)
                    slider("Высота показателей", $preferences.config.statsHeight, 55...120)
                    slider("Высота кнопки записи", $preferences.config.buttonHeight, 48...100)
                    slider("Промежутки", $preferences.config.gap, 4...24)
                    slider("Скругление окон", $preferences.config.cornerRadius, 0...36)
                }
                Section("Карта") {
                    Toggle("Сетка", isOn: $preferences.config.showGrid)
                    Toggle("Длины участков", isOn: $preferences.config.showLengths)
                    Toggle("Названия меток", isOn: $preferences.config.showLabels)
                    Toggle("Пунктир маршрута", isOn: $preferences.config.showRoute)
                    Toggle("Стрелки проходов", isOn: $preferences.config.showPassages)
                    slider("Толщина стен", $preferences.config.wallThickness, 1...8)
                    slider("Яркость сетки", $preferences.config.gridOpacity, 0.02...0.4)
                    slider("Ширина новых коридоров, м", $preferences.config.corridorWidth, 0.5...10)
                }
                Section("Расположение") {
                    Toggle("Панель кнопок сверху", isOn: $preferences.config.controlsAtTop)
                    Toggle("Запись перед остальными кнопками", isOn: $preferences.config.recordFirst)
                    Toggle("Компактная кнопка записи", isOn: $preferences.config.compactRecord)
                    Text("Удерживай любой блок на главном экране: появятся перетаскивание, порядок и размеры.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(preferences.config.controls) { control in
                        HStack {
                            Label(control.title, systemImage: control.symbol)
                            Spacer()
                            Button { shiftControl(control, by: -1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderless)
                            Button { shiftControl(control, by: 1) } label: { Image(systemName: "arrow.down") }.buttonStyle(.borderless)
                        }
                    }
                }
                Section("Ходьба и обратная связь") {
                    slider("Длина шага для голосовых чисел, м", $preferences.config.stepLength, 0.3...1.2)
                    slider("«Чуть левее / правее», °", $preferences.config.smallTurn, 5...45)
                    Toggle("Вибрация после понятой команды", isOn: $preferences.config.vibration)
                }
                Section {
                    Button("Вернуть исходные настройки", role: .destructive) { preferences.config = UIConfiguration() }
                }
            }
            .navigationTitle("Настроить под себя")
            .toolbar { Button("Готово") { dismiss() } }
        }
    }
    private func colorPicker(_ title: String, _ key: WritableKeyPath<UIConfiguration, String>) -> some View {
        ColorPicker(title, selection: Binding(get: { Color(hex: preferences.config[keyPath: key]) },
                                              set: { preferences.config[keyPath: key] = $0.hexString }), supportsOpacity: false)
    }
    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(String(format: "%.2g", value.wrappedValue)).foregroundStyle(.secondary) }
            Slider(value: value, in: range)
        }
    }
    private func shiftControl(_ control: ControlAction, by delta: Int) {
        guard let index = preferences.config.controls.firstIndex(of: control) else { return }
        preferences.config.controls.swapAt(index, min(max(0, index + delta), preferences.config.controls.count - 1))
    }
}
