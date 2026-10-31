import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private let accent = Color(red: 0.52, green: 0.56, blue: 0.87)

struct TabletView: View {
    @EnvironmentObject var model: TabletModel
    @State private var photo: PhotosPickerItem?
    @State private var showingImporter = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if geometry.size.width >= 950 {
                        settings.frame(width: 250)
                        Divider()
                    }
                    editor.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 8) {
                            Image(systemName: "scribble.variable").foregroundStyle(accent)
                            Text("forma").font(.system(.title2, design: .rounded).weight(.semibold))
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("Фото", systemImage: "photo.on.rectangle")
                        }
                        Button { showingImporter = true } label: { Label("Файл", systemImage: "folder") }
                        if geometry.size.width < 950 {
                            Button { showingSettings = true } label: { Label("Настройки", systemImage: "slider.horizontal.3") }
                        }
                        Menu {
                            Button("SVG · вектор", systemImage: "point.topleft.down.curvedto.point.bottomright.up") { model.export(svg: true) }
                            Button("PNG · 1536 × 1536", systemImage: "photo") { model.export(svg: false) }
                        } label: { Label("Экспорт", systemImage: "square.and.arrow.up") }
                            .disabled(model.busy || model.current.marks.isEmpty)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbarTitleDisplayMode(.inline)
        }
        .tint(accent)
        .onChange(of: model.parameters) { _, _ in model.regenerate() }
        .onChange(of: photo) { _, item in
            Task {
                do {
                    guard let data = try await item?.loadTransferable(type: Data.self) else { return }
                    model.load(data)
                } catch { model.error = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): model.load(url)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $model.showingExporter, document: model.exportDocument,
                      contentType: model.exportType, defaultFilename: model.exportName) { result in
            switch result {
            case .success: model.status = "Файл сохранён"
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { model.error = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                settings.navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { showingSettings = false } } }
            }.presentationDetents([.large])
        }
        .alert("Не получилось", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Понятно", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.selected.title).font(.title2.weight(.medium))
                    Text("Интерпретация \(model.selected.rawValue)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Предпросмотр", selection: $model.showOriginal) {
                    Text("Форма").tag(false)
                    Text("Фото").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }.padding(.horizontal, 24).padding(.vertical, 18)
            GeometryReader { geo in
                let side = max(1, min(geo.size.width - 36, geo.size.height - 12))
                ZStack {
                    Color.white
                    if model.showOriginal, let raster = model.raster {
                        Image(decorative: raster.image, scale: 1).resizable().scaledToFit()
                    } else {
                        TabletCanvas(drawing: model.current, color: model.color, paper: model.paper)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 5)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            Text(model.selected.explanation).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24).frame(minHeight: 42)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Style.allCases) { style in
                        Button {
                            model.selected = style
                            model.showOriginal = false
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                TabletCanvas(drawing: model.drawings[style] ?? Drawing(), color: model.color)
                                    .frame(width: 92, height: 92).clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .topLeading) {
                                        Text(String(format: "%02d", style.rawValue)).font(.system(size: 9, design: .monospaced)).foregroundStyle(accent).padding(5)
                                    }
                                Text(style.title).font(.system(size: 10)).lineLimit(1)
                            }
                            .frame(width: 92).padding(6)
                            .background(model.selected == style ? accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.selected == style ? accent : Color.primary.opacity(0.08)))
                        }.buttonStyle(.plain).accessibilityLabel("Стиль \(style.rawValue), \(style.title)")
                    }
                }.padding(.horizontal, 18).padding(.vertical, 8)
            }
            HStack(spacing: 8) {
                if model.busy { ProgressView().controlSize(.mini) }
                else { Circle().fill(accent).frame(width: 5, height: 5) }
                Text(model.busy ? "Обрабатываю…" : model.status).lineLimit(1)
                Spacer()
            }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 20).frame(height: 30)
        }
    }

    private var settings: some View {
        Form {
            Section("Исходник") {
                if let raster = model.raster {
                    Image(decorative: raster.image, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 100)
                }
                Button("Загрузить пингвина", systemImage: "sparkles") { model.loadSample() }
                Text("Объект на однотонном или прозрачном фоне даст самый чистый результат.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Выделение объекта") {
                Picker("Область", selection: $model.parameters.maskMode) {
                    Text("По стилю").tag(0)
                    Text("Силуэт").tag(1)
                    Text("Тёмное").tag(2)
                }.pickerStyle(.menu)
                setting("Допуск фона", value: $model.parameters.backgroundTolerance, range: 5...180)
                setting("Порог тёмного", value: $model.parameters.inkThreshold, range: 35...250)
            }
            Section("Характер") {
                setting("Шаг элементов", value: $model.parameters.spacing, range: 6...30)
                setting("Толщина линии", value: $model.parameters.stroke, range: 0.6...7)
                setting("Упрощение", value: $model.parameters.simplification, range: 0.7...9)
                Toggle("Внутренние линии", isOn: $model.parameters.detail)
                ColorPicker("Цвет", selection: $model.color, supportsOpacity: false)
                Toggle("Белый фон", isOn: $model.paper)
                Button("Сбросить настройки") { model.parameters = Parameters() }
            }
        }.font(.subheadline)
    }

    private func setting(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(1))).foregroundStyle(.secondary).monospacedDigit()
            }.font(.caption)
            Slider(value: value, in: range).accessibilityLabel(title)
        }.padding(.vertical, 3)
    }
}

struct TabletCanvas: View {
    let drawing: Drawing
    let color: Color
    var paper = true
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper ? .white : Color(white: 0.96)))
            if !paper {
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
        }.accessibilityLabel("Предпросмотр формы")
    }
}
