import SwiftUI

private enum AppPage: Identifiable {
    case journal, markers, customize, levels, command, marker(UUID)
    var id: String {
        switch self {
        case .journal: return "journal"
        case .markers: return "markers"
        case .customize: return "customize"
        case .levels: return "levels"
        case .command: return "command"
        case .marker(let id): return id.uuidString
        }
    }
}

struct ContentView: View {
    @StateObject private var speech = SpeechService()
    @StateObject private var motion = MotionService()
    @StateObject private var session = MapSession()
    @StateObject private var preferences = CustomizationStore()
    @State private var page: AppPage?
    @State private var editing = false
    @State private var selectedLevel = 0
    @State private var showResetFirst = false
    @State private var showResetFinal = false
    @State private var commandText = ""
    private var c: UIConfiguration { preferences.config }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: c.gap) {
                    header
                    if editing {
                        Text("Перетащи блок за заголовок. Кнопки S / M / L меняют размер.")
                            .font(font(12)).foregroundStyle(preferences.color(\.muted))
                    }
                    ForEach(c.blocks.filter { editing || !c.hiddenBlocks.contains($0) }) { block in
                        blockContainer(block, availableHeight: geometry.size.height)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 10)
            }.scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: c.controlsAtTop ? .top : .bottom, spacing: 0) { controls }
        .background(preferences.color(\.background).ignoresSafeArea())
        .foregroundStyle(preferences.color(\.text))
        .tint(preferences.color(\.accent))
        .preferredColorScheme(c.background == "#EFF5F3" || c.background == "#FFFFFF" ? .light : .dark)
        .onAppear {
            session.connect(speech: speech, motion: motion, preferences: preferences)
            selectedLevel = session.route.level
            #if DEBUG
            let preview = ProcessInfo.processInfo.environment["DIGGERMAP_PREVIEW"]
            if preview == "editor" { editing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if preview == "settings" { page = .customize }
                if preview == "marker", let id = session.route.markers.last?.id { page = .marker(id) }
            }
            #endif
        }
        .onChange(of: session.route.level) { _, value in selectedLevel = value }
        .onChange(of: c.corridorWidth) { _, value in session.setCorridorWidth(value) }
        .sheet(item: $page) { item in
            switch item {
            case .markers: MarkersView(session: session)
            case .marker(let id): MarkerDetailView(session: session, markerID: id)
            case .customize: CustomizationView(preferences: preferences)
            case .journal: journalView
            case .levels: levelsView
            case .command: commandView
            }
        }
        .confirmationDialog("Сбросить карту?", isPresented: $showResetFirst) {
            Button("Продолжить сброс", role: .destructive) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showResetFinal = true }
            }
        } message: { Text("Удалятся маршрут и метки с этой карты.") }
        .alert("Точно удалить всю карту?", isPresented: $showResetFinal) {
            Button("Да, удалить", role: .destructive) { speech.stop(discardPending: true); session.reset() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("DIGGERMAP").font(font(12, .black)).tracking(3).foregroundStyle(preferences.color(\.accent))
                Text(editing ? "Редактор экрана" : "Карта маршрута").font(font(24, .bold)).minimumScaleFactor(0.65).lineLimit(1)
            }
            Spacer(minLength: 8)
            if editing { Button("Готово") { withAnimation { editing = false } }.font(font(14, .semibold)) }
            else {
                Text("1.3 · 4").font(font(10)).foregroundStyle(preferences.color(\.muted))
                Menu {
                    Button("Настроить оформление", systemImage: "slider.horizontal.3") { page = .customize }
                    Button("Редактировать блоки", systemImage: "rectangle.3.group") { editing = true }
                    Button("Ввести команду", systemImage: "keyboard") { page = .command }
                    Button("Выбрать план уровня", systemImage: "square.3.layers.3d") { page = .levels }
                    Button("Сбросить карту", systemImage: "trash", role: .destructive) { showResetFirst = true }
                } label: { Image(systemName: "ellipsis.circle").font(.title2) }
            }
        }
    }

    @ViewBuilder
    private func blockContainer(_ block: DashboardBlock, availableHeight: CGFloat) -> some View {
        let content = VStack(spacing: 7) {
            if editing {
                HStack {
                    Image(systemName: "line.3.horizontal")
                    Text(block.title).font(font(13, .bold))
                    Spacer()
                    Button { preferences.shift(block, by: -1) } label: { Image(systemName: "arrow.up") }
                    Button { preferences.shift(block, by: 1) } label: { Image(systemName: "arrow.down") }
                    Button {
                        if c.hiddenBlocks.contains(block) { preferences.config.hiddenBlocks.remove(block) }
                        else { preferences.config.hiddenBlocks.insert(block) }
                    } label: { Image(systemName: c.hiddenBlocks.contains(block) ? "eye.slash" : "eye") }
                }.padding(.horizontal, 10).padding(.top, 8)
            }
            switch block {
            case .stats: stats
            case .map:
                MapPanel(route: session.route, level: selectedLevel, preferences: preferences) { page = .marker($0) }
                    .frame(height: c.mapAutoFit && !editing ? min(c.mapHeight, max(220, Double(availableHeight) - 340)) : c.mapHeight)
            case .voice: voicePanel
            }
            if editing {
                HStack {
                    Text("Размер").font(font(11))
                    ForEach(0..<3) { size in
                        Button(["S", "M", "L"][size]) { resize(block, size: size) }.buttonStyle(.bordered)
                    }
                    Spacer()
                }.padding(.horizontal, 10).padding(.bottom, 8)
            }
        }
        .background(preferences.color(\.panel))
        .clipShape(RoundedRectangle(cornerRadius: c.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: c.cornerRadius).stroke(preferences.color(\.accent).opacity(editing ? 0.8 : 0.12),
                                                                     style: StrokeStyle(lineWidth: 1, dash: editing ? [5, 3] : [])))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.7).onEnded { _ in withAnimation { editing = true } })
        if editing {
            content.draggable(block.rawValue).dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, let source = DashboardBlock(rawValue: raw) else { return false }
                withAnimation { preferences.move(source, to: block) }; return true
            }
        } else { content }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            stat("ПРОЙДЕНО", String(format: "%.1f м", session.route.totalMeters))
            stat("НАПРАВЛЕНИЕ", "\(Int(session.route.heading.rounded()))°")
            Button { page = .levels } label: { stat("ПЛАН УРОВНЯ ▾", "\(selectedLevel)") }.buttonStyle(.plain)
        }.frame(height: max(c.statsHeight, 60 * c.fontScale))
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(font(20, .bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(font(9, .bold)).foregroundStyle(preferences.color(\.muted)).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.horizontal, 12)
    }
    private var voicePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Circle().fill(speech.isListening ? preferences.color(\.accent) : preferences.color(\.position)).frame(width: 7, height: 7)
                    Text(speech.isProcessing ? "Распознаю фразу…" : speech.status).font(font(12, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill").foregroundStyle(preferences.color(\.accent))
                    ProgressView(value: Double(speech.level))
                    Text(speech.inputName).font(font(10)).foregroundStyle(preferences.color(\.muted)).lineLimit(1)
                }
                Text(speech.transcript.isEmpty ? "Услышал: —" : "Услышал: «\(speech.transcript)»")
                    .font(font(12)).foregroundStyle(preferences.color(\.muted)).fixedSize(horizontal: false, vertical: true)
                Text(session.lastAction).font(font(13, .semibold)).foregroundStyle(preferences.color(\.accent))
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }.frame(height: c.voiceHeight)
    }
    private var controls: some View {
        VStack(spacing: 8) {
            if c.recordFirst { recordButton }
            HStack {
                ForEach(c.controls) { action in
                    Button {
                        switch action { case .markers: page = .markers; case .journal: page = .journal; case .settings: page = .customize }
                    } label: {
                        Label(action.title, systemImage: action.symbol).font(font(12, .semibold))
                            .frame(maxWidth: .infinity).frame(minHeight: 30)
                    }
                }
                if session.walking {
                    Button { session.setWalking(false); session.log("Ходьба остановлена кнопкой") } label: {
                        Image(systemName: "figure.stand").foregroundStyle(preferences.color(\.position))
                    }
                }
            }.foregroundStyle(preferences.color(\.text))
            if !c.recordFirst { recordButton }
        }
        .padding(.horizontal, 16).padding(.vertical, 7).background(preferences.color(\.background))
    }
    private var recordButton: some View {
        Button {
            if speech.isListening { session.setWalking(false) }
            speech.toggle()
        } label: {
            HStack(spacing: 12) {
                if speech.isStarting { ProgressView().tint(preferences.color(\.background)) }
                else { Image(systemName: speech.isListening ? "stop.fill" : "waveform").font(.title3) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(speech.isStarting ? "Подготовка…" : speech.isListening ? "Остановить запись" : "Слушать команды").font(font(17, .bold))
                    if !c.compactRecord {
                        Text(session.walking ? "Шагомер строит маршрут" : "«Развернись назад» · «Здесь тупик»").font(font(10))
                    }
                }
                if !c.compactRecord { Spacer(minLength: 0) }
            }.foregroundStyle(preferences.color(\.background)).padding(.horizontal, 15)
                .frame(maxWidth: c.compactRecord ? nil : .infinity).frame(minHeight: max(c.buttonHeight, 45 * c.fontScale))
                .background(preferences.color(\.accent), in: RoundedRectangle(cornerRadius: c.cornerRadius))
        }.disabled(speech.isStarting)
            .frame(maxWidth: .infinity, alignment: c.recordAlignment == "Слева" ? .leading : c.recordAlignment == "Справа" ? .trailing : .center)
    }
    private var journalView: some View {
        NavigationStack {
            List(session.journal.reversed()) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(entry.text).font(.callout).textSelection(.enabled)
                }.padding(.vertical, 3)
            }.navigationTitle("Журнал команд").toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: session.journal.map { "\($0.date.formatted(date: .omitted, time: .standard)) \($0.text)" }.joined(separator: "\n")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { page = nil } }
            }
        }
    }
    private var levelsView: some View {
        NavigationStack {
            List {
                Section {
                    Text("0 — уровень входа. Команды «поднялся на этаж» и «спустился на этаж» меняют твоё положение. «Проход выше» только сохраняет наблюдение. Выбор плана здесь не перемещает тебя.")
                        .font(.callout)
                }
                Section("Сохранённые планы") {
                    ForEach(Array(Set(session.route.points.map(\.level) + session.route.markers.map(\.level))).sorted(), id: \.self) { value in
                        Button {
                            selectedLevel = value; page = nil
                        } label: {
                            HStack {
                                Text(value == 0 ? "0 · Уровень входа" : "Уровень \(value)")
                                Spacer()
                                if value == session.route.level { Text("Вы здесь").font(.caption) }
                                if value == selectedLevel { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }.navigationTitle("Планы уровней").toolbar { Button("Готово") { page = nil } }
        }
    }
    private var commandView: some View {
        NavigationStack {
            Form {
                TextField("Команда или описание", text: $commandText, axis: .vertical)
                Button("Применить") {
                    session.log("Текст: «\(commandText)»"); session.apply(commandText); commandText = ""; page = nil
                }
                Text("Примеры: «разворачиваюсь назад», «назад два шага», «слева проход выше, справа тупик», «надпись выход».")
                    .font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Команда текстом").toolbar { Button("Закрыть") { page = nil } }
        }
    }
    private func resize(_ block: DashboardBlock, size: Int) {
        switch block {
        case .stats: preferences.config.statsHeight = [55, 75, 100][size]
        case .map: preferences.config.mapAutoFit = false; preferences.config.mapHeight = [260, 400, 600][size]
        case .voice: preferences.config.voiceHeight = [130, 190, 260][size]
        }
    }
    private func font(_ size: Double, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * c.fontScale, weight: c.boldText && weight == .regular ? .bold : weight, design: preferences.fontDesign)
    }
}
