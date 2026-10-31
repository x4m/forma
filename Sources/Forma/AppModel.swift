import SwiftUI
import UniformTypeIdentifiers

// The model owns state and file operations. Views only describe the interface.
@MainActor
final class AppModel: ObservableObject {
    @Published var parameters = Parameters()
    @Published var selected: Style = .candles
    @Published var color = Color.black
    @Published var paper = true
    @Published var paperColor = Color.white
    @Published var showOriginal = false
    @Published var raster: Raster?
    @Published var drawings: [Style: Drawing] = [:]
    @Published var busy = false
    @Published var error: String?
    @Published var status = "Все изображения обрабатываются на этом Mac"
    private var revision = 0
    private var pendingRender: DispatchWorkItem?
    private let worker = DispatchQueue(label: "forma.render", qos: .userInitiated)

    var current: Drawing { drawings[selected] ?? Drawing() }

    init() { loadSample() }

    func loadSample() {
        let bundled = Bundle.main.url(forResource: "sample", withExtension: "png")
        let development = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/sample.png")
        load(bundled ?? development)
    }

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Для полутонов подойдёт любая фотография; для силуэтов — объект на однотонном фоне."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.load(url)
        }
    }

    func load(_ url: URL) {
        revision += 1
        let token = revision
        busy = true
        status = "Читаю изображение…"
        worker.async { [weak self] in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let result = Result { try Raster.load(url) }
            DispatchQueue.main.async {
                guard let self, self.revision == token else { return }
                switch result {
                case .success(let raster):
                    self.raster = raster
                    self.showOriginal = false
                    self.regenerate()
                case .failure(let error):
                    self.busy = false
                    self.error = error.localizedDescription
                    self.status = "Не удалось открыть файл"
                }
            }
        }
    }

    func regenerate() {
        guard let raster else { return }
        revision += 1
        let token = revision, p = parameters
        busy = true
        pendingRender?.cancel()
        let task = DispatchWorkItem { [weak self] in
            // The expensive work never runs on the UI thread.
            let engine = Engine(raster: raster, parameters: p)
            var results: [Style: Drawing] = [:]
            for style in Style.allCases { results[style] = engine.drawing(style, p) }
            let hasShape = engine.shape.contains(true)
            DispatchQueue.main.async {
                guard let self, self.revision == token else { return }
                self.drawings = results
                self.busy = false
                self.status = hasShape ? "\(Style.allCases.count) стилей готовы · локальная обработка" : "Силуэт не найден · полутоновые стили доступны"
            }
        }
        pendingRender = task
        worker.asyncAfter(deadline: .now() + 0.14, execute: task)
    }

    func reset() { parameters = Parameters() }

    func export(svg: Bool) {
        guard !busy, !current.marks.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [svg ? .svg : .png]
        panel.nameFieldStringValue = "\(raster?.name ?? "image")-\(selected.rawValue).\(svg ? "svg" : "png")"
        panel.canCreateDirectories = true
        let drawing = current, ink = NSColor(color)
        let background: NSColor? = paper ? NSColor(paperColor) : nil
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                if svg {
                    try drawing.svg(color: ink, background: background).write(to: url, atomically: true, encoding: .utf8)
                } else {
                    guard let data = drawing.png(color: ink, background: background) else { throw ImageFailure.unreadable }
                    try data.write(to: url, options: .atomic)
                }
                self?.status = "Сохранено: \(url.lastPathComponent)"
            } catch { self?.error = error.localizedDescription }
        }
    }
}
