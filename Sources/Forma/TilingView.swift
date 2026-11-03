import SwiftUI

struct TilingWorkspaceView: View {
    @EnvironmentObject var model: AppModel
    @State private var zoom = 0.9
    @State private var pan = CGSize.zero
    @State private var panStart: CGSize?
    @State private var zoomStart: Double?
    @State private var activeHandle: String?
    @State private var showHandles = true
    @State private var blocked = false

    var body: some View {
        HStack(spacing: 0) {
            controls.frame(width: 242)
            Divider()
            GeometryReader { geometry in
                let centre = CGPoint(x: geometry.size.width / 2 + pan.width, y: geometry.size.height / 2 + pan.height)
                let viewport = CGRect(x: -centre.x / zoom, y: -centre.y / zoom,
                                      width: geometry.size.width / zoom, height: geometry.size.height / zoom)
                ZStack {
                    Canvas { context, _ in
                        context.translateBy(x: centre.x, y: centre.y)
                        context.scaleBy(x: zoom, y: zoom)
                        let design = model.tile, path = Path(design.path)
                        for (i, j) in design.cells(in: viewport) {
                            let o = design.origin(i, j)
                            var tile = context
                            tile.translateBy(x: o.x, y: o.y)
                            tile.fill(path, with: .color(Color(nsColor: design.fill(i,j))))
                            if design.seam > 0 {
                                tile.stroke(path, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: design.seam, lineJoin: .round))
                            }
                        }
                        if showHandles { context.stroke(path, with: .color(.indigo), lineWidth: 3 / zoom) }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                        if panStart == nil { panStart = pan }
                        pan = CGSize(width: panStart!.width + value.translation.width, height: panStart!.height + value.translation.height)
                    }.onEnded { _ in panStart = nil })
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                        guard showHandles else { return }
                        model.insertTileKnot(at: world(value.location, centre: centre), tolerance: 12 / zoom)
                    })
                    .simultaneousGesture(MagnifyGesture().onChanged { value in
                        if zoomStart == nil { zoomStart = zoom }
                        zoom = max(0.25, min(2.8, zoomStart! * value.magnification))
                    }.onEnded { _ in zoomStart = nil })

                    if showHandles {
                        ForEach(model.tile.handles) { handle in
                            Circle().fill(handleColor(handle)).frame(width: isVertex(handle) ? 13 : 10, height: isVertex(handle) ? 13 : 10)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                                .frame(width: 24, height: 24).contentShape(Circle())
                                .position(x: centre.x + handle.point.x * zoom, y: centre.y + handle.point.y * zoom)
                                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tilePlane")).onChanged { value in
                                    if activeHandle == nil {
                                        activeHandle = handle.id; model.beginContinuousEdit("Изменить форму плитки")
                                    }
                                    blocked = !model.moveTileHandle(handle.kind, to: world(value.location, centre: centre))
                                }.onEnded { _ in
                                    activeHandle = nil; model.endContinuousEdit()
                                })
                                .contextMenu {
                                    if case .knot(let edge, let index) = handle.kind {
                                        Button("Удалить точку излома") { model.removeTileKnot(edge, index) }
                                    } else { Text("Связана с противоположной вершиной") }
                                }
                                .accessibilityLabel(isVertex(handle) ? "Вершина плитки" : "Точка излома границы")
                        }
                    }
                }
                .coordinateSpace(name: "tilePlane")
                .clipped()
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Одна форма. Бесконечный узор.").font(.system(size: 19, weight: .medium))
                        Text("Тяни фон для перемещения · двойной щелчок по границе добавляет излом")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(18)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    if blocked {
                        Text("Здесь границы пересеклись бы. Попробуй потянуть в другую сторону.")
                            .font(.system(size: 11)).padding(12).background(.regularMaterial, in: Capsule()).padding(16)
                            .allowsHitTesting(false)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .onDisappear { if activeHandle != nil { model.endContinuousEdit(); activeHandle = nil } }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("ОСНОВА ПЛИТКИ").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Picker("Основа", selection: Binding(get: { model.tile.kind }, set: { model.setTileKind($0); blocked = false })) {
                    ForEach(TileKind.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
                Text("Противоположные вершины и стороны связаны. Каждая копия плитки имеет одинаковую форму.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    Button("Прямые стороны") { model.resetTile(); blocked = false }
                    Button("Замок") { model.tilePreset(1); blocked = false }
                    Button("Зигзаг") { model.tilePreset(2); blocked = false }
                }.buttonStyle(.borderless)
                Divider()
                Toggle("Показывать точки", isOn: $showHandles).font(.system(size: 11))
                Text("Большие точки меняют вершины. Маленькие — выступы и выемки. Правый щелчок по маленькой точке позволяет удалить её.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Picker("Цвета", selection: model.value(\.tile, name: "Изменить цвета мощения").palette) {
                    Text("Лаванда").tag(0); Text("Терракота").tag(1); Text("Серый камень").tag(2)
                }.font(.system(size: 11))
                EffectSlider(title: "Шов", value: model.value(\.tile, name: "Изменить шов").seam, range: 0...8)
                Divider()
                HStack { Text("Масштаб"); Spacer(); Text("\(Int(zoom * 100))%") }.font(.system(size: 11))
                Slider(value: $zoom, in: 0.25...2.8).controlSize(.small)
                Button("Вернуться к плитке") { pan = .zero; zoom = 0.9; blocked = false }
                    .buttonStyle(.borderless)
                Divider()
                Text("СОХРАНИТЬ").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Button("Проект плитки…  ⌘S") { model.saveTile() }
                Button("Одна плитка · SVG…") { model.exportTile(pattern: false) }
                Button("Узор · SVG…") { model.exportTile(pattern: true) }
                Text("⌘Z — отмена · ⌘⇧Z — повтор\nПроект .formatile сохраняет форму и оформление.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(20)
        }
    }
    private func world(_ p: CGPoint, centre: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - centre.x) / zoom, y: (p.y - centre.y) / zoom)
    }
    private func isVertex(_ h: TileHandle) -> Bool { if case .vertex = h.kind { return true }; return false }
    private func handleColor(_ h: TileHandle) -> Color {
        let edge: Int
        switch h.kind { case .vertex(let i): edge = i; case .knot(let i, _): edge = i }
        return [Color.indigo, Color.teal, Color.orange][edge % model.tile.half]
    }
}
