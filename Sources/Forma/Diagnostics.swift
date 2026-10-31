import AppKit
import SwiftUI

// Headless checks exercise real pixels and export files, not SwiftUI layout.
enum Diagnostics {
    struct Failure: Error, CustomStringConvertible { var description: String }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    @MainActor
    static func snapshot(to url: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        guard let sampleURL = Bundle.main.url(forResource: "sample", withExtension: "png") else {
            throw Failure(description: "Sample is missing from app bundle")
        }
        let raster = try Raster.load(sampleURL)
        let model = AppModel()
        model.raster = raster
        let engine = Engine(raster: raster, parameters: model.parameters)
        for style in Style.allCases { model.drawings[style] = engine.drawing(style, model.parameters) }
        model.busy = false
        let view = ContentView().environmentObject(model).frame(width: 1180, height: 860).environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1180, height: 860)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Render our own offscreen view only. No screen recording or desktop capture.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failure(description: "Cannot render UI") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure(description: "Cannot encode UI snapshot") }
        try data.write(to: url)
        print("UI snapshot: \(url.path)")
    }

    static func fixture(transparent: Bool) throws -> Raster {
        let w = 80, h = 100
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Failure(description: "No bitmap context")
        }
        if !transparent { ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 20, y: 10, width: 40, height: 80))
        if transparent { ctx.clear(CGRect(x: 30, y: 30, width: 20, height: 40)) }
        else { ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 30, y: 30, width: 20, height: 40)) }
        guard let image = ctx.makeImage() else { throw Failure(description: "No fixture image") }
        return try Raster.prepare(image, name: "fixture")
    }

    static func run() throws {
        let outputIndex = CommandLine.arguments.firstIndex(of: "--output")
        let destination = outputIndex.map { URL(fileURLWithPath: CommandLine.arguments[$0 + 1]) }
        if let destination { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) }
        let p = Parameters()
        let raster = try fixture(transparent: false)
        let masks = raster.masks(p)
        let center = (Raster.n / 2) * Raster.n + Raster.n / 2
        try require(masks.shape[center], "Enclosed white area must remain inside silhouette")
        try require(!masks.ink[center], "White belly must not be treated as ink")
        try require(!masks.shape[0], "Exterior background must be removed")
        let alpha = try fixture(transparent: true).masks(p)
        try require(!alpha.shape[center], "Transparent holes must stay empty")
        let engine = Engine(raster: raster, parameters: p)
        try require(engine.inkLoops.count == 2, "A hollow rectangle must have two boundary loops")
        try require(polygonArea(engine.inkLoops[0]) * polygonArea(engine.inkLoops[1]) < 0,
                    "Outer and inner contours must have opposite orientation")
        let color = NSColor(srgbRed: 0.52, green: 0.56, blue: 0.87, alpha: 1)
        for style in Style.allCases {
            let d = engine.drawing(style, p)
            try require(!d.marks.isEmpty, "Style \(style.rawValue) returned no vector paths")
            let svg = d.svg(color: color, background: nil)
            try require(!svg.contains("nan") && !svg.contains("inf"), "Non-finite SVG coordinates")
            let parser = XMLParser(data: Data(svg.utf8))
            try require(parser.parse(), "Invalid SVG XML for style \(style.rawValue)")
            guard let png = d.png(color: color, background: nil, pixels: 384),
                  let decoded = NSBitmapImageRep(data: png) else { throw Failure(description: "PNG encoding failed") }
            try require(decoded.pixelsWide == 384 && decoded.pixelsHigh == 384, "Wrong export size")
            try require(decoded.colorAt(x: 0, y: 0)!.alphaComponent == 0, "Transparent export has opaque background")
            let opaque = d.png(color: color, background: .white, pixels: 384)!
            let opaqueImage = NSBitmapImageRep(data: opaque)!
            try require(opaqueImage.colorAt(x: 0, y: 0)!.alphaComponent == 1, "Paper export should be opaque")
            try require(svg == engine.drawing(style, p).svg(color: color, background: nil), "Output must be deterministic")
            if let destination {
                try Data(svg.utf8).write(to: destination.appendingPathComponent("fixture-\(style.rawValue).svg"))
                try opaque.write(to: destination.appendingPathComponent("fixture-\(style.rawValue).png"))
            }
        }
        // Ensure the bitmap exporter and the preview use the same Y direction.
        var asymmetric = Drawing()
        asymmetric.rect(CGRect(x: 40, y: 20, width: 30, height: 30))
        let direction = NSBitmapImageRep(data: asymmetric.png(color: .black, background: .white, pixels: 384)!)!
        try require(direction.colorAt(x: 50, y: 30)!.redComponent < 0.1, "PNG vertical orientation is inverted")
        try require(direction.colorAt(x: 50, y: 350)!.redComponent > 0.9, "PNG bottom must remain white")
        try halftoneChecks(destination: destination)
        print("PASS: segmentation, alpha holes, contour topology, \(Style.allCases.count) styles, SVG XML, PNG size/transparency, orientation, deterministic output")

        if let destination, let sampleURL = Bundle.main.url(forResource: "sample", withExtension: "png") {
            let sample = try Raster.load(sampleURL)
            let sampleEngine = Engine(raster: sample, parameters: p)
            for style in Style.allCases {
                let d = sampleEngine.drawing(style, p)
                try require(!d.marks.isEmpty, "Sample style \(style.rawValue) is empty")
                try d.png(color: color, background: .white, pixels: 768)!.write(to: destination.appendingPathComponent("penguin-\(style.rawValue).png"))
                try Data(d.svg(color: color, background: nil).utf8).write(to: destination.appendingPathComponent("penguin-\(style.rawValue).svg"))
            }
            try contactSheet(sampleEngine, parameters: p, color: color).write(to: destination.appendingPathComponent("contact-sheet.png"))
            print("PASS: bundled penguin in all \(Style.allCases.count) styles; contact sheet saved")
        }
    }

    static func contactSheet(_ engine: Engine, parameters: Parameters, color: NSColor) throws -> Data {
        let cols = 4, cell = 300, rows = Int(ceil(Double(Style.allCases.count) / 4))
        let ctx = CGContext(data: nil, width: cols * cell, height: rows * cell, bitsPerComponent: 8,
                            bytesPerRow: cols * cell * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: cols * cell, height: rows * cell))
        ctx.translateBy(x: 0, y: CGFloat(rows * cell)); ctx.scaleBy(x: 1, y: -1)
        for (index, style) in Style.allCases.enumerated() {
            ctx.saveGState()
            ctx.translateBy(x: CGFloat((index % cols) * cell), y: CGFloat((index / cols) * cell))
            ctx.scaleBy(x: CGFloat(cell) / 384, y: CGFloat(cell) / 384)
            engine.drawing(style, parameters).paint(in: ctx, color: color)
            ctx.restoreGState()
        }
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    }

    static func flat(_ brightness: CGFloat, transparent: Bool = false) throws -> Raster {
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
                            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if !transparent {
            ctx.setFillColor(NSColor(srgbRed: brightness, green: brightness, blue: brightness, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        return try Raster.prepare(ctx.makeImage()!, name: "tone-\(brightness)")
    }

    static func printedArea(_ drawing: Drawing) throws -> Double {
        let png = drawing.png(color: .black, background: nil, pixels: 384)!
        let decoded = NSBitmapImageRep(data: png)!.cgImage!
        var rgba = [UInt8](repeating: 0, count: 384 * 384 * 4)
        rgba.withUnsafeMutableBytes { bytes in
            let ctx = CGContext(data: bytes.baseAddress, width: 384, height: 384, bitsPerComponent: 8,
                                bytesPerRow: 1536, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(decoded, in: CGRect(x: 0, y: 0, width: 384, height: 384))
        }
        return stride(from: 3, to: rgba.count, by: 4).reduce(0.0) { $0 + Double(rgba[$1]) / 255 }
    }

    static func halftoneChecks(destination: URL?) throws {
        let p = Parameters()
        let levels: [CGFloat] = [0.2, 0.5, 0.8]
        let fields = try levels.map { Engine(raster: try flat($0), parameters: p) }
        for style in Style.halftones {
            let areas = try fields.map { try printedArea($0.drawing(style, p)) }
            try require(areas[0] > areas[1] * 1.15 && areas[1] > areas[2] * 1.15,
                        "\(style.title): distinct midtones must print different, monotonic ink areas: \(areas)")
            var rotated = p
            rotated.screenAngle = 37
            let raster = try flat(0.4)
            let drawing = Engine(raster: raster, parameters: rotated).drawing(style, rotated)
            let allowed = raster.contentRect.insetBy(dx: -0.001, dy: -0.001)
            for mark in drawing.marks {
                try require(allowed.contains(mark.path.boundingBoxOfPath), "Rotated marks leaked outside the photograph")
            }
            let empty = Engine(raster: try flat(0, transparent: true), parameters: p).drawing(style, p)
            try require(empty.marks.isEmpty, "Transparent pixels must not turn into paper lines")
            var threshold = p
            threshold.inkThreshold = 35
            let changed = Engine(raster: raster, parameters: threshold).drawing(style, threshold)
            let original = Engine(raster: raster, parameters: p).drawing(style, p)
            try require(changed.svg(color: .black, background: nil) == original.svg(color: .black, background: nil),
                        "Full-photo halftones must be independent of binary ink threshold")
            if let destination {
                for (i, field) in fields.enumerated() {
                    try field.drawing(style, p).png(color: .black, background: .white, pixels: 384)!
                        .write(to: destination.appendingPathComponent("tone-\(style.rawValue)-\(i).png"))
                }
            }
        }
        let raster = try flat(0.5)
        var dense = p
        dense.toneDensity = 2
        let lightArea = try printedArea(Engine(raster: raster, parameters: p).drawing(.threads, p))
        let denseArea = try printedArea(Engine(raster: raster, parameters: dense).drawing(.threads, dense))
        try require(denseArea > lightArea * 1.15, "Density control must increase printed area")
        let yellow = NSColor(srgbRed: 1, green: 0.84, blue: 0.3, alpha: 1)
        let drawing = fields[1].drawing(.bricks, p)
        try require(drawing.svg(color: .black, background: yellow).contains("fill=\"\(yellow.hex)\""), "Paper colour missing from SVG")
        let png = NSBitmapImageRep(data: drawing.png(color: .black, background: yellow, pixels: 384)!)!
        let corner = png.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
        try require(corner.redComponent > 0.95 && corner.greenComponent > 0.7 && corner.blueComponent < 0.4,
                    "PNG export lost the chosen paper colour")
        print("PASS: continuous midtones, rotated clipping, alpha, threshold independence, density, coloured paper")
    }
}
