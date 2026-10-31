import SwiftUI

private enum MapStyle {
    static let background = Color(red: 0.035, green: 0.075, blue: 0.105)
    static let panel = Color(red: 0.075, green: 0.13, blue: 0.16)
    static let mint = Color(red: 0.40, green: 0.94, blue: 0.72)
    static let muted = Color(red: 0.58, green: 0.70, blue: 0.72)
}

struct ContentView: View {
    @StateObject private var speech = SpeechService()
    @StateObject private var motion = MotionService()
    @State private var route = RouteState()
    @State private var mapLevel = 0
    @State private var message = "Скажи «прошёл четыре метра» или «на 12 градусов налево»."
    @State private var showResetFirst = false
    @State private var showResetFinal = false
    @State private var showMarker = false
    @State private var showCorrection = false
    @State private var markerName = ""
    @State private var correction = ""

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    MapPanel(route: route, level: mapLevel)
                        .frame(height: max(390, geometry.size.height * 0.53))
                        .clipShape(RoundedRectangle(cornerRadius: 25))
                        .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.10)))
                    stats
                    commandStatus
                    controls
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .background(MapStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            voiceBar
        }
        .confirmationDialog("Сбросить текущую карту?", isPresented: $showResetFirst) {
            Button("Продолжить сброс", role: .destructive) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showResetFinal = true }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все точки и маршрут этой карты будут удалены.")
        }
        .alert("Точно удалить всю карту?", isPresented: $showResetFinal) {
            Button("Да, удалить карту", role: .destructive) {
                speech.stop()
                route = RouteState()
                mapLevel = 0
                save()
                message = "Карта сброшена."
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это второе подтверждение. Действие нельзя отменить.")
        }
        .onAppear {
            load()
            mapLevel = route.level
            motion.start()
            speech.onCommand = { phrase in apply(phrase) }
        }
        .onChange(of: route.level) { _, value in mapLevel = value }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DIGGERMAP")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(3.5)
                    .foregroundStyle(MapStyle.mint)
                Text("Карта маршрута")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "location.north.line.fill")
                .font(.title2)
                .foregroundStyle(MapStyle.mint)
                .frame(width: 48, height: 48)
                .background(MapStyle.panel, in: RoundedRectangle(cornerRadius: 15))
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            statCard("ПРОЙДЕНО", value: String(format: "%.1f м", route.totalMeters), symbol: "figure.walk")
            statCard("НАПРАВЛЕНИЕ", value: "\(Int(route.heading.rounded()))°", symbol: "location.north.fill")
            statCard("УРОВЕНЬ", value: "\(route.level)", symbol: "square.3.layers.3d")
        }
    }

    private func statCard(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).font(.caption).foregroundStyle(MapStyle.mint)
            Text(value).font(.system(size: 19, weight: .bold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(MapStyle.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MapStyle.panel, in: RoundedRectangle(cornerRadius: 17))
    }

    private var commandStatus: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(speech.isListening ? MapStyle.mint : MapStyle.muted).frame(width: 7, height: 7)
                Text(speech.status).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            Text(speech.isListening ? "Микрофон: \(speech.inputName)" : "Подключи гарнитуру и начни запись перед тем, как убрать телефон.")
                .font(.caption).foregroundStyle(MapStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !speech.transcript.isEmpty {
                Text("Слышу: \(speech.transcript)").font(.callout).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(message).font(.callout).foregroundStyle(MapStyle.mint)
                .fixedSize(horizontal: false, vertical: true)
            if let altitude = motion.relativeAltitude {
                Text(String(format: "Барометр: %+.1f м от запуска", altitude))
                    .font(.caption).foregroundStyle(MapStyle.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MapStyle.panel, in: RoundedRectangle(cornerRadius: 19))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { showMarker = true } label: {
                Label("Метка", systemImage: "mappin.and.ellipse")
            }
            .alert("Добавить точку", isPresented: $showMarker) {
                TextField("Название точки", text: $markerName)
                Button("Добавить") {
                    route.addMarker(markerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Точка" : markerName)
                    save()
                    markerName = ""
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Точка появится у текущей позиции.")
            }
            Button { showCorrection = true } label: {
                Label("Исправить", systemImage: "pencil")
            }
            .alert("Исправить команду", isPresented: $showCorrection) {
                TextField("Например: прошёл 4 метра", text: $correction)
                Button("Применить") { apply(correction); correction = "" }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Ручной ввод нужен только для исправления распознавания.")
            }
            Spacer(minLength: 4)
            Menu {
                Button("Убрать последнюю точку", systemImage: "arrow.uturn.backward") { undoLastPoint() }
                Button("Сбросить карту", systemImage: "trash", role: .destructive) { showResetFirst = true }
            } label: {
                Image(systemName: "ellipsis").font(.title3).frame(width: 34, height: 32)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .buttonStyle(.bordered)
    }

    private var voiceBar: some View {
        Button { speech.toggle() } label: {
            HStack(spacing: 13) {
                Image(systemName: speech.isListening ? "stop.fill" : "waveform")
                    .font(.title3)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(speech.isListening ? "Остановить запись" : "Начать запись")
                        .font(.headline)
                    Text(speech.isListening ? "Команды сами появляются на карте" : "Говори в микрофон гарнитуры")
                        .font(.caption)
                        .opacity(0.8)
                }
                Spacer()
                Image(systemName: speech.isListening ? "record.circle" : "arrow.up.right")
            }
            .foregroundStyle(MapStyle.background)
            .padding(.horizontal, 20)
            .frame(height: 62)
            .background(MapStyle.mint, in: RoundedRectangle(cornerRadius: 19))
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(MapStyle.background.opacity(0.97))
    }

    private func apply(_ phrase: String) {
        let commands = CommandParser.parse(phrase, stepLength: route.stepLength)
        if route.apply(commands, source: phrase) {
            save()
            message = "Добавлено: \(phrase)"
        } else {
            message = "Не понял: «\(phrase)». Скажи «прошёл 4 метра» или «налево на 12 градусов»."
        }
    }

    private func undoLastPoint() {
        guard route.points.count > 1 else { return }
        let removed = route.points.removeLast()
        if let last = route.points.last {
            if removed.level == last.level {
                route.totalMeters = max(0, route.totalMeters - hypot(removed.x - last.x, removed.y - last.y))
            }
            route.level = last.level
        }
        save()
        message = "Последняя точка удалена."
    }

    private func save() {
        if let data = try? JSONEncoder().encode(route) {
            UserDefaults.standard.set(data, forKey: "route-v2")
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: "route-v2"),
           let saved = try? JSONDecoder().decode(RouteState.self, from: data) {
            route = saved
            return
        }
        if let data = UserDefaults.standard.data(forKey: "route-v1"),
           var old = try? JSONDecoder().decode(RouteState.self, from: data) {
            for index in old.points.indices {
                old.points[index].x *= 0.75
                old.points[index].y *= 0.75
            }
            if old.points.first?.label == "Старт" { old.points[0].label = "Вход" }
            old.totalMeters = zip(old.points, old.points.dropFirst()).reduce(0) {
                $0 + ($1.0.level == $1.1.level ? hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) : 0)
            }
            route = old
            save()
        }
    }
}

private struct MapPanel: View {
    let route: RouteState
    let level: Int
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var cursor: CGPoint?
    @State private var dragOrigin: CGSize?
    @State private var zoomOrigin: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let visible = route.points.filter { $0.level == level }
            let minX = visible.map(\.x).min() ?? 0
            let maxX = visible.map(\.x).max() ?? 0
            let minY = visible.map(\.y).min() ?? 0
            let maxY = visible.map(\.y).max() ?? 0
            let centerX = (minX + maxX) / 2
            let centerY = (minY + maxY) / 2
            let extent = max(max(maxX - minX, maxY - minY), 10) + route.corridorWidth * 2
            let scale = min(geometry.size.width, geometry.size.height) * 0.76 / CGFloat(extent) * zoom
            let origin = CGPoint(x: geometry.size.width / 2 + pan.width,
                                 y: geometry.size.height / 2 + pan.height)
            Canvas { context, size in
                func position(_ point: RoutePoint) -> CGPoint {
                    CGPoint(x: origin.x + CGFloat(point.x - centerX) * scale,
                            y: origin.y - CGFloat(point.y - centerY) * scale)
                }
                let gridSpacing = max(14, scale)
                var grid = Path()
                for x in stride(from: origin.x.truncatingRemainder(dividingBy: gridSpacing),
                                through: size.width, by: gridSpacing) {
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: origin.y.truncatingRemainder(dividingBy: gridSpacing),
                                through: size.height, by: gridSpacing) {
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)

                for index in 1..<route.points.count {
                    let previous = route.points[index - 1]
                    let point = route.points[index]
                    guard previous.level == level, point.level == level else { continue }
                    let a = position(previous)
                    let b = position(point)
                    let dx = b.x - a.x
                    let dy = b.y - a.y
                    let length = hypot(dx, dy)
                    guard length > 0.1 else { continue }
                    let offset = CGFloat(route.corridorWidth / 2) * scale
                    let nx = -dy / length * offset
                    let ny = dx / length * offset
                    var fill = Path()
                    fill.move(to: CGPoint(x: a.x + nx, y: a.y + ny))
                    fill.addLine(to: CGPoint(x: b.x + nx, y: b.y + ny))
                    fill.addLine(to: CGPoint(x: b.x - nx, y: b.y - ny))
                    fill.addLine(to: CGPoint(x: a.x - nx, y: a.y - ny))
                    fill.closeSubpath()
                    context.fill(fill, with: .color(MapStyle.mint.opacity(0.10)))
                    for side: CGFloat in [-1, 1] {
                        var wall = Path()
                        wall.move(to: CGPoint(x: a.x + nx * side, y: a.y + ny * side))
                        wall.addLine(to: CGPoint(x: b.x + nx * side, y: b.y + ny * side))
                        context.stroke(wall, with: .color(MapStyle.mint.opacity(0.75)),
                                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                    var center = Path()
                    center.move(to: a)
                    center.addLine(to: b)
                    context.stroke(center, with: .color(.white.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
                for point in visible {
                    guard let label = point.label else { continue }
                    let p = position(point)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)),
                                 with: .color(MapStyle.mint))
                    context.draw(Text(label).font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white), at: CGPoint(x: p.x + 11, y: p.y - 13), anchor: .leading)
                }
                if let last = visible.last, last.id == route.points.last?.id {
                    let p = position(last)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)),
                                 with: .color(.orange))
                    context.stroke(Path(ellipseIn: CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)),
                                   with: .color(.orange.opacity(0.5)), lineWidth: 2)
                }
                if let cursor {
                    var cross = Path()
                    cross.move(to: CGPoint(x: cursor.x - 10, y: cursor.y))
                    cross.addLine(to: CGPoint(x: cursor.x + 10, y: cursor.y))
                    cross.move(to: CGPoint(x: cursor.x, y: cursor.y - 10))
                    cross.addLine(to: CGPoint(x: cursor.x, y: cursor.y + 10))
                    context.stroke(cross, with: .color(.orange), lineWidth: 2)
                }
            }
            .background(MapStyle.panel)
            .gesture(DragGesture().onChanged { value in
                if dragOrigin == nil { dragOrigin = pan }
                pan = CGSize(width: (dragOrigin?.width ?? 0) + value.translation.width,
                             height: (dragOrigin?.height ?? 0) + value.translation.height)
            }.onEnded { _ in dragOrigin = nil })
            .simultaneousGesture(MagnificationGesture().onChanged { value in
                if zoomOrigin == nil { zoomOrigin = zoom }
                zoom = min(max((zoomOrigin ?? 1) * value, 0.5), 8)
            }.onEnded { _ in zoomOrigin = nil })
            .simultaneousGesture(SpatialTapGesture().onEnded { cursor = $0.location })
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ПЛАН · УРОВЕНЬ \(level)")
                        .font(.system(size: 11, weight: .bold)).tracking(1.6)
                        .foregroundStyle(MapStyle.mint)
                    Text("Перетаскивай · увеличивай · ставь курсор")
                        .font(.caption2).foregroundStyle(MapStyle.muted)
                    if let cursor {
                        Text(String(format: "Курсор: %+.1f, %+.1f м",
                                    centerX + Double((cursor.x - origin.x) / scale),
                                    centerY - Double((cursor.y - origin.y) / scale)))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.orange)
                    }
                }
                .padding(15)
                .background(MapStyle.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 15))
                .padding(14)
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 7) {
                    mapButton("minus") { zoom = max(0.5, zoom / 1.4) }
                    mapButton("plus") { zoom = min(8, zoom * 1.4) }
                    mapButton("scope") { zoom = 1; pan = .zero; cursor = nil }
                }
                .padding(14)
            }
        }
    }

    private func mapButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(MapStyle.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 11))
        }
    }
}
