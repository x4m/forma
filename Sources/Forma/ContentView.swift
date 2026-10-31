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
                controls.frame(width: 242)
                Divider()
                workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                styles.frame(width: 258)
            }
            Divider()
            HStack(spacing: 8) {
                Circle().fill(model.busy ? Color.orange : accent).frame(width: 5, height: 5)
                Text(model.busy ? "Пересчитываю стили…" : model.status)
                Spacer()
                Text("SWIFTUI / MACOS").tracking(1.6).font(.system(size: 9, design: .monospaced))
            }
            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 20).frame(height: 30)
        }
        .background(panelColor)
        .tint(accent)
        .frame(minWidth: 1020, minHeight: 720)
        .onChange(of: model.parameters) { _, _ in model.regenerate() }
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
            Text("РАСТР → ФОРМА").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.7).foregroundStyle(.secondary).padding(.leading, 10)
            Spacer()
            Button { model.loadSample() } label: { Label("Пример", systemImage: "sparkles") }
                .buttonStyle(.borderless).padding(.trailing, 8).help("Загрузить пингвина из референса")
            Menu {
                Button("SVG · вектор") { model.export(svg: true) }
                Button("PNG · 1536 × 1536") { model.export(svg: false) }
            } label: { Label("Экспорт", systemImage: "square.and.arrow.up") }
                .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 16).padding(.vertical, 9)
                .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .disabled(model.busy || model.current.marks.isEmpty)
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
                VStack(alignment: .leading, spacing: 15) {
                    caption("02", model.selected.isHalftone ? "ИСТОЧНИК ПОЛУТОНОВ" : "ВЫДЕЛЕНИЕ ОБЪЕКТА")
                    Picker("Область", selection: $model.parameters.maskMode) {
                        Text(model.selected.isHalftone ? "Вся фотография" : "По стилю").tag(0)
                        Text("Силуэт").tag(1)
                        Text("Тёмные области").tag(2)
                    }.labelsHidden().frame(maxWidth: .infinity)
                    if !model.selected.isHalftone || model.parameters.maskMode != 0 {
                        setting("Допуск фона", value: $model.parameters.backgroundTolerance, range: 5...180, format: "%.0f")
                        setting("Порог тёмного", value: $model.parameters.inkThreshold, range: 35...250, format: "%.0f")
                    }
                    Text(model.selected.isHalftone ? "Светлые места дают тонкие штрихи, тёмные — широкие. Удаление фона не требуется." : "Если исчезают детали — уменьши допуск. Для сложного фона сначала удали его в редакторе.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                }
                Divider()
                VStack(alignment: .leading, spacing: 15) {
                    caption("03", "ХАРАКТЕР")
                    setting("Шаг элементов", value: $model.parameters.spacing, range: 4...30, format: "%.0f")
                    setting("Толщина линии", value: $model.parameters.stroke, range: 0.6...7, format: "%.1f")
                    if model.selected.isHalftone {
                        setting("Контраст", value: $model.parameters.toneContrast, range: 0.4...3, format: "%.1f")
                        setting("Плотность", value: $model.parameters.toneDensity, range: 0.4...2.5, format: "%.1f")
                        setting("Поворот растра", value: $model.parameters.screenAngle, range: -90...90, format: "%.0f°")
                    } else {
                        setting("Упрощение", value: $model.parameters.simplification, range: 0.7...9, format: "%.1f")
                        Toggle("Внутренние линии контура", isOn: $model.parameters.detail).font(.system(size: 11))
                    }
                    palette("Чернила", selection: $model.color, colors: [.black, accent])
                    Toggle("Фон при экспорте", isOn: $model.paper).font(.system(size: 11))
                    if model.paper {
                        palette("Бумага", selection: $model.paperColor, colors: [.white, Color(red: 1, green: 0.98, blue: 0.88), Color(red: 1, green: 0.84, blue: 0.3)])
                    }
                    Button("Сбросить настройки") { model.reset() }.buttonStyle(.link).font(.system(size: 11))
                }
            }.padding(20)
        }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.showOriginal ? "Исходное изображение" : model.selected.title).font(.system(size: 21, weight: .medium))
                    Text(model.showOriginal ? "Оригинал · до преобразования" : (model.selected.isHalftone ? "Полутоновый растр · яркость → штрих" : "Интерпретация \(model.selected.rawValue) из референса"))
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
                    } else {
                        VectorCanvas(drawing: model.current, color: model.color, paper: model.paper, paperColor: model.paperColor)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(alignment: .bottomTrailing) {
                    Text(model.showOriginal ? "01" : String(format: "%02d", model.selected.rawValue))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(accent.opacity(0.65)).padding(16)
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            VStack(spacing: 10) {
                Text(model.selected.explanation).font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
                HStack(spacing: 7) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up").font(.system(size: 10))
                    Text("SVG — масштабируется без потерь").font(.system(size: 10, design: .monospaced))
                }.foregroundStyle(.tertiary)
            }.frame(height: 100).padding(.horizontal, 20)
        }
        .background(Color.primary.opacity(0.025))
    }

    private var styles: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                caption("04", "ВЫБЕРИ СТИЛЬ")
                Text("\(Style.allCases.count) стилей · новые полутона сверху").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.top, 22)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Style.gallery) { style in
                        Button {
                            model.selected = style
                            model.showOriginal = false
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                VectorCanvas(drawing: model.drawings[style] ?? Drawing(), color: model.color, paper: true, paperColor: model.paperColor)
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

    private func palette(_ title: String, selection: Binding<Color>, colors: [Color]) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 11))
            Spacer()
            ForEach(colors.indices, id: \.self) { i in
                Button { selection.wrappedValue = colors[i] } label: {
                    Circle().fill(colors[i]).frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("\(title), образец \(i + 1)")
            }
            ColorPicker(title, selection: selection, supportsOpacity: false).labelsHidden()
        }
    }

    private func setting(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 11))
            Slider(value: value, in: range).controlSize(.small).accessibilityLabel(title)
        }
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
            for mark in drawing.marks {
                context.opacity = mark.opacity
                let path = Path(mark.path)
                if mark.fill { context.fill(path, with: .color(color), style: FillStyle(eoFill: true)) }
                else { context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: mark.width, lineCap: .round, lineJoin: .round)) }
            }
        }.accessibilityLabel("Предпросмотр стилизованного изображения")
    }
}
