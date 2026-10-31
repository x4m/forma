import SwiftUI
import UniformTypeIdentifiers

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case effects = "Эффекты", composition = "Композиция"
    var id: String { rawValue }
}

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
    @Published var mode: WorkspaceMode = .effects
    @Published var category: StyleGroup = .all
    @Published var layers: [ArtLayer] = []
    @Published var selectedLayerID: UUID?
    @Published var compositionPreview: CGImage?
    @Published var layersBusy = false
    @Published var projectName = "Новая композиция"
    private var revision = 0
    private var compositionRevision = 0
    private var pendingComposition: DispatchWorkItem?
    private var layerCache: [UUID: (LayerRecipe, Drawing)] = [:]
    private var pendingRender: DispatchWorkItem?
    private let worker = DispatchQueue(label: "forma.render", qos: .userInitiated)

    var current: Drawing { drawings[selected] ?? Drawing() }
    var renderBusy: Bool { busy || (mode == .composition && layersBusy) }
    var canExport: Bool { !renderBusy && (mode == .effects ? !current.isEmpty : layers.contains { $0.enabled }) }
    var selectedLayer: ArtLayer? { layers.first { $0.id == selectedLayerID } }
    var layerCountLabel: String {
        let n = layers.count, last = n % 10
        let word = (11...14).contains(n % 100) ? "слоёв" : (last == 1 ? "слой" : ((2...4).contains(last) ? "слоя" : "слоёв"))
        return "\(n) \(word)"
    }
    var composition: Composition {
        Composition(layers: layers.compactMap { layer in
            guard let cached = layerCache[layer.id], cached.0 == LayerRecipe(layer) else { return nil }
            return RenderedLayer(layer: layer, drawing: cached.1)
        }, background: paper ? NSColor(paperColor) : nil)
    }

    init(loadSample: Bool = true) { if loadSample { self.loadSample() } }

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
        if url.pathExtension.lowercased() == "forma" { loadProject(url); return }
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
                    self.layerCache = [:]
                    self.regenerateComposition()
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

    func selectEffect(_ style: Style) {
        if style == .xray || style == .photogram || selected == .xray || selected == .photogram {
            color = Color(nsColor: style.previewInk)
            paperColor = Color(nsColor: style.previewPaper)
            paper = true
        }
        selected = style; showOriginal = false
    }

    func addLayer(_ style: Style? = nil) {
        guard layers.count < 64 else { error = "В композиции уже 64 слоя"; return }
        let effect = style ?? selected
        let ink = style == nil ? NSColor(color) : effect.previewInk
        let layer = ArtLayer(style: effect, parameters: parameters, ink: Ink(ink))
        layers.append(layer); selectedLayerID = layer.id
        mode = .composition; showOriginal = false
    }

    func shadowPreset() {
        guard layers.count <= 62 else { error = "Недостаточно места для двух новых слоёв"; return }
        let template = mode == .composition ? selectedLayer : nil
        let topStyle = template?.style ?? selected
        let topParameters = template?.parameters ?? parameters
        let topInk = template?.ink ?? Ink(NSColor(color))
        var shadowParameters = topParameters
        shadowParameters.softness = 0
        shadowParameters.invertTones = false
        var bottom = ArtLayer(style: .shadow, parameters: shadowParameters, ink: Ink(.black))
        bottom.opacity = 0.35; bottom.blur = 6; bottom.x = 9; bottom.y = 12
        let top = ArtLayer(style: topStyle, parameters: topParameters, ink: topInk)
        layers += [bottom, top]; selectedLayerID = top.id
        mode = .composition; showOriginal = false
    }

    func duplicateLayer() {
        guard var layer = selectedLayer, layers.count < 64 else { return }
        layer.id = UUID(); layers.append(layer); selectedLayerID = layer.id
    }

    func removeLayer() {
        guard let id = selectedLayerID, let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers.remove(at: index)
        selectedLayerID = layers.isEmpty ? nil : layers[min(index, layers.count - 1)].id
    }

    func moveLayer(up: Bool) {
        guard let index = layers.firstIndex(where: { $0.id == selectedLayerID }) else { return }
        let target = index + (up ? 1 : -1)
        guard layers.indices.contains(target) else { return }
        layers.swapAt(index, target)
    }

    func layerValue<T>(_ path: WritableKeyPath<ArtLayer, T>, fallback: T) -> Binding<T> {
        Binding(get: { self.selectedLayer?[keyPath: path] ?? fallback }, set: { value in
            guard let index = self.layers.firstIndex(where: { $0.id == self.selectedLayerID }) else { return }
            self.layers[index][keyPath: path] = value
        })
    }

    func setLayerStyle(_ style: Style) {
        guard let index = layers.firstIndex(where: { $0.id == selectedLayerID }) else { return }
        layers[index].style = style
        layers[index].ink = Ink(style.previewInk)
    }

    func regenerateComposition() {
        compositionRevision += 1
        pendingComposition?.cancel()
        guard let raster, !layers.isEmpty else { compositionPreview = nil; layersBusy = false; return }
        let token = compositionRevision, requested = layers, cache = layerCache
        let background: NSColor? = paper ? NSColor(paperColor) : nil
        layersBusy = true
        let task = DispatchWorkItem { [weak self] in
            var next: [UUID: (LayerRecipe, Drawing)] = [:]
            var rendered: [RenderedLayer] = []
            for layer in requested {
                let key = LayerRecipe(layer)
                let drawing: Drawing
                if let old = cache[layer.id], old.0 == key { drawing = old.1 }
                else { drawing = Engine(raster: raster, parameters: layer.parameters).drawing(layer.style, layer.parameters) }
                next[layer.id] = (key, drawing)
                rendered.append(RenderedLayer(layer: layer, drawing: drawing))
            }
            let preview = Composition(layers: rendered, background: background).image()
            DispatchQueue.main.async {
                guard let self, self.compositionRevision == token else { return }
                self.layerCache = next; self.compositionPreview = preview; self.layersBusy = false
            }
        }
        pendingComposition = task
        worker.asyncAfter(deadline: .now() + 0.1, execute: task)
    }

    func saveProject() {
        guard let raster else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "forma") ?? UTType(exportedAs: "local.forma.project", conformingTo: .json)]
        panel.nameFieldStringValue = "\(raster.name).forma"
        do {
            let project = FormaProject(source: try SourceRecord(raster), layers: layers, style: selected,
                                       parameters: parameters, ink: Ink(NSColor(color)), paper: Ink(NSColor(paperColor)), opaque: paper)
            try project.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(project)
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                do { try data.write(to: url, options: .atomic); self?.projectName = url.deletingPathExtension().lastPathComponent; self?.status = "Проект сохранён" }
                catch { self?.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "forma") ?? .json]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] result in
            if result == .OK, let url = panel.url { self?.loadProject(url) }
        }
    }

    func loadProject(_ url: URL) {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard data.count <= 20_000_000 else { throw ImageFailure.unreadable }
            let project = try JSONDecoder().decode(FormaProject.self, from: data)
            try project.validate()
            let restored = try project.source.restore()
            revision += 1; pendingRender?.cancel()
            raster = restored; parameters = project.parameters; selected = project.style
            color = project.ink.color; paperColor = project.paper.color; paper = project.opaque
            layers = project.layers; selectedLayerID = layers.last?.id; layerCache = [:]
            projectName = url.deletingPathExtension().lastPathComponent
            mode = .composition; showOriginal = false
            regenerate(); regenerateComposition()
        } catch { self.error = "Не удалось открыть проект: \(error.localizedDescription)" }
    }

    func export(svg: Bool) {
        guard canExport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [svg ? .svg : .png]
        let suffix = mode == .composition ? "composition" : String(selected.rawValue)
        panel.nameFieldStringValue = "\(raster?.name ?? "image")-\(suffix).\(svg ? "svg" : "png")"
        panel.canCreateDirectories = true
        let drawing = current, ink = NSColor(color)
        let background: NSColor? = paper ? NSColor(paperColor) : nil
        let composite: Composition? = mode == .composition ? composition : nil
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                if svg {
                    let text = composite?.svg() ?? drawing.svg(color: ink, background: background)
                    try text.write(to: url, atomically: true, encoding: .utf8)
                } else {
                    let output = composite != nil ? composite!.png() : drawing.png(color: ink, background: background)
                    guard let data = output else { throw ImageFailure.unreadable }
                    try data.write(to: url, options: .atomic)
                }
                self?.status = "Сохранено: \(url.lastPathComponent)"
            } catch { self?.error = error.localizedDescription }
        }
    }
}
