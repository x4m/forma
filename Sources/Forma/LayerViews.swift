import SwiftUI

struct LayerListView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("СЛОИ").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.horizontal, 18).padding(.top, 22)
            HStack {
                Menu {
                    ForEach(StyleGroup.allCases.filter { $0 != .all }) { group in
                        Menu(group.rawValue) {
                            ForEach(Style.allCases.filter { $0.category == group }) { style in
                                Button(style.title) { model.addLayer(style) }
                            }
                        }
                    }
                } label: { Label("Новый слой", systemImage: "plus") }
                Button { model.duplicateLayer() } label: { Image(systemName: "plus.square.on.square") }
                    .help("Дублировать выбранный слой").disabled(model.selectedLayer == nil)
            }.padding(.horizontal, 16)
            Button { model.shadowPreset() } label: {
                Label("Тень + текущий эффект", systemImage: "square.3.layers.3d").font(.system(size: 11))
            }.padding(.horizontal, 16)
            Text("Верхний слой в списке рисуется последним.").font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 18)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(Array(model.layers.reversed())) { layer in
                        HStack(spacing: 9) {
                            Button {
                                if let index = model.layers.firstIndex(where: { $0.id == layer.id }) { model.layers[index].enabled.toggle() }
                            } label: { Image(systemName: layer.enabled ? "eye" : "eye.slash").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).help(layer.enabled ? "Скрыть слой" : "Показать слой")
                            Circle().fill(layer.ink.color).frame(width: 10, height: 10).overlay(Circle().strokeBorder(.gray.opacity(0.4)))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(layer.style.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text("\(Int(layer.opacity * 100))% · \(layer.blend.title)").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12).contentShape(Rectangle())
                        .background(model.selectedLayerID == layer.id ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                        .onTapGesture { model.selectedLayerID = layer.id }
                    }
                }.padding(.horizontal, 12)
                if model.layers.isEmpty {
                    Text("Добавь эффект в слой или начни с комбинации «Тень + эффект».").font(.system(size: 12)).foregroundStyle(.secondary).padding(20)
                }
            }
            HStack {
                Button { model.moveLayer(up: true) } label: { Image(systemName: "arrow.up") }.help("Поднять слой")
                Button { model.moveLayer(up: false) } label: { Image(systemName: "arrow.down") }.help("Опустить слой")
                Spacer()
                Button { model.removeLayer() } label: { Image(systemName: "trash") }.help("Удалить выбранный слой")
            }.disabled(model.selectedLayer == nil).padding(.horizontal, 18)
            Divider()
            PaperSettings(paper: $model.paper, color: $model.paperColor).padding(.horizontal, 18)
            Button { model.saveProject() } label: { Label("Сохранить проект…", systemImage: "square.and.arrow.down") }
                .padding(.horizontal, 18).padding(.bottom, 18)
        }
    }
}

struct LayerInspectorView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            if let layer = model.selectedLayer {
                VStack(alignment: .leading, spacing: 18) {
                    Text("ВЫБРАННЫЙ СЛОЙ").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Picker("Эффект", selection: Binding(get: { layer.style }, set: { model.setLayerStyle($0) })) {
                        ForEach(Style.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                    EffectSlider(title: "Непрозрачность", value: model.layerValue(\.opacity, fallback: 1), range: 0...1, format: "%.2f")
                    Picker("Наложение", selection: model.layerValue(\.blend, fallback: .normal)) {
                        ForEach(LayerBlend.allCases) { Text($0.title).tag($0) }
                    }.font(.system(size: 11))
                    EffectSlider(title: "Размытие слоя", value: model.layerValue(\.blur, fallback: 0), range: 0...30)
                    HStack(spacing: 8) {
                        EffectSlider(title: "Сдвиг X", value: model.layerValue(\.x, fallback: 0), range: -160...160, format: "%.0f")
                        EffectSlider(title: "Сдвиг Y", value: model.layerValue(\.y, fallback: 0), range: -160...160, format: "%.0f")
                    }
                    EffectSlider(title: "Масштаб", value: model.layerValue(\.scale, fallback: 1), range: 0.2...2)
                    EffectSlider(title: "Поворот слоя", value: model.layerValue(\.rotation, fallback: 0), range: -180...180, format: "%.0f°")
                    Divider()
                    EffectSettings(style: layer.style,
                                   parameters: model.layerValue(\.parameters, fallback: Parameters()),
                                   ink: Binding(get: { layer.ink.color }, set: { color in
                        guard let index = model.layers.firstIndex(where: { $0.id == layer.id }) else { return }
                        model.layers[index].ink = Ink(NSColor(color))
                    }))
                }.padding(18)
            } else {
                Text("Выбери слой слева, чтобы настроить его эффект и положение.").font(.system(size: 12)).foregroundStyle(.secondary).padding(22)
            }
        }
    }
}

struct EffectSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var format = "%.1f"
    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 11))
            Slider(value: $value, in: range).controlSize(.small).accessibilityLabel(title)
        }
    }
}

// Shared by the effect browser and the selected-layer inspector.
struct EffectSettings: View {
    var style: Style
    @Binding var parameters: Parameters
    @Binding var ink: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(style.usesTones ? "ИСТОЧНИК И ТОНА" : "ВЫДЕЛЕНИЕ ОБЪЕКТА")
                .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            if style != .photo && style != .softFocus {
                Picker("Область", selection: $parameters.maskMode) {
                    Text(style.usesTones ? "Вся фотография" : "По стилю").tag(0)
                    Text("Силуэт").tag(1)
                    Text("Тёмные области").tag(2)
                }.labelsHidden()
            }
            if style == .ascii {
                Divider()
                Text("АЛФАВИТ").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                TextField("Буквы, цифры и знаки", text: Binding(get: { parameters.alphabet }, set: { parameters.alphabet = String($0.prefix(128)) }), axis: .vertical)
                    .font(.system(size: 12, design: .monospaced)).lineLimit(2...5).textFieldStyle(.roundedBorder)
                HStack(spacing: 7) {
                    Button("ASCII") { parameters.alphabet = ".,:;irsXA253hMHGS#9B&@" }
                    Button("0–9") { parameters.alphabet = "0123456789" }
                    Button("А–Я") { parameters.alphabet = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЫЬЭЮЯ" }
                }.font(.system(size: 10)).buttonStyle(.borderless)
                Toggle("Сортировать по плотности", isOn: $parameters.sortAlphabet).font(.system(size: 10))
                Text("Первые 128 знаков. Пробелы пропускаются. Буквы переводятся в векторные контуры; цветные эмодзи могут не поддерживаться.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if (!style.usesTones || parameters.maskMode != 0) && style != .photo && style != .softFocus {
                EffectSlider(title: "Допуск фона", value: $parameters.backgroundTolerance, range: 5...180, format: "%.0f")
                EffectSlider(title: "Порог тёмного", value: $parameters.inkThreshold, range: 35...250, format: "%.0f")
            }
            if style != .photo && style != .softFocus {
                if !style.isPhotographic {
                    EffectSlider(title: "Шаг элементов", value: $parameters.spacing, range: 4...30, format: "%.0f")
                    EffectSlider(title: "Толщина линии", value: $parameters.stroke, range: 0.6...7)
                }
                if style.usesTones {
                    EffectSlider(title: "Контраст", value: $parameters.toneContrast, range: 0.4...3)
                    EffectSlider(title: "Плотность", value: $parameters.toneDensity, range: 0.4...2.5)
                    Toggle("Инвертировать тона", isOn: $parameters.invertTones).font(.system(size: 11))
                    if !style.isPhotographic {
                        EffectSlider(title: "Поворот растра", value: $parameters.screenAngle, range: -90...90, format: "%.0f°")
                    }
                } else {
                    EffectSlider(title: "Упрощение", value: $parameters.simplification, range: 0.7...9)
                    if style == .outline { Toggle("Внутренние линии", isOn: $parameters.detail).font(.system(size: 11)) }
                }
            }
            if [.shadow, .softFocus, .photogram, .xray].contains(style) {
                EffectSlider(title: style == .xray ? "Свечение" : "Размытие эффекта", value: $parameters.softness, range: 0...24)
            }
            if [.xray, .flow, .glitch].contains(style) {
                EffectSlider(title: "Выраженность", value: $parameters.textureAmount, range: 0...1)
            }
            if style.supportsTint {
                InkPalette(title: "Чернила", selection: $ink, colors: [.black, .white, Color(red: 0.52, green: 0.56, blue: 0.87), Color(red: 0.72, green: 0.86, blue: 1)])
            }
        }
    }
}

struct PaperSettings: View {
    @Binding var paper: Bool
    @Binding var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Фон при экспорте", isOn: $paper).font(.system(size: 11))
            if paper {
                InkPalette(title: "Бумага", selection: $color,
                           colors: [.white, .black, Color(red: 1, green: 0.98, blue: 0.88), Color(red: 1, green: 0.84, blue: 0.3)])
            }
        }
    }
}

struct InkPalette: View {
    var title: String
    @Binding var selection: Color
    var colors: [Color]
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11))
            Spacer(minLength: 0)
            ForEach(colors.indices, id: \.self) { i in
                Button { selection = colors[i] } label: {
                    Circle().fill(colors[i]).frame(width: 15, height: 15).overlay(Circle().strokeBorder(.gray.opacity(0.4)))
                }.buttonStyle(.plain).accessibilityLabel("\(title), образец \(i + 1)")
            }
            ColorPicker(title, selection: $selection, supportsOpacity: false).labelsHidden()
        }
    }
}
