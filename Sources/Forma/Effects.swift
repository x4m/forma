import AppKit
import Accelerate
import CoreText

enum ImageFilters {
    // Three box passes approximate a Gaussian with the requested sigma. vImage
    // runs on the CPU, including during headless rendering and on older Macs.
    static func blur(_ image: CGImage, radius: CGFloat) -> CGImage {
        guard radius > 0.01 else { return image }
        let w = image.width, h = image.height
        var source = [UInt8](repeating: 0, count: w * h * 4)
        var scratch = source
        source.withUnsafeMutableBytes { bytes in
            let ctx = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let sigma = Double(radius)
        var lower = Int(floor(sqrt(4 * sigma * sigma + 1)))
        if lower.isMultiple(of: 2) { lower -= 1 }
        lower = max(1, lower)
        let upper = lower + 2
        let numerator = 12 * sigma * sigma - 3 * Double(lower * lower) - 12 * Double(lower) - 9
        let count = max(0, min(3, Int(round(numerator / Double(-4 * lower - 4)))))
        source.withUnsafeMutableBytes { a in
            scratch.withUnsafeMutableBytes { b in
                var input = vImage_Buffer(data: a.baseAddress!, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
                var output = vImage_Buffer(data: b.baseAddress!, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
                for pass in 0..<3 {
                    let size = UInt32(pass < count ? lower : upper)
                    let status = vImageBoxConvolve_ARGB8888(&input, &output, nil, 0, 0, size, size, nil, vImage_Flags(kvImageEdgeExtend))
                    precondition(status == kvImageNoError, "Unexpected vImage blur failure")
                    swap(&input, &output)
                }
            }
        }
        // Three swaps put the final image in scratch.
        return rgbaImage(scratch, width: w, height: h)!
    }
}

extension Engine {
    func photographicDrawing(_ style: Style, _ p: Parameters) -> Drawing {
        var drawing = Drawing()
        if style == .photo || style == .softFocus {
            drawing.raster = style == .photo ? raster.image : ImageFilters.blur(raster.image, radius: p.softness)
            return drawing
        }
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let i = y * n + x
                let alpha = toneField.coverage[i]
                guard alpha > 0.001 else { continue }
                let t = toneField.darkness[i] / alpha
                var intensity = t
                if style == .xray {
                    func value(_ xx: Int, _ yy: Int) -> Double {
                        let j = min(n - 1, max(0, yy)) * n + min(n - 1, max(0, xx))
                        return toneField.coverage[j] > 0 ? toneField.darkness[j] / toneField.coverage[j] : 0
                    }
                    let gradient = hypot(value(x + 1, y) - value(x - 1, y), value(x, y + 1) - value(x, y - 1))
                    let local = (value(x + 3, y) + value(x - 3, y) + value(x, y + 3) + value(x, y - 3)) / 4
                    intensity = min(1, 0.2 * sqrt(t) + gradient * (1.2 + p.textureAmount * 3) + abs(t - local) * 1.5)
                } else if style == .photogram {
                    intensity = pow(t, 0.6) * 0.85
                }
                let a = UInt8(min(255, max(0, intensity * alpha * 255)))
                pixels[i * 4] = a; pixels[i * 4 + 1] = a; pixels[i * 4 + 2] = a; pixels[i * 4 + 3] = a
            }
        }
        let image = rgbaImage(pixels, width: n, height: n)
        if let image {
            let radius = style == .xray ? p.softness * 0.12 : p.softness
            drawing.raster = ImageFilters.blur(image, radius: radius)
            drawing.rasterUsesInk = true
        }
        return drawing
    }
}

func rgbaImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
}

private func textureNoise(_ x: Int, _ y: Int, _ salt: Int = 0) -> CGFloat {
    // Fixed integer hashing: appearance never changes merely because of redraw.
    var h = UInt64(bitPattern: Int64(x)) &* 0x9e3779b185ebca87
    h ^= UInt64(bitPattern: Int64(y)) &* 0xc2b2ae3d27d4eb4f
    h ^= UInt64(salt) &* 0x165667b19e3779f9
    h = (h ^ (h >> 29)) &* 0x85ebca77c2b2ae63
    return CGFloat((h ^ (h >> 32)) & 65535) / 65535
}

extension ToneField {
    func textureDrawing(_ style: Style, _ p: Parameters) -> Drawing {
        var result = Drawing()
        let pitch = max(2, CGFloat(p.spacing) * 0.65)
        let angle = CGFloat(p.screenAngle * .pi / 180)
        let cs = cos(angle), sn = sin(angle)
        func world(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: bounds.midX + x * cs - y * sn, y: bounds.midY + x * sn + y * cs)
        }
        func rect(_ rectangle: CGRect) {
            let clipped = rectangle.intersection(bounds)
            if !clipped.isEmpty { result.rect(clipped) }
        }
        if style == .glitch {
            let step = max(1, pitch * 0.32)
            var row = 0
            for y in stride(from: bounds.minY + step / 2, to: bounds.maxY, by: step) {
                let threshold = 0.25 + Double(textureNoise(row, 0, 1)) * 0.5
                let shift = (textureNoise(row, 0, 2) - 0.5) * pitch * CGFloat(p.textureAmount) * 3
                var start: CGFloat?
                for x in stride(from: bounds.minX, through: bounds.maxX + 1, by: CGFloat(1)) {
                    let s = sample(CGPoint(x: x, y: y))
                    let active = x < bounds.maxX && s.alpha > 0.5 && s.tone > threshold && textureNoise(Int(x / 3), row, 3) > p.textureAmount * 0.13
                    if active && start == nil { start = x }
                    if !active, let a = start {
                        rect(CGRect(x: a + shift, y: y, width: max(0.6, x - a), height: min(step, step * CGFloat(p.stroke / 2.4) * 0.75)))
                        start = nil
                    }
                }
                row += 1
            }
            return result
        }
        let glyphs = style == .ascii ? GlyphAtlas.make(p.alphabet, sorted: p.sortAlphabet) : []
        if style == .ascii && glyphs.isEmpty {
            result.note = "У этих символов нет векторных контуров. Попробуй буквы, цифры или знаки вместо цветных эмодзи."
            return result
        }
        let reach = hypot(bounds.width, bounds.height) / 2 + pitch
        let cellX = style == .stipple ? pitch * 0.42 : pitch
        let cellY = style == .ascii ? pitch * 1.45 : (style == .dotScreen ? pitch * 0.866 : cellX)
        let nx = Int(ceil(reach / cellX)), ny = Int(ceil(reach / cellY))
        for row in -ny...ny {
            for column in -nx...nx {
                var u = CGFloat(column) * cellX
                var v = CGFloat(row) * cellY
                if style == .dotScreen && !row.isMultiple(of: 2) { u += cellX / 2 }
                if style == .stipple {
                    u += (textureNoise(column, row, 1) - 0.5) * cellX * 0.9
                    v += (textureNoise(column, row, 2) - 0.5) * cellY * 0.9
                }
                let point = world(u, v)
                guard bounds.contains(point) else { continue }
                let s = sample(point)
                guard s.alpha > 0.5, s.tone > 0.015 else { continue }
                let t = CGFloat(s.tone)
                switch style {
                case .ascii:
                    let glyph = glyphs[min(glyphs.count - 1, Int(t * CGFloat(glyphs.count)))]
                    let scale = min(pitch * 0.9 / glyph.frame.width, cellY * 0.9 / glyph.frame.height)
                    var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
                                                     tx: point.x - glyph.frame.midX * scale, ty: point.y + glyph.frame.midY * scale)
                    if let path = glyph.path.copy(using: &transform) {
                        result.marks.append(Mark(path: path, fill: true, opacity: 0.18 + 0.82 * t))
                    }
                case .crosses:
                    let h = pitch * (0.29 + 0.1 * t)
                    let width = min(pitch * 0.36, CGFloat(p.stroke) * 0.48)
                    result.line([world(u - h, v - h), world(u + h, v + h)], width: width, opacity: pow(t, 0.7))
                    result.line([world(u + h, v - h), world(u - h, v + h)], width: width, opacity: pow(t, 0.7))
                case .dotScreen:
                    let r = min(pitch * 0.49, pitch * 0.48 * sqrt(t) * CGFloat(p.stroke / 2.4))
                    if bounds.insetBy(dx: r, dy: r).contains(point) { result.ellipse(x: point.x, y: point.y, rx: r, ry: r) }
                case .stipple:
                    guard textureNoise(column, row, 4) < t else { continue }
                    let r = cellX * (0.12 + textureNoise(column, row, 5) * 0.3) * CGFloat(p.stroke / 2.4)
                    if bounds.insetBy(dx: r, dy: r).contains(point) { result.ellipse(x: point.x, y: point.y, rx: r, ry: r) }
                case .flow:
                    func direction(_ q: CGPoint) -> CGFloat {
                        let gx = sample(CGPoint(x: q.x + 2, y: q.y)).tone - sample(CGPoint(x: q.x - 2, y: q.y)).tone
                        let gy = sample(CGPoint(x: q.x, y: q.y + 2)).tone - sample(CGPoint(x: q.x, y: q.y - 2)).tone
                        let flow = atan2(CGFloat(gy), CGFloat(gx)) + .pi / 2
                        let base = angle + sin(q.x * 0.03) * 0.4 + cos(q.y * 0.03) * 0.3
                        let mix = min(0.9, hypot(gx, gy) * (2 + p.textureAmount * 5))
                        return atan2(sin(base * 2) * (1 - mix) + sin(flow * 2) * mix,
                                     cos(base * 2) * (1 - mix) + cos(flow * 2) * mix) / 2
                    }
                    var points = [point]
                    for sign in [-1.0, 1.0] {
                        var q = point, arm: [CGPoint] = []
                        for _ in 0..<3 {
                            let a = direction(q)
                            q.x += cos(a) * pitch * 0.2 * sign
                            q.y += sin(a) * pitch * 0.2 * sign
                            if !bounds.contains(q) || sample(q).tone < 0.025 { break }
                            arm.append(q)
                        }
                        if sign < 0 { points = Array(arm.reversed()) + points } else { points += arm }
                    }
                    result.line(points, width: max(0.25, CGFloat(p.stroke) * 0.27), opacity: pow(t, 0.6))
                default: break
                }
            }
        }
        return result
    }
}

struct GlyphAtlas {
    struct Glyph { let path: CGPath; let frame: CGRect; let weight: Double }

    static func make(_ alphabet: String, sorted: Bool) -> [Glyph] {
        let font = CTFontCreateWithName("Menlo" as CFString, 32, nil)
        var seen = Set<Character>()
        var glyphs: [Glyph] = []
        for character in alphabet.prefix(128) where !character.isWhitespace && seen.insert(character).inserted {
            let text = NSAttributedString(string: String(character), attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let line = CTLineCreateWithAttributedString(text)
            let combined = CGMutablePath()
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let advance = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var ids = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &ids)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let runFont = attributes[kCTFontAttributeName] as! CTFont
                for i in ids.indices {
                    guard ids[i] != 0, let path = CTFontCreatePathForGlyph(runFont, ids[i], nil) else { continue }
                    combined.addPath(path, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
                }
            }
            guard !combined.isEmpty, advance > 0 else { continue }
            let frame = CGRect(x: 0, y: -descent, width: advance, height: ascent + descent)
            let weight = glyphWeight(combined, frame: frame)
            glyphs.append(Glyph(path: combined, frame: frame, weight: weight))
        }
        return sorted ? glyphs.enumerated().sorted { $0.element.weight == $1.element.weight ? $0.offset < $1.offset : $0.element.weight < $1.element.weight }.map(\.element) : glyphs
    }

    private static func glyphWeight(_ path: CGPath, frame: CGRect) -> Double {
        var bytes = [UInt8](repeating: 0, count: 32 * 32)
        bytes.withUnsafeMutableBytes { data in
            let ctx = CGContext(data: data.baseAddress, width: 32, height: 32, bitsPerComponent: 8,
                                bytesPerRow: 32, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            let scale = min(30 / frame.width, 30 / frame.height)
            ctx.translateBy(x: 1 - frame.minX * scale, y: 1 - frame.minY * scale)
            ctx.scaleBy(x: scale, y: scale)
            ctx.setFillColor(gray: 1, alpha: 1); ctx.addPath(path); ctx.fillPath(using: .evenOdd)
        }
        return bytes.reduce(0.0) { $0 + Double($1) } / 255
    }
}
