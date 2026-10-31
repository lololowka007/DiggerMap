import SwiftUI

struct ContentView: View {
    @StateObject private var speech = SpeechService()
    @StateObject private var motion = MotionService()
    @State private var route = RouteState()
    @State private var commandText = ""
    @State private var message = ""
    @State private var showReset = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("DiggerMap").font(.title2.bold())
                Spacer()
                Text("Этаж \(route.level) · \(route.totalSteps) шагов")
                    .font(.subheadline)
            }
            .padding(.horizontal)

            RouteCanvas(route: route)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

            TextField("Например: прямо 12 шагов", text: $commandText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .onChange(of: speech.transcript) { _, value in commandText = value }

            HStack {
                Button(speech.isListening ? "Остановить" : "Говорить") { speech.toggle() }
                    .buttonStyle(.borderedProminent)
                Button("Добавить") { applyCommand() }
                    .buttonStyle(.bordered)
                Button("Сброс") { showReset = true }
                    .buttonStyle(.bordered)
            }
            .alert("Удалить текущую карту?", isPresented: $showReset) {
                Button("Удалить", role: .destructive) { route = RouteState(); save() }
                Button("Отмена", role: .cancel) {}
            }

            Text(message.isEmpty ? speech.status : message)
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 20)
            if let altitude = motion.relativeAltitude {
                Text("Барометр от запуска: \(altitude, specifier: "%.1f") м · условное направление: \(Int(route.heading))°")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("Карта приблизительная. Сверяй путь с реальной обстановкой.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical)
        .onAppear { load(); motion.start() }
        .onDisappear { speech.stop(); motion.stop() }
    }

    private func applyCommand() {
        let input = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        if route.apply(CommandParser.parse(input), source: input) {
            save()
            commandText = ""
            speech.transcript = ""
            message = "Добавлено: \(input)"
        } else {
            message = "Команда не распознана. Пример: прямо 12 шагов."
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(route) { UserDefaults.standard.set(data, forKey: "route-v1") }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: "route-v1"),
           let saved = try? JSONDecoder().decode(RouteState.self, from: data) { route = saved }
    }
}

struct RouteCanvas: View {
    let route: RouteState

    var body: some View {
        Canvas { context, size in
            let visible = route.points.filter { $0.level == route.level }
            guard !visible.isEmpty else { return }
            let minX = visible.map(\.x).min() ?? 0
            let maxX = visible.map(\.x).max() ?? 0
            let minY = visible.map(\.y).min() ?? 0
            let maxY = visible.map(\.y).max() ?? 0
            let extent = max(max(maxX - minX, maxY - minY), 10)
            let scale = min(size.width, size.height) * 0.8 / extent
            func position(_ point: RoutePoint) -> CGPoint {
                CGPoint(x: size.width / 2 + (point.x - (minX + maxX) / 2) * scale,
                        y: size.height / 2 - (point.y - (minY + maxY) / 2) * scale)
            }
            var path = Path()
            for index in 0..<route.points.count {
                let point = route.points[index]
                guard point.level == route.level else { continue }
                if index > 0 && route.points[index - 1].level == route.level {
                    path.move(to: position(route.points[index - 1]))
                    path.addLine(to: position(point))
                }
            }
            context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            for point in visible {
                let center = position(point)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(.orange))
                if let label = point.label {
                    context.draw(Text(label).font(.caption).foregroundColor(.primary), at: CGPoint(x: center.x, y: center.y - 16))
                }
            }
        }
        .frame(minHeight: 350)
    }
}
