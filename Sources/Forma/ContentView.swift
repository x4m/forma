import SwiftUI
import UniformTypeIdentifiers

private let accent = Color(red: 0.52, green: 0.56, blue: 0.87)
private let panelColor = Color(nsColor: .windowBackgroundColor)

// This is the whole GUI: small views composed into a resizable three-column window.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var dropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                Group {
                    if model.mode == .effects { controls }
                    else { LayerListView() }
                }.frame(width: 242)
                Divider()
                workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                Group {
                    if model.mode == .effects { styles }
                    else { LayerInspectorView() }
                }.frame(width: 258)
            }
            Divider()
            HStack(spacing: 8) {
                Circle().fill(model.renderBusy ? Color.orange : accent).frame(width: 5, height: 5)
                Text(model.renderBusy ? "Пересчитываю изображение…" : (model.mode == .composition ? "\(model.layerCountLabel) · \(model.projectName)" : model.status))
                Spacer()
                Text("SWIFTUI / MACOS").tracking(1.6).font(.system(size: 9, design: .monospaced))
            }
            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 20).frame(height: 30)
        }
        .background(panelColor)
        .tint(accent)
        .frame(minWidth: 1020, minHeight: 720)
        .onChange(of: model.parameters) { _, _ in model.regenerate() }
        .onChange(of: model.layers) { _, _ in model.regenerateComposition() }
        .onChange(of: model.paper) { _, _ in model.regenerateComposition() }
        .onChange(of: model.paperColor) { _, _ in model.regenerateComposition() }
        .onChange(of: model.mode) { _, value in if value == .composition { model.regenerateComposition() } }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { model.load(url) }
            }
            return true
        }
        .overlay {
            if dropTarget {
                ZStack {
                    accent.opacity(0.15)
                    Text("Отпусти изображение здесь").font(.title2).padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent, style: StrokeStyle(lineWidth: 3, dash: [10])))
                .allowsHitTesting(false)
            }
        }
        .alert("Не получилось", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Понятно", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(accent.opacity(0.12)).frame(width: 34, height: 34)
                Image(systemName: "scribble.variable").font(.system(size: 22, weight: .medium)).foregroundStyle(accent)
            }
            Text("forma").font(.system(size: 27, weight: .semibold, design: .rounded)).tracking(-1.3)
            Picker("Режим", selection: $model.mode) {
                ForEach(WorkspaceMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 200).padding(.leading, 18)
            Spacer()
            Button { model.loadSample() } label: { Label("Пример", systemImage: "sparkles") }
                .buttonStyle(.borderless).padding(.trailing, 8).help("Загрузить пингвина из референса")
            Menu {
                Button("Открыть проект…") { model.openProject() }
                Button("Сохранить проект…") { model.saveProject() }
            } label: { Label("Проект", systemImage: "doc") }.menuStyle(.borderlessButton).fixedSize()
            if model.mode == .effects {
                Button { model.addLayer() } label: { Label("В слой", systemImage: "square.stack.3d.up") }
                    .disabled(model.busy).padding(.horizontal, 6)
            }
            Menu {
                Button("SVG") { model.export(svg: true) }
                Button("PNG · 1536 × 1536") { model.export(svg: false) }
            } label: { Label("Экспорт", systemImage: "square.and.arrow.up") }
                .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 16).padding(.vertical, 9)
                .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .disabled(!model.canExport)
        }
        .padding(.horizontal, 22).frame(height: 72)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    caption("01", "ИСХОДНИК")
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 10).fill(Color.white)
                        if let raster = model.raster {
                            Image(decorative: raster.image, scale: 1).resizable().interpolation(.high).scaledToFit().padding(8)
                        }
                        Text("⌘O / ПЕРЕТАЩИ ФАЙЛ").font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.45)).padding(9)
                    }
                    .frame(height: 144).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                    Text(model.raster?.name ?? "Изображение").font(.system(size: 11)).lineLimit(1).foregroundStyle(.secondary)
                    Button { model.openImage() } label: {
                        Label("Открыть изображение", systemImage: "plus").frame(maxWidth: .infinity)
                    }.controlSize(.large)
                    Text("PNG, JPEG, HEIC, TIFF…\nПолутона работают с любой фотографией.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                }
                Divider()
                EffectSettings(style: model.selected, parameters: $model.parameters, ink: $model.color)
                Divider()
                PaperSettings(paper: $model.paper, color: $model.paperColor)
                Button("Сбросить настройки") { model.reset() }.buttonStyle(.link).font(.system(size: 11))
            }.padding(20)
        }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.showOriginal ? "Исходное изображение" : (model.mode == .composition ? "Композиция" : model.selected.title)).font(.system(size: 21, weight: .medium))
                    Text(model.showOriginal ? "Оригинал · до преобразования" : (model.mode == .composition ? "Слои одного исходного изображения" : model.selected.category.rawValue))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Предпросмотр", selection: $model.showOriginal) {
                    Text("Форма").tag(false)
                    Text("Фото").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 132)
            }.padding(24)
            GeometryReader { geo in
                let side = max(100, min(geo.size.width - 40, geo.size.height - 20))
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.07)).blur(radius: 12).offset(y: 5)
                    if model.showOriginal, let raster = model.raster {
                        Color.white
                        Image(decorative: raster.image, scale: 1).resizable().scaledToFit()
                    } else if model.mode == .composition {
                        VectorCanvas(drawing: Drawing(), color: .black, paper: model.paper, paperColor: model.paperColor)
                        if let image = model.compositionPreview {
                            Image(decorative: image, scale: 1).resizable().scaledToFit()
                        } else {
                            VStack(spacing: 14) {
                                Image(systemName: "square.3.layers.3d").font(.system(size: 32)).foregroundStyle(accent)
                                Text("Собери эффект из слоёв").font(.headline)
                                Button("Добавить текущий эффект") { model.addLayer() }
                                Button("Тень + эффект") { model.shadowPreset() }
                            }.foregroundStyle(.secondary)
                        }
                    } else {
                        VectorCanvas(drawing: model.current, color: model.color, paper: model.paper, paperColor: model.paperColor)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(alignment: .bottomTrailing) {
                    Text(model.showOriginal ? "01" : (model.mode == .composition ? "СЛОИ" : String(format: "%02d", model.selected.rawValue)))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(accent.opacity(0.65)).padding(16)
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            VStack(spacing: 10) {
                Text(model.mode == .composition ? "Настрой выбранный слой справа. Проект .forma сохраняет картинку и все настройки." : (model.current.note ?? model.selected.explanation)).font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
                HStack(spacing: 7) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up").font(.system(size: 10))
                    Text((model.mode == .composition ? model.composition.hasRaster : model.current.raster != nil) ? "SVG содержит встроенное изображение" : "SVG — векторные контуры").font(.system(size: 10, design: .monospaced))
                }.foregroundStyle(.tertiary)
            }.frame(height: 100).padding(.horizontal, 20)
        }
        .background(Color.primary.opacity(0.025))
    }

    private var styles: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                caption("04", "ВЫБЕРИ СТИЛЬ")
                Text("\(Style.allCases.count) эффектов · 5 групп").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("Группа эффектов", selection: $model.category) {
                    ForEach(StyleGroup.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden()
            }.padding(.horizontal, 18).padding(.top, 22)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Style.gallery.filter { model.category == .all || $0.category == model.category }) { style in
                        Button {
                            model.selectEffect(style)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                VectorCanvas(drawing: model.drawings[style] ?? Drawing(), color: Color(nsColor: style.previewInk), paper: true, paperColor: Color(nsColor: style.previewPaper))
                                    .frame(height: 91).clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(alignment: .topLeading) {
                                        Text(String(format: "%02d", style.rawValue)).font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(accent).padding(6)
                                    }
                                Text(style.title).font(.system(size: 10, weight: model.selected == style ? .semibold : .regular))
                                    .lineLimit(1).padding(.horizontal, 3)
                            }
                            .padding(5).background(model.selected == style ? accent.opacity(0.12) : Color.clear,
                                                   in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(model.selected == style ? accent : Color.primary.opacity(0.07), lineWidth: 1))
                        }.buttonStyle(.plain).help("\(style.rawValue) · \(style.explanation)")
                            .accessibilityLabel("Стиль \(style.rawValue), \(style.title)")
                    }
                }.padding(.horizontal, 14).padding(.bottom, 20)
            }
        }
    }

    private func caption(_ number: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(number).foregroundStyle(accent)
            Text(title).foregroundStyle(.secondary)
        }.font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.2)
    }


}

// SwiftUI Canvas is a native immediate-mode 2D drawing surface.
// The exact same CGPaths are also written into SVG and rendered into PNG.
struct VectorCanvas: View {
    let drawing: Drawing
    let color: Color
    var paper = true
    var paperColor = Color.white

    var body: some View {
        Canvas { context, size in
            if paper {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paperColor))
            } else {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.96)))
                let cell: CGFloat = 10
                for y in stride(from: CGFloat.zero, to: size.height, by: cell) {
                    for x in stride(from: CGFloat.zero, to: size.width, by: cell) where (Int(x / cell) + Int(y / cell)) % 2 == 0 {
                        context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(Color(white: 0.9)))
                    }
                }
            }
            let scale = min(size.width, size.height) / drawing.size
            context.translateBy(x: (size.width - drawing.size * scale) / 2, y: (size.height - drawing.size * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            if let image = drawing.raster {
                context.drawLayer { layer in
                    let rect = CGRect(x: 0, y: 0, width: drawing.size, height: drawing.size)
                    layer.draw(Image(decorative: image, scale: 1), in: rect)
                    if drawing.rasterUsesInk {
                        layer.blendMode = .sourceIn
                        layer.fill(Path(rect), with: .color(color))
                    }
                }
            }
            for mark in drawing.marks {
                context.opacity = mark.opacity
                let path = Path(mark.path)
                if mark.fill { context.fill(path, with: .color(color), style: FillStyle(eoFill: true)) }
                else { context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: mark.width, lineCap: .round, lineJoin: .round)) }
            }
        }.accessibilityLabel("Предпросмотр стилизованного изображения")
    }
}
