import AppKit

// One small vector model powers the preview and both exports.
// Coordinates always run from the top-left, just like an image or SVG.
struct Mark {
    var path: CGPath
    var fill: Bool
    var width: CGFloat = 1
    var opacity: CGFloat = 1
}

struct Drawing {
    var marks: [Mark] = []
    var size: CGFloat = 384
    var raster: CGImage?
    var rasterUsesInk = false
    var note: String?
    var isEmpty: Bool { marks.isEmpty && raster == nil }

    mutating func line(_ points: [CGPoint], width: CGFloat, closed: Bool = false,
                       filled: Bool = false, smooth: Bool = false, opacity: CGFloat = 1) {
        guard points.count > 1 else { return }
        let p = CGMutablePath()
        p.move(to: points[0])
        if smooth && points.count > 3 {
            let n = points.count
            let count = closed ? n : n - 1
            for i in 0..<count {
                let a = points[closed ? (i - 1 + n) % n : max(0, i - 1)]
                let b = points[i]
                let c = points[(i + 1) % n]
                let d = points[closed ? (i + 2) % n : min(n - 1, i + 2)]
                p.addCurve(to: c,
                           control1: CGPoint(x: b.x + (c.x - a.x) / 6, y: b.y + (c.y - a.y) / 6),
                           control2: CGPoint(x: c.x - (d.x - b.x) / 6, y: c.y - (d.y - b.y) / 6))
            }
        } else {
            for point in points.dropFirst() { p.addLine(to: point) }
        }
        if closed { p.closeSubpath() }
        marks.append(Mark(path: p, fill: filled, width: width, opacity: opacity))
    }

    mutating func ellipse(x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat,
                          filled: Bool = true, width: CGFloat = 1, angle: CGFloat = 0) {
        let p = CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: nil)
        var transform = CGAffineTransform(rotationAngle: angle)
        transform.tx = x
        transform.ty = y
        if let path = p.copy(using: &transform) { marks.append(Mark(path: path, fill: filled, width: width)) }
    }

    mutating func rect(_ rect: CGRect) {
        marks.append(Mark(path: CGPath(rect: rect, transform: nil), fill: true))
    }

    func paint(in ctx: CGContext, color: NSColor) {
        if let raster {
            ctx.saveGState()
            if rasterUsesInk { ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
            drawImage(raster, in: CGRect(x: 0, y: 0, width: size, height: size), context: ctx)
            if rasterUsesInk {
                ctx.setBlendMode(.sourceIn)
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
                ctx.endTransparencyLayer()
            }
            ctx.restoreGState()
        }
        ctx.setFillColor(color.cgColor)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        for mark in marks {
            ctx.setAlpha(mark.opacity)
            ctx.setLineWidth(mark.width)
            ctx.addPath(mark.path)
            ctx.drawPath(using: mark.fill ? .eoFill : .stroke)
        }
        ctx.setAlpha(1)
    }

    func png(color: NSColor, background: NSColor?, pixels: Int = 1536) -> Data? {
        guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                  bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if let background {
            ctx.setFillColor(background.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        }
        // Quartz bitmap contexts point up; our vector model points down.
        ctx.translateBy(x: 0, y: CGFloat(pixels))
        ctx.scaleBy(x: CGFloat(pixels) / size, y: -CGFloat(pixels) / size)
        paint(in: ctx, color: color)
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    func svg(color: NSColor, background: NSColor?) -> String {
        var elements: [String] = []
        if let background {
            elements.append("<rect width=\"384\" height=\"384\" fill=\"\(background.hex)\"/>")
        }
        elements.append(contentsOf: svgElements(color: color))
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1536\" height=\"1536\" viewBox=\"0 0 384 384\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\n" + elements.joined(separator: "\n") + "\n</svg>"
    }

    func svgElements(color: NSColor) -> [String] {
        var elements: [String] = []
        if raster != nil {
            var imageOnly = self
            imageOnly.marks = []
            if let data = imageOnly.png(color: color, background: nil, pixels: 384) {
                elements.append("<image width=\"384\" height=\"384\" href=\"data:image/png;base64,\(data.base64EncodedString())\"/>")
            }
        }
        for mark in marks {
            var commands: [String] = []
            mark.path.applyWithBlock { pointer in
                let e = pointer.pointee
                func pt(_ i: Int) -> String { "\(fmt(e.points[i].x)) \(fmt(e.points[i].y))" }
                switch e.type {
                case .moveToPoint: commands.append("M\(pt(0))")
                case .addLineToPoint: commands.append("L\(pt(0))")
                case .addQuadCurveToPoint: commands.append("Q\(pt(0)) \(pt(1))")
                case .addCurveToPoint: commands.append("C\(pt(0)) \(pt(1)) \(pt(2))")
                case .closeSubpath: commands.append("Z")
                @unknown default: break
                }
            }
            let appearance = mark.fill ? "fill=\"\(color.hex)\" fill-rule=\"evenodd\"" : "fill=\"none\" stroke=\"\(color.hex)\" stroke-width=\"\(fmt(mark.width))\""
            elements.append("<path d=\"\(commands.joined(separator: " "))\" \(appearance) opacity=\"\(fmt(mark.opacity))\"/>")
        }
        return elements
    }
}

// Draw a CGImage into our top-left coordinate system without flipping its rows.
func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(origin: .zero, size: rect.size))
    context.restoreGState()
}

func fmt(_ v: CGFloat) -> String { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), Double(v)) }

extension NSColor {
    var hex: String {
        let c = usingColorSpace(.deviceRGB) ?? self
        func channel(_ value: CGFloat) -> Int { min(255, max(0, Int(value * 255))) }
        return String(format: "#%02x%02x%02x", channel(c.redComponent), channel(c.greenComponent), channel(c.blueComponent))
    }
}

func simplify(_ pts: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
    guard pts.count > 2 else { return pts }
    let a = pts[0], b = pts[pts.count - 1]
    let dx = b.x - a.x, dy = b.y - a.y
    let length = dx * dx + dy * dy
    var maxDistance: CGFloat = 0
    var split = 0
    for i in 1..<(pts.count - 1) {
        let t = length == 0 ? 0 : max(0, min(1, ((pts[i].x - a.x) * dx + (pts[i].y - a.y) * dy) / length))
        let distance = hypot(pts[i].x - a.x - t * dx, pts[i].y - a.y - t * dy)
        if distance > maxDistance { maxDistance = distance; split = i }
    }
    if maxDistance > tolerance {
        return Array(simplify(Array(pts[...split]), tolerance: tolerance).dropLast()) + simplify(Array(pts[split...]), tolerance: tolerance)
    }
    return [a, b]
}

func polygonArea(_ points: [CGPoint]) -> CGFloat {
    guard points.count > 2 else { return 0 }
    return points.indices.reduce(CGFloat.zero) { sum, i in
        let a = points[i], b = points[(i + 1) % points.count]
        return sum + a.x * b.y - b.x * a.y
    } / 2
}
