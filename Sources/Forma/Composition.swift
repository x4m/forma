import AppKit
import SwiftUI

struct Ink: Codable, Equatable {
    var r: Double; var g: Double; var b: Double
    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        r = min(1, max(0, c.redComponent)); g = min(1, max(0, c.greenComponent)); b = min(1, max(0, c.blueComponent))
    }
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    var color: Color { Color(nsColor: ns) }
    var valid: Bool { [r, g, b].allSatisfy { $0.isFinite && (0...1).contains($0) } }
}

enum LayerBlend: String, CaseIterable, Codable, Identifiable {
    case normal, multiply, screen
    var id: String { rawValue }
    var title: String { self == .normal ? "Обычный" : (self == .multiply ? "Умножение" : "Экран") }
    var cg: CGBlendMode { self == .normal ? .normal : (self == .multiply ? .multiply : .screen) }
}

struct ArtLayer: Identifiable, Codable, Equatable {
    var id = UUID()
    var style: Style
    var parameters: Parameters
    var ink: Ink
    var enabled = true
    var opacity: Double = 1
    var blur: Double = 0
    var x: Double = 0
    var y: Double = 0
    var scale: Double = 1
    var rotation: Double = 0
    var blend: LayerBlend = .normal

    var valid: Bool {
        ink.valid && parameters.valid && opacity.isFinite && (0...1).contains(opacity) &&
        blur.isFinite && (0...30).contains(blur) && scale.isFinite && (0.1...3).contains(scale) &&
        x.isFinite && abs(x) <= 384 && y.isFinite && abs(y) <= 384 && rotation.isFinite && abs(rotation) <= 360
    }
}

struct LayerRecipe: Equatable {
    var id: UUID
    var style: Style
    var parameters: Parameters
    init(_ layer: ArtLayer) { id = layer.id; style = layer.style; parameters = layer.parameters }
}

struct RenderedLayer { var layer: ArtLayer; var drawing: Drawing }

struct Composition {
    // Storage is bottom-to-top, just like a painter's order.
    var layers: [RenderedLayer]
    var background: NSColor?

    var hasRaster: Bool { layers.contains { $0.layer.enabled && $0.drawing.raster != nil } }

    func image(pixels: Int = 768) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if let background { ctx.setFillColor(background.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels)) }
        let scale = CGFloat(pixels) / 384
        ctx.translateBy(x: 0, y: CGFloat(pixels)); ctx.scaleBy(x: scale, y: -scale)
        for item in layers where item.layer.enabled && item.layer.opacity > 0 {
            let layer = item.layer
            // Extra transparent pixels prevent a blur from being clipped before
            // a translated/rotated layer is placed on the final canvas.
            let padding = CGFloat(ceil(layer.blur * 3) + 2)
            let extent = CGRect(x: -padding, y: -padding, width: 384 + padding * 2, height: 384 + padding * 2)
            let side = Int(ceil(extent.width * scale))
            guard let isolated = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            isolated.translateBy(x: 0, y: CGFloat(side)); isolated.scaleBy(x: scale, y: -scale)
            isolated.translateBy(x: padding, y: padding)
            item.drawing.paint(in: isolated, color: layer.ink.ns)
            guard let raw = isolated.makeImage() else { continue }
            let image = ImageFilters.blur(raw, radius: layer.blur * scale)
            ctx.saveGState()
            ctx.setAlpha(layer.opacity); ctx.setBlendMode(layer.blend.cg)
            ctx.translateBy(x: 192 + layer.x, y: 192 + layer.y)
            ctx.rotate(by: layer.rotation * .pi / 180)
            ctx.scaleBy(x: layer.scale, y: layer.scale)
            ctx.translateBy(x: -192, y: -192)
            drawImage(image, in: extent, context: ctx)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    func png(pixels: Int = 1536) -> Data? {
        guard let image = image(pixels: pixels) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    func svg() -> String {
        var definitions: [String] = [], body: [String] = []
        if let background { body.append("<rect width=\"384\" height=\"384\" fill=\"\(background.hex)\"/>") }
        for (index, item) in layers.enumerated() where item.layer.enabled && item.layer.opacity > 0 {
            let layer = item.layer
            var filter = ""
            if layer.blur > 0 {
                let pad = layer.blur * 3 + 2
                definitions.append("<filter id=\"blur\(index)\" filterUnits=\"userSpaceOnUse\" x=\"\(fmt(-pad))\" y=\"\(fmt(-pad))\" width=\"\(fmt(384 + 2 * pad))\" height=\"\(fmt(384 + 2 * pad))\" color-interpolation-filters=\"sRGB\"><feGaussianBlur stdDeviation=\"\(fmt(layer.blur))\"/></filter>")
                filter = " filter=\"url(#blur\(index))\""
            }
            let transform = "translate(\(fmt(192 + layer.x)) \(fmt(192 + layer.y))) rotate(\(fmt(layer.rotation))) scale(\(fmt(layer.scale))) translate(-192 -192)"
            let paths = item.drawing.svgElements(color: layer.ink.ns).joined(separator: "\n")
            body.append("<g transform=\"\(transform)\" opacity=\"\(fmt(layer.opacity))\" style=\"mix-blend-mode:\(layer.blend.rawValue)\"><g\(filter)>\n\(paths)\n</g></g>")
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1536\" height=\"1536\" viewBox=\"0 0 384 384\" stroke-linecap=\"round\" stroke-linejoin=\"round\" style=\"isolation:isolate\">\n<defs>\(definitions.joined())</defs>\n\(body.joined(separator: "\n"))\n</svg>"
    }
}

struct SourceRecord: Codable {
    var rgba: Data
    var name: String
    var background: [Double]
    var bounds: CGRect

    init(_ raster: Raster) throws {
        rgba = Data(raster.rgba); name = raster.name; background = raster.background; bounds = raster.contentRect
    }

    func restore() throws -> Raster {
        guard rgba.count == 384 * 384 * 4, let image = rgbaImage(Array(rgba), width: 384, height: 384),
              background.count == 3, background.allSatisfy({ $0.isFinite && (0...255).contains($0) }),
              !bounds.isEmpty, CGRect(x: 0, y: 0, width: 384, height: 384).contains(bounds) else { throw ImageFailure.unreadable }
        return Raster(rgba: Array(rgba), image: image, background: background, name: name, contentRect: bounds)
    }
}

struct FormaProject: Codable {
    var schema = 1
    var source: SourceRecord
    var layers: [ArtLayer]
    var style: Style
    var parameters: Parameters
    var ink: Ink
    var paper: Ink
    var opaque: Bool

    func validate() throws {
        guard schema == 1, layers.count <= 64, Set(layers.map(\.id)).count == layers.count,
              layers.allSatisfy(\.valid), parameters.valid, ink.valid, paper.valid else { throw ImageFailure.unreadable }
    }
}

extension Parameters {
    var valid: Bool {
        let values = [spacing, stroke, simplification, backgroundTolerance, inkThreshold, toneContrast, toneDensity, screenAngle, softness, textureAmount]
        return values.allSatisfy(\.isFinite) && (4...30).contains(spacing) && (0.6...7).contains(stroke) &&
            (0.7...9).contains(simplification) && (5...180).contains(backgroundTolerance) && (35...250).contains(inkThreshold) &&
            (0.4...3).contains(toneContrast) && (0.4...2.5).contains(toneDensity) && abs(screenAngle) <= 90 &&
            (0...24).contains(softness) && (0...1).contains(textureAmount) && (0...2).contains(maskMode) && alphabet.count <= 4096
    }
}
