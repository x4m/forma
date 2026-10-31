import SwiftUI
import UniformTypeIdentifiers

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.svg, .png] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ImageFailure.unreadable }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
final class TabletModel: ObservableObject {
    @Published var parameters = Parameters()
    @Published var selected: Style = .outline
    @Published var color = Color(red: 0.52, green: 0.56, blue: 0.87)
    @Published var paper = true
    @Published var showOriginal = false
    @Published var raster: Raster?
    @Published var drawings: [Style: Drawing] = [:]
    @Published var busy = false
    @Published var error: String?
    @Published var status = "Все вычисления выполняются на iPad"
    @Published var exportDocument = ExportDocument()
    @Published var exportType: UTType = .svg
    @Published var exportName = "forma.svg"
    @Published var showingExporter = false
    private var revision = 0
    private var pending: DispatchWorkItem?
    private let worker = DispatchQueue(label: "forma.ipad.processing", qos: .userInitiated)

    var current: Drawing { drawings[selected] ?? Drawing() }

    init() { loadSample() }

    func loadSample() {
        // App playground products put their resources in the application bundle.
        let url = Bundle.main.url(forResource: "sample", withExtension: "png")
        guard let url else { error = "Не найден встроенный пример"; return }
        load(url)
    }

    func load(_ url: URL) {
        revision += 1
        let token = revision
        pending?.cancel()
        busy = true
        worker.async { [weak self] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let result = Result { try Raster.load(url) }
            DispatchQueue.main.async { self?.accept(result, token: token) }
        }
    }

    func load(_ data: Data) {
        revision += 1
        let token = revision
        pending?.cancel()
        busy = true
        worker.async { [weak self] in
            let result = Result { try Raster.load(data, name: "Фото") }
            DispatchQueue.main.async { self?.accept(result, token: token) }
        }
    }

    private func accept(_ result: Result<Raster, Error>, token: Int) {
        guard token == revision else { return }
        switch result {
        case .success(let image): raster = image; showOriginal = false; regenerate()
        case .failure(let failure): busy = false; error = failure.localizedDescription
        }
    }

    func regenerate() {
        guard let raster else { return }
        revision += 1
        let token = revision, p = parameters
        busy = true
        pending?.cancel()
        let task = DispatchWorkItem { [weak self] in
            let engine = Engine(raster: raster, parameters: p)
            var results: [Style: Drawing] = [:]
            for style in Style.allCases { results[style] = engine.drawing(style, p) }
            let hasShape = engine.shape.contains(true)
            DispatchQueue.main.async {
                guard let self, token == self.revision else { return }
                self.drawings = results
                self.busy = false
                self.status = hasShape ? "14 стилей готовы · локальная обработка" : "Объект не найден — уменьши допуск фона"
            }
        }
        pending = task
        worker.asyncAfter(deadline: .now() + 0.18, execute: task)
    }

    func export(svg: Bool) {
        guard !busy, !current.marks.isEmpty else { return }
        let drawing = current, ink = UIColor(color), background: UIColor? = paper ? .white : nil
        let name = "forma-\(selected.rawValue)"
        busy = true
        worker.async { [weak self] in
            let data = svg ? Data(drawing.svg(color: ink, background: background).utf8) : drawing.png(color: ink, background: background)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard let data else { self.error = "Не удалось подготовить файл"; return }
                self.exportDocument = ExportDocument(data: data)
                self.exportType = svg ? .svg : .png
                self.exportName = name
                self.showingExporter = true
            }
        }
    }
}
