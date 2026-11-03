import SwiftUI
import UniformTypeIdentifiers

struct TileDocument: Codable {
    var version = 2
    var tile: TileDesign
    func validate() throws {
        guard (1...2).contains(version), tile.valid else { throw CocoaError(.fileReadCorruptFile) }
    }
}

extension TileDesign {
    static let exportRect = CGRect(x: -600, y: -450, width: 1200, height: 900)

    func svg(pattern: Bool) -> String {
        let rect = pattern ? Self.exportRect : bounds.insetBy(dx: -8, dy: -8)
        let entries = pattern ? cells(in: rect) : [(0, 0)]
        let paths = entries.map { i, j -> String in
            let o = origin(i, j)
            let fills = regions.enumerated().map { index, points in
                "<path d=\"\(tileSVGPath(points))\" fill=\"\(regionFill(index,i:i,j:j).hex)\"/>"
            }.joined()
            let border = "<path d=\"\(tileSVGPath(polygon))\"/>" + (division == nil ? "" : "<path d=\"\(tileSVGPath(divisionLine,closed:false))\"/>")
            var drawing = ""
            if showDetails != false {
                for (index,detail) in (details ?? []).enumerated() {
                    let clip = detail.region.flatMap { regions.indices.contains($0) ? regions[$0] : nil } ?? polygon
                    let id = "clip-\(i)-\(j)-\(index)"
                    let content: String
                    if let r = detail.radius, let p = detail.points.first {
                        content = "<circle cx=\"\(p.x)\" cy=\"\(p.y)\" r=\"\(r)\" fill=\"white\"/><circle cx=\"\(p.x)\" cy=\"\(p.y)\" r=\"\(r*0.55)\" fill=\"black\"/>"
                    } else {
                        content = "<path d=\"\(tileSVGPath(detail.points,closed:false))\" fill=\"none\" stroke=\"#595959\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
                    }
                    drawing += "<defs><clipPath id=\"\(id)\"><path d=\"\(tileSVGPath(clip))\"/></clipPath></defs><g clip-path=\"url(#\(id))\">\(content)</g>"
                }
            }
            return "<g transform=\"translate(\(o.x) \(o.y))\">\(fills)<g fill=\"none\" stroke=\"#343846\" stroke-width=\"\(seam)\" stroke-linejoin=\"round\">\(border)</g>\(drawing)</g>"
        }.joined(separator: "\n")
        let background = pattern ? "<rect x=\"\(rect.minX)\" y=\"\(rect.minY)\" width=\"\(rect.width)\" height=\"\(rect.height)\" fill=\"\(fill(0,0).hex)\"/>" : ""
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="\(rect.minX) \(rect.minY) \(rect.width) \(rect.height)">
        \(background)
        \(paths)
        </svg>
        """
    }

    func png() -> Data? {
        let rect = Self.exportRect, w = 1536, h = 1152
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(fill(0,0).cgColor); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.translateBy(x: 0, y: Double(h)); context.scaleBy(x: Double(w) / rect.width, y: -Double(h) / rect.height)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        context.setLineWidth(seam); context.setLineJoin(.round)
        for (i,j) in cells(in: rect) {
            let o = origin(i,j)
            context.saveGState(); context.translateBy(x: o.x, y: o.y)
            paint(in: context, i:i, j:j)
            context.restoreGState()
        }
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

@MainActor
extension AppModel {
    func setTileKind(_ kind: TileKind) {
        guard tile.kind != kind else { return }
        edit("Сменить основу плитки") { tile = TileDesign(kind) }
    }

    func resetTile() { edit("Сбросить плитку") { tile = TileDesign(tile.kind) } }

    func tilePreset(_ index: Int) {
        var next = TileDesign(tile.kind)
        if index == 1 {
            next.profiles[0] = [TileKnot(t: 0.25, offset: 0), TileKnot(t: 0.35, offset: -28),
                                TileKnot(t: 0.65, offset: -28), TileKnot(t: 0.75, offset: 0)]
        } else {
            next.profiles[0] = [TileKnot(t: 0.3, offset: -22), TileKnot(t: 0.7, offset: 22)]
            next.profiles[1] = [TileKnot(t: 0.35, offset: 18), TileKnot(t: 0.65, offset: -18)]
        }
        if next.valid { edit("Загрузить форму плитки") { tile = next } }
    }

    func moveTileHandle(_ handle: TileHandle.Kind, to point: CGPoint) -> Bool {
        guard let next = tile.moving(handle, to: point) else { return false }
        edit("Изменить границу плитки") { tile = next }
        return true
    }

    func insertTileKnot(at point: CGPoint, tolerance: Double) {
        guard let next = tile.inserting(at: point, tolerance: tolerance) else { return }
        edit("Добавить излом") { tile = next }
    }

    func removeTileKnot(_ edge: Int, _ index: Int) {
        var next = tile
        next.profiles[edge % tile.half].remove(at: index)
        if next.valid { edit("Удалить излом") { tile = next } }
    }

    func saveTile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "formatile") ?? .json]
        panel.nameFieldStringValue = "Плитка.formatile"
        do {
            let document = TileDocument(tile: tile)
            try document.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            panel.begin { [weak self] result in
                guard result == .OK, let url = panel.url else { return }
                do { try data.write(to: url, options: .atomic) }
                catch { self?.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }

    func loadTile(_ url: URL) {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard data.count < 100_000 else { throw ImageFailure.unreadable }
            let document = try JSONDecoder().decode(TileDocument.self, from: data)
            try document.validate()
            edit("Открыть проект мощения") { tile = document.tile; mode = .tiling }
        } catch { self.error = "Не удалось открыть плитку: \(error.localizedDescription)" }
    }

    func exportTile(pattern: Bool, svg: Bool = true) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [svg ? .svg : .png]
        panel.nameFieldStringValue = (pattern ? "Мощение" : "Плитка") + (svg ? ".svg" : ".png")
        let design = tile
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            do {
                let data = svg ? Data(design.svg(pattern: pattern).utf8) : design.png()
                guard let data else { throw ImageFailure.unreadable }
                try data.write(to: url, options: .atomic)
            } catch { self?.error = error.localizedDescription }
        }
    }
}
