import SwiftUI
import PhotosUI
import AVFoundation

enum PhotoStorage {
    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("DiggerMapPhotos", isDirectory: true)
    }
    static func url(_ name: String) -> URL { folder.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent) }
    static func store(_ data: Data) throws -> String {
        guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        let ratio = min(1, 1800 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = normalized.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        try jpeg.write(to: url(name), options: .atomic)
        return name
    }
}

struct MarkerSelection: Identifiable { var id: UUID }

struct MarkersView: View {
    @ObservedObject var session: MapSession
    @State private var selection: MarkerSelection?
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(session.route.markers.reversed().filter {
                search.isEmpty || ($0.title + $0.detail).localizedCaseInsensitiveContains(search)
            }) { marker in
                Button { selection = MarkerSelection(id: marker.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: marker.kind.symbol).font(.title3).frame(width: 30)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(marker.title).font(.headline)
                            Text(marker.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text("Уровень \(marker.level) · фото: \(marker.photos.count)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }.foregroundStyle(.primary)
            }
            .searchable(text: $search, prompt: "Название или описание")
            .navigationTitle("Метки и фото")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { if let id = session.addMarker("Новая метка") { selection = MarkerSelection(id: id) } } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
            .sheet(item: $selection) { MarkerDetailView(session: session, markerID: $0.id) }
            .overlay { if session.route.markers.isEmpty { ContentUnavailableView("Меток пока нет", systemImage: "mappin") } }
        }
    }
}

struct MarkerDetailView: View {
    @ObservedObject var session: MapSession
    let markerID: UUID
    @State private var title = ""
    @State private var detail = ""
    @State private var kind = MarkerKind.note
    @State private var photos: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var failure = ""
    @State private var loading = false
    @Environment(\.dismiss) private var dismiss
    private var marker: RouteMarker? { session.route.markers.first { $0.id == markerID } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Подпись") {
                    TextField("Название", text: $title)
                    Picker("Тип", selection: $kind) {
                        ForEach(MarkerKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    TextEditor(text: $detail).frame(minHeight: 100)
                }
                if let marker {
                    Section("Положение и проходы") {
                        Text(String(format: "Уровень %d · X %.1f м · Y %.1f м", marker.level, marker.x, marker.y))
                        ForEach(Array(marker.passages.enumerated()), id: \.offset) { _, passage in
                            Text("\(passage.label) · \(Int(passage.angle))°" + (passage.elevation == 0 ? "" : passage.elevation > 0 ? " · выше" : " · ниже"))
                        }
                    }
                    Section("Фотографии") {
                        PhotosPicker(selection: $photos, maxSelectionCount: 10, matching: .images) {
                            Label("Прикрепить из Фото", systemImage: "photo.on.rectangle")
                        }
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { requestCamera() } label: { Label("Снять фотографию", systemImage: "camera") }
                        }
                        if loading { ProgressView("Сохраняю фотографии…") }
                        ForEach(marker.photos, id: \.self) { name in
                            VStack(alignment: .leading) {
                                if let image = UIImage(contentsOfFile: PhotoStorage.url(name).path) {
                                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                HStack {
                                    ShareLink(item: PhotoStorage.url(name)) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                                    Spacer()
                                    Button("Убрать", role: .destructive) { session.removePhoto(name, from: markerID) }
                                }.font(.caption).buttonStyle(.borderless)
                            }
                        }
                    }
                    Section {
                        Button("Удалить метку", role: .destructive) { session.removeMarker(markerID); dismiss() }
                    }
                }
            }
            .navigationTitle("Метка")
            .toolbar { Button("Сохранить") { session.updateMarker(markerID, title: title, detail: detail, kind: kind); dismiss() } }
            .onAppear {
                if let marker { title = marker.title; detail = marker.detail; kind = marker.kind }
            }
            .onChange(of: photos) { _, items in
                Task {
                    loading = true
                    do {
                        for item in items {
                            if let data = try await item.loadTransferable(type: Data.self) { try session.attachPhoto(data, to: markerID) }
                        }
                    } catch { failure = error.localizedDescription }
                    loading = false
                    photos = []
                }
            }
            .fullScreenCover(isPresented: $camera) {
                CameraCapture { image in
                    camera = false
                    if let data = image?.jpegData(compressionQuality: 0.9) {
                        do { try session.attachPhoto(data, to: markerID) } catch { failure = error.localizedDescription }
                    }
                }.ignoresSafeArea()
            }
            .alert("Не удалось добавить фото", isPresented: Binding(get: { !failure.isEmpty }, set: { if !$0 { failure = "" } })) {
                Button("Понятно") { failure = "" }
            } message: { Text(failure) }
        }
    }
    private func requestCamera() {
        Task {
            if await AVCaptureDevice.requestAccess(for: .video) { camera = true }
            else { failure = "Разреши камеру в Настройки → DiggerMap." }
        }
    }
}

private struct CameraCapture: UIViewControllerRepresentable {
    var completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }
    }
}
