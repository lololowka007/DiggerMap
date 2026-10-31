import SwiftUI

enum MapStyle {
    static let background = Color(red: 0.035, green: 0.075, blue: 0.105)
    static let panel = Color(red: 0.075, green: 0.13, blue: 0.16)
    static let mint = Color(red: 0.40, green: 0.94, blue: 0.72)
    static let muted = Color(red: 0.58, green: 0.70, blue: 0.72)
}

struct ContentView: View {
    @StateObject private var speech = SpeechService()
    @StateObject private var motion = MotionService()
    @StateObject private var session = MapSession()
    @State private var showJournal = false
    @State private var showResetFirst = false
    @State private var showResetFinal = false
    @State private var showMarker = false
    @State private var markerName = ""
    @State private var showText = false
    @State private var commandText = ""

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    header
                    stats
                    MapPanel(route: session.route)
                        .frame(height: max(220, geometry.size.height - 134))
                        .clipShape(RoundedRectangle(cornerRadius: 23))
                        .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.1)))
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .background(MapStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { session.connect(speech: speech, motion: motion) }
        .sheet(isPresented: $showJournal) { journalView }
        .confirmationDialog("Сбросить карту?", isPresented: $showResetFirst) {
            Button("Продолжить сброс", role: .destructive) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showResetFinal = true }
            }
        } message: { Text("Удалятся маршрут и метки.") }
        .alert("Точно удалить всю карту?", isPresented: $showResetFinal) {
            Button("Да, удалить", role: .destructive) {
                speech.stop(discardPending: true)
                session.reset()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("DIGGERMAP").font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(3).foregroundStyle(MapStyle.mint)
                Text("Карта маршрута").font(.system(size: 25, weight: .bold, design: .rounded))
            }
            Spacer()
            Text("1.2 · 3").font(.caption.monospacedDigit()).foregroundStyle(MapStyle.muted)
            Menu {
                Button("Ввести команду текстом", systemImage: "keyboard") { showText = true }
                Button("Сбросить карту", systemImage: "trash", role: .destructive) { showResetFirst = true }
            } label: { Image(systemName: "ellipsis.circle").font(.title2).foregroundStyle(MapStyle.mint) }
            .alert("Команда для карты", isPresented: $showText) {
                TextField("Например: налево сто метров", text: $commandText)
                Button("Применить") {
                    session.log("Текст: «\(commandText)»")
                    session.apply(commandText)
                    commandText = ""
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            stat("ПРОЙДЕНО", String(format: "%.1f м", session.route.totalMeters))
            stat("НАПРАВЛЕНИЕ", "\(Int(session.route.heading.rounded()))°")
            stat("УРОВЕНЬ", "\(session.route.level)")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(MapStyle.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(MapStyle.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        VStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Circle().fill(speech.isListening ? MapStyle.mint : .orange).frame(width: 7, height: 7)
                    Text(speech.isProcessing ? "Распознаю фразу…" : speech.status)
                        .font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill").foregroundStyle(MapStyle.mint)
                    ProgressView(value: Double(speech.level)).tint(MapStyle.mint)
                    Text(speech.inputName).font(.system(size: 10)).foregroundStyle(MapStyle.muted).lineLimit(1)
                }
                Text(speech.transcript.isEmpty ? "Услышал: —" : "Услышал: «\(speech.transcript)»")
                    .font(.caption).foregroundStyle(MapStyle.muted).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(session.lastAction)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(MapStyle.mint).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12).background(MapStyle.panel, in: RoundedRectangle(cornerRadius: 17))
            HStack(spacing: 14) {
                Button { showJournal = true } label: { Label("Журнал", systemImage: "list.bullet.rectangle") }
                Button { showMarker = true } label: { Label("Метка", systemImage: "mappin.and.ellipse") }
                    .alert("Добавить метку", isPresented: $showMarker) {
                        TextField("Название", text: $markerName)
                        Button("Добавить") { session.addMarker(markerName); markerName = "" }
                        Button("Отмена", role: .cancel) {}
                    }
                Spacer(minLength: 0)
                if session.walking {
                    Button { session.setWalking(false); session.log("Ходьба остановлена кнопкой") } label: {
                        Label("Стоп", systemImage: "figure.stand")
                    }.foregroundStyle(.orange)
                }
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .frame(minHeight: 30)
            Button {
                if speech.isListening { session.setWalking(false) }
                speech.toggle()
            } label: {
                HStack(spacing: 12) {
                    if speech.isStarting { ProgressView().tint(MapStyle.background) }
                    else { Image(systemName: speech.isListening ? "stop.fill" : "waveform").font(.title3) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(speech.isStarting ? "Подготовка модели…" : speech.isListening ? "Остановить запись" : "Слушать команды")
                            .font(.headline)
                        Text(session.walking ? "Шагомер строит маршрут" : "«Налево сто метров» · «Иду прямо»")
                            .font(.system(size: 11))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(MapStyle.background).padding(.horizontal, 16).padding(.vertical, 13)
                .frame(maxWidth: .infinity)
                .background(MapStyle.mint, in: RoundedRectangle(cornerRadius: 17))
            }
            .disabled(speech.isStarting)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
        .background(MapStyle.background)
    }

    private var journalView: some View {
        NavigationStack {
            List(session.journal.reversed()) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(entry.text).font(.callout).textSelection(.enabled)
                }.padding(.vertical, 3)
            }
            .navigationTitle("Журнал команд")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: session.journal.map { "\($0.date.formatted(date: .omitted, time: .standard)) \($0.text)" }.joined(separator: "\n")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { showJournal = false } }
            }
        }
        .preferredColorScheme(.dark)
    }
}
