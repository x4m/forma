import AppKit
import ImageIO

enum Style: Int, CaseIterable, Identifiable {
    case outline = 2, dots = 3, ovals = 11, pixels = 12, waves = 13
    case polygon = 21, mosaic = 22, angular = 23, pencil = 31, bars = 32
    case silhouette = 33, rings = 41, geometry = 42, sketch = 43
    case candles = 51, diagonal = 52, bricks = 53, threads = 54
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .outline: return "Контур"
        case .dots: return "Точки"
        case .ovals: return "Овалы"
        case .pixels: return "Пиксели"
        case .waves: return "Волны"
        case .polygon: return "Многоугольник"
        case .mosaic: return "Мозаика"
        case .angular: return "Ломаная"
        case .pencil: return "Штриховка"
        case .bars: return "Полосы"
        case .silhouette: return "Пятно"
        case .rings: return "Кольца"
        case .geometry: return "Геометрия"
        case .sketch: return "Набросок"
        case .candles: return "Свечи"
        case .diagonal: return "Наклонный растр"
        case .bricks: return "Кирпичики"
        case .threads: return "Нити"
        }
    }
    var explanation: String {
        switch self {
        case .outline: return "Граница объекта → упрощение → плавная кривая."
        case .dots: return "Шестиугольная сетка точек по тёмным областям изображения."
        case .ovals: return "Горизонтальные срезы силуэта заменяются наклонными овалами."
        case .pixels: return "Крупные квадратные ячейки собирают силуэт."
        case .waves: return "Силуэт прорезается ритмом из волнообразных лент."
        case .polygon: return "Контур упрощается до небольшого числа вершин."
        case .mosaic: return "Квадратная сетка с промежутками между элементами."
        case .angular: return "Упрощённая граница объекта с угловатыми соединениями."
        case .pencil: return "Короткие повторяемые штрихи заполняют тёмные участки."
        case .bars: return "Вертикальные срезы тёмных участков."
        case .silhouette: return "Плавный силуэт с сохранением светлых внутренних областей."
        case .rings: return "Силуэт, заполненный полыми окружностями."
        case .geometry: return "Крупные срезы силуэта превращаются в геометрические модули."
        case .sketch: return "Несколько слегка смещённых линий по блочной форме."
        case .candles: return "Яркость управляет телом и тонкими усами вертикальных штрихов."
        case .diagonal: return "Наклонная сетка штрихов: чем темнее фотография, тем крупнее штрих."
        case .bricks: return "Смещённые ряды горизонтальных штрихов передают полутона."
        case .threads: return "Непрерывные нити утолщаются в тёмных местах фотографии."
        }
    }
    var usesInk: Bool { [.dots, .pencil, .bars, .silhouette].contains(self) }
    var isHalftone: Bool { rawValue >= 51 }
    static var halftones: [Style] { [.candles, .diagonal, .bricks, .threads] }
    static var gallery: [Style] { halftones + allCases.filter { !$0.isHalftone } }
}

struct Parameters: Equatable {
    var spacing: Double = 12
    var stroke: Double = 2.4
    var simplification: Double = 3
    var backgroundTolerance: Double = 48
    var inkThreshold: Double = 190
    var detail: Bool = false
    var maskMode: Int = 0 // 0: style default, 1: silhouette, 2: dark areas
    var toneContrast: Double = 1.2
    var toneDensity: Double = 1
    var screenAngle: Double = 0
}

enum ImageFailure: LocalizedError {
    case unreadable, empty
    var errorDescription: String? {
        switch self {
        case .unreadable: return "Не удалось прочитать изображение. Попробуй PNG, JPEG, HEIC или TIFF."
        case .empty: return "Объект не найден. Уменьши допуск фона или выбери другое изображение."
        }
    }
}

struct Raster {
    static let n = 384
    var rgba: [UInt8]
    var image: CGImage
    var background: [Double]
    var name: String
    var contentRect: CGRect

    static func load(_ url: URL) throws -> Raster {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { throw ImageFailure.unreadable }
        return try prepare(image, name: url.deletingPathExtension().lastPathComponent)
    }

    static func prepare(_ image: CGImage, name: String) throws -> Raster {
        let n = Self.n
        let scale = CGFloat(n - 48) / CGFloat(max(image.width, image.height))
        let w = max(1, Int(CGFloat(image.width) * scale))
        let h = max(1, Int(CGFloat(image.height) * scale))
        let x = (n - w) / 2, y = (n - h) / 2
        var data = [UInt8](repeating: 0, count: n * n * 4)
        let drawn = data.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let ctx = CGContext(data: bytes.baseAddress, width: n, height: n, bitsPerComponent: 8,
                                      bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .high
            // Memory rows should be in the same top-to-bottom order as CGImage.
            ctx.draw(image, in: CGRect(x: x, y: y, width: w, height: h))
            return ctx.makeImage()
        }
        guard let drawn else { throw ImageFailure.unreadable }
        // Infer a flat background from the median colour around the source border.
        var samples = [[Double]](repeating: [], count: 3)
        for yy in y..<(y + h) {
            for xx in x..<(x + w) where xx < x + 2 || xx >= x + w - 2 || yy < y + 2 || yy >= y + h - 2 {
                let i = (yy * n + xx) * 4
                if data[i + 3] > 220 {
                    for c in 0..<3 { samples[c].append(min(255, Double(data[i + c]) * 255 / Double(data[i + 3]))) }
                }
            }
        }
        let bg = samples.map { values -> Double in
            let sorted = values.sorted()
            return sorted.isEmpty ? 255 : sorted[sorted.count / 2]
        }
        return Raster(rgba: data, image: drawn, background: bg, name: name,
                      contentRect: CGRect(x: x, y: y, width: w, height: h))
    }

    func masks(_ p: Parameters) -> (shape: [Bool], ink: [Bool]) {
        let n = Self.n
        var candidate = [Bool](repeating: false, count: n * n)
        for i in 0..<(n * n) {
            let a = Double(rgba[i * 4 + 3])
            if a < 24 { candidate[i] = true; continue }
            var distance: Double = 0
            for c in 0..<3 {
                let value = min(255, Double(rgba[i * 4 + c]) * 255 / a)
                distance += pow(value - background[c], 2)
            }
            candidate[i] = sqrt(distance) <= p.backgroundTolerance
        }
        // Only remove background pixels connected to the canvas boundary.
        // An enclosed white belly or a hole does not erase the entire object.
        var outside = [Bool](repeating: false, count: n * n)
        var queue = [Int]()
        queue.reserveCapacity(n * n)
        func seed(_ i: Int) {
            if candidate[i] && !outside[i] { outside[i] = true; queue.append(i) }
        }
        for i in 0..<n { seed(i); seed((n - 1) * n + i); seed(i * n); seed(i * n + n - 1) }
        var head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            let x = i % n, y = i / n
            if x > 0 { seed(i - 1) }; if x < n - 1 { seed(i + 1) }
            if y > 0 { seed(i - n) }; if y < n - 1 { seed(i + n) }
        }
        let shape = outside.indices.map { !outside[$0] && rgba[$0 * 4 + 3] > 24 }
        let ink = shape.indices.map { i -> Bool in
            guard shape[i] else { return false }
            let a = max(1, Double(rgba[i * 4 + 3]))
            let luma = (0.2126 * Double(rgba[i * 4]) + 0.7152 * Double(rgba[i * 4 + 1]) + 0.0722 * Double(rgba[i * 4 + 2])) * 255 / a
            return luma < p.inkThreshold
        }
        return (shape, ink)
    }
}

// Follow oriented grid-cell edges into closed boundary loops, including holes.
func contours(_ mask: [Bool], n: Int = Raster.n) -> [[CGPoint]] {
    let stride = n + 1
    var edges = [Int: [Int]]()
    func add(_ ax: Int, _ ay: Int, _ bx: Int, _ by: Int) {
        edges[ay * stride + ax, default: []].append(by * stride + bx)
    }
    for y in 0..<n {
        for x in 0..<n where mask[y * n + x] {
            if y == 0 || !mask[(y - 1) * n + x] { add(x, y, x + 1, y) }
            if x == n - 1 || !mask[y * n + x + 1] { add(x + 1, y, x + 1, y + 1) }
            if y == n - 1 || !mask[(y + 1) * n + x] { add(x + 1, y + 1, x, y + 1) }
            if x == 0 || !mask[y * n + x - 1] { add(x, y + 1, x, y) }
        }
    }
    var loops: [[CGPoint]] = []
    // Sorting gives deterministic output for preview, diagnostics and exports.
    for start in edges.keys.sorted() {
        while !(edges[start] ?? []).isEmpty {
            var points: [CGPoint] = []
            var current = start
            repeat {
                points.append(CGPoint(x: current % stride, y: current / stride))
                guard var next = edges[current], let end = next.popLast() else { break }
                edges[current] = next
                current = end
            } while current != start && points.count < n * n * 4
            if points.count >= 4 && abs(polygonArea(points)) >= 3 { loops.append(points) }
        }
    }
    return loops.sorted { abs(polygonArea($0)) > abs(polygonArea($1)) }
}

struct Engine {
    let shape: [Bool]
    let ink: [Bool]
    let shapeLoops: [[CGPoint]]
    let inkLoops: [[CGPoint]]
    let n = Raster.n
    let toneField: ToneField

    init(raster: Raster, parameters: Parameters) {
        let masks = raster.masks(parameters)
        shape = masks.shape; ink = masks.ink
        shapeLoops = contours(shape); inkLoops = contours(ink)
        toneField = ToneField(raster: raster, parameters: parameters, shape: shape, ink: ink)
    }

    func drawing(_ style: Style, _ p: Parameters) -> Drawing {
        if style.isHalftone { return toneField.drawing(style, p) }
        var drawing = Drawing()
        let dark = p.maskMode == 2 || (p.maskMode == 0 && style.usesInk)
        let mask = dark ? ink : shape
        let loops = dark ? inkLoops : shapeLoops
        let spacing = CGFloat(p.spacing), stroke = CGFloat(p.stroke)
        func inside(_ x: CGFloat, _ y: CGFloat) -> Bool {
            let xx = Int(x), yy = Int(y)
            return xx >= 0 && yy >= 0 && xx < n && yy < n && mask[yy * n + xx]
        }
        func reduced(_ loop: [CGPoint], _ tolerance: CGFloat) -> [CGPoint] {
            // Split a closed curve at opposite vertices before applying RDP.
            let half = loop.count / 2
            return Array(simplify(Array(loop[...half]), tolerance: tolerance).dropLast()) +
                Array(simplify(Array(loop[half...]) + [loop[0]], tolerance: tolerance).dropLast())
        }
        func filled(_ paths: [[CGPoint]], tolerance: CGFloat, smooth: Bool) {
            let combined = CGMutablePath()
            for loop in paths {
                var part = Drawing()
                part.line(reduced(loop, tolerance), width: 0, closed: true, filled: true, smooth: smooth)
                if let path = part.marks.first?.path { combined.addPath(path) }
            }
            drawing.marks.append(Mark(path: combined, fill: true))
        }
        func coverage(_ x: CGFloat, _ y: CGFloat, _ step: CGFloat) -> CGFloat {
            var sum: CGFloat = 0
            for dy in [-0.32, 0.0, 0.32] {
                for dx in [-0.32, 0.0, 0.32] { if inside(x + dx * step, y + dy * step) { sum += 1 } }
            }
            return sum / 9
        }
        // Ranges of occupied pixels in a row/column; handles disconnected parts.
        func runs(_ fixed: Int, vertical: Bool) -> [(Int, Int)] {
            var spans: [(Int, Int)] = [], start: Int? = nil
            for moving in 0...n {
                let yes = moving < n && (vertical ? mask[moving * n + fixed] : mask[fixed * n + moving])
                if yes && start == nil { start = moving }
                if !yes, let s = start { if moving - s > 2 { spans.append((s, moving)) }; start = nil }
            }
            return spans
        }

        switch style {
        case .outline, .angular:
            let tolerance = CGFloat(p.simplification) * (style == .angular ? 3 : 0.65)
            for loop in loops where abs(polygonArea(loop)) > 12 {
                drawing.line(reduced(loop, tolerance), width: stroke, closed: true, smooth: style == .outline)
            }
            if style == .outline && p.detail && !dark {
                // Ink boundaries that coincide with the outer silhouette would
                // draw the same edge twice. Keep only genuinely interior runs.
                func interior(_ point: CGPoint) -> Bool {
                    for dy in [-3, 0, 3] {
                        for dx in [-3, 0, 3] {
                            let x = Int(point.x) + dx, y = Int(point.y) + dy
                            if x < 0 || y < 0 || x >= n || y >= n || !shape[y * n + x] { return false }
                        }
                    }
                    return true
                }
                for loop in inkLoops where abs(polygonArea(loop)) > 4 {
                    if loop.allSatisfy(interior) {
                        drawing.line(reduced(loop, min(2, tolerance)), width: stroke * 0.65, closed: true, smooth: true)
                    } else {
                        // Rotate to an exterior point so an interior run never
                        // wraps across the beginning and end of this array.
                        let split = loop.firstIndex(where: { !interior($0) }) ?? 0
                        let ordered = Array(loop[split...]) + Array(loop[..<split])
                        var run: [CGPoint] = []
                        func flush() {
                            if run.count > 8 {
                                drawing.line(simplify(run, tolerance: max(1.5, tolerance)), width: stroke * 0.65, smooth: true)
                            }
                            run = []
                        }
                        for point in ordered {
                            if interior(point) { run.append(point) } else { flush() }
                        }
                        flush()
                    }
                }
            }
        case .polygon, .silhouette:
            filled(loops, tolerance: CGFloat(p.simplification) * (style == .polygon ? 3.5 : 0.8), smooth: style == .silhouette)
        case .dots, .rings, .pixels, .mosaic:
            let hex = style == .dots || style == .rings
            let stepY = hex ? spacing * 0.866 : spacing
            var row = 0
            var y = spacing / 2
            while y < CGFloat(n) {
                var x = spacing / 2 + (hex && row % 2 == 1 ? spacing / 2 : 0)
                while x < CGFloat(n) {
                    let fill = coverage(x, y, spacing)
                    if fill >= 0.4 {
                        if hex {
                            drawing.ellipse(x: x, y: y, rx: spacing * 0.43, ry: spacing * 0.43,
                                            filled: style != .rings, width: max(0.5, stroke * 0.55))
                        } else {
                            let side = spacing * (style == .pixels ? 1.01 : 0.84)
                            drawing.rect(CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side))
                        }
                    }
                    x += spacing
                }
                y += stepY; row += 1
            }
        case .ovals:
            for y in stride(from: Int(spacing), to: n, by: max(4, Int(spacing * 1.5))) {
                for (a, b) in runs(y, vertical: false) {
                    drawing.ellipse(x: CGFloat(a + b) / 2, y: CGFloat(y), rx: CGFloat(b - a) * 0.55,
                                    ry: spacing * 0.9, angle: -0.4)
                }
            }
        case .bars:
            for x in stride(from: Int(spacing / 2), to: n, by: max(3, Int(spacing))) {
                for (a, b) in runs(x, vertical: true) {
                    drawing.rect(CGRect(x: CGFloat(x) - spacing * 0.27, y: CGFloat(a), width: spacing * 0.54, height: CGFloat(b - a)))
                }
            }
        case .waves:
            var bands = mask
            for y in 0..<n {
                for x in 0..<n where bands[y * n + x] {
                    let phase = CGFloat(y) + sin(CGFloat(x) / 32) * spacing * 0.6
                    bands[y * n + x] = phase.truncatingRemainder(dividingBy: spacing * 1.7) < spacing * 0.65
                }
            }
            filled(contours(bands), tolerance: 1, smooth: true)
        case .pencil:
            // Integer hashing keeps the texture stable while changing colour/exporting.
            func noise(_ x: Int, _ y: Int, _ salt: Int) -> CGFloat {
                let h = UInt64(x &* 374761393) ^ UInt64(y &* 668265263) ^ UInt64(salt &* 1274126177)
                return CGFloat((h ^ (h >> 13)) & 1023) / 1023
            }
            let step = max(2, Int(spacing / 3))
            for y in stride(from: 0, to: n, by: step) {
                for x in stride(from: 0, to: n, by: step) where mask[y * n + x] {
                    let px = CGFloat(x) + noise(x, y, 1) * CGFloat(step)
                    let py = CGFloat(y) + noise(x, y, 2) * CGFloat(step)
                    let length = spacing * (0.6 + noise(x, y, 3))
                    var points = [CGPoint(x: px, y: py)]
                    for t in 1...8 {
                        let xx = px + CGFloat(t) / 8 * length * 0.35
                        let yy = py - CGFloat(t) / 8 * length
                        if !inside(xx, yy) { break }
                        points.append(CGPoint(x: xx, y: yy))
                    }
                    drawing.line(points, width: max(0.3, stroke * 0.3), opacity: 0.4 + noise(x, y, 4) * 0.5)
                }
            }
        case .geometry:
            // Rounded, alternating modules fitted to broad silhouette slices.
            let step = max(12, Int(spacing * 4))
            for y in stride(from: 0, to: n, by: step) {
                let middle = min(n - 1, y + step / 2)
                for (a, b) in runs(middle, vertical: false) {
                    let w = CGFloat(b - a), h = CGFloat(min(step, n - y))
                    let r = CGRect(x: a, y: y, width: Int(w), height: Int(h))
                    let path = CGPath(roundedRect: r, cornerWidth: min(w, h) * 0.45, cornerHeight: min(w, h) * 0.45, transform: nil)
                    drawing.marks.append(Mark(path: path, fill: true))
                }
            }
        case .sketch:
            let cell = max(8, Int(spacing * 2))
            var block = [Bool](repeating: false, count: n * n)
            for y in stride(from: 0, to: n, by: cell) {
                for x in stride(from: 0, to: n, by: cell) {
                    if coverage(CGFloat(x + cell / 2), CGFloat(y + cell / 2), CGFloat(cell)) >= 0.4 {
                        for yy in y..<min(n, y + cell) {
                            for xx in x..<min(n, x + cell) { block[yy * n + xx] = true }
                        }
                    }
                }
            }
            for loop in contours(block) {
                let points = reduced(loop, 1)
                for pass in 0..<4 {
                    let jittered = points.enumerated().map { i, v in
                        CGPoint(x: v.x + sin(Double(i * 3 + pass * 7)) * 2.2,
                                y: v.y + cos(Double(i * 5 + pass * 3)) * 2.2)
                    }
                    drawing.line(jittered, width: max(0.35, stroke * 0.22), closed: true, smooth: true, opacity: 0.55)
                }
            }
        case .candles, .diagonal, .bricks, .threads:
            break // The continuous-tone renderer above handles these styles.
        }
        return drawing
    }
}

// The photographic styles sample a continuous darkness field. Binarising the
// image first would erase exactly the midtones these screens need to reproduce.
struct ToneField {
    let darkness: [Double] // premultiplied by coverage for correct interpolation
    let coverage: [Double]
    let bounds: CGRect
    let n = Raster.n

    init(raster: Raster, parameters p: Parameters, shape: [Bool], ink: [Bool]) {
        bounds = raster.contentRect
        var d = [Double](repeating: 0, count: Raster.n * Raster.n)
        var a = d
        for i in d.indices {
            let alpha = Double(raster.rgba[i * 4 + 3]) / 255
            guard alpha > 0 else { continue }
            if p.maskMode == 1 && !shape[i] { continue }
            if p.maskMode == 2 && !ink[i] { continue }
            let luma = (0.2126 * Double(raster.rgba[i * 4]) + 0.7152 * Double(raster.rgba[i * 4 + 1]) + 0.0722 * Double(raster.rgba[i * 4 + 2])) / (255 * alpha)
            let adjusted = min(1, max(0, (luma - 0.5) * p.toneContrast + 0.5))
            let tone = pow(1 - adjusted, 1 / p.toneDensity)
            d[i] = tone * alpha
            a[i] = alpha
        }
        darkness = d; coverage = a
    }

    func sample(_ point: CGPoint) -> (tone: Double, alpha: Double) {
        // Pixel centres are at half-integer positions in vector coordinates.
        let x = Double(point.x) - 0.5, y = Double(point.y) - 0.5
        let ix = Int(floor(x)), iy = Int(floor(y))
        let fx = x - Double(ix), fy = y - Double(iy)
        var d = 0.0, a = 0.0
        for dy in 0...1 {
            for dx in 0...1 {
                let xx = ix + dx, yy = iy + dy
                guard xx >= 0, yy >= 0, xx < n, yy < n else { continue }
                let w = (dx == 0 ? 1 - fx : fx) * (dy == 0 ? 1 - fy : fy)
                let i = yy * n + xx
                d += darkness[i] * w; a += coverage[i] * w
            }
        }
        return (a > 0.0001 ? d / a : 0, a)
    }

    func drawing(_ style: Style, _ p: Parameters) -> Drawing {
        var result = Drawing()
        let pitch = max(2, CGFloat(p.spacing) * 0.65)
        let base: Double = style == .bricks ? -90 : (style == .diagonal ? -16 : 0)
        let angle = CGFloat((base + p.screenAngle) * .pi / 180)
        let cs = cos(angle), sn = sin(angle)
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let reach = hypot(bounds.width, bounds.height) / 2 + pitch * 4
        func world(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: centre.x + u * cs - v * sn, y: centre.y + u * sn + v * cs)
        }
        func addPolygon(_ local: [CGPoint]) {
            // Clip every primitive, including rotated ones, to the source frame.
            // Preview and both exports therefore share exactly the same edges.
            let points = clipPolygon(local.map { world($0.x, $0.y) }, to: bounds)
            if points.count >= 3 { result.line(points, width: 0, closed: true, filled: true) }
        }
        func rectangle(u: CGFloat, v: CGFloat, width: CGFloat, length: CGFloat) {
            let w = width / 2, h = length / 2
            addPolygon([CGPoint(x: u - w, y: v - h), CGPoint(x: u + w, y: v - h),
                        CGPoint(x: u + w, y: v + h), CGPoint(x: u - w, y: v + h)])
        }
        func average(_ u: CGFloat, _ v: CGFloat, width: CGFloat, length: CGFloat) -> (tone: CGFloat, alpha: Double) {
            var ink = 0.0, alpha = 0.0
            for dv in [-0.32, 0.0, 0.32] {
                for du in [-0.32, 0.0, 0.32] {
                    let s = sample(world(u + du * width, v + dv * length))
                    ink += s.tone * s.alpha; alpha += s.alpha
                }
            }
            return (CGFloat(alpha > 0 ? ink / alpha : 0), alpha / 9)
        }
        let weight = CGFloat(p.stroke / 2.4)
        let columnCount = Int(ceil(reach / pitch))

        if style == .threads {
            // Two sides of one long filled ribbon. Its width follows brightness
            // at every sample, rather than breaking the image into rectangles.
            for column in -columnCount...columnCount {
                let u = CGFloat(column) * pitch
                var left: [CGPoint] = [], right: [CGPoint] = []
                func flush() {
                    if left.count >= 2 { addPolygon(left + right.reversed()) }
                    left = []; right = []
                }
                for v in stride(from: -reach, through: reach, by: CGFloat(1.5)) {
                    let s = average(u, v, width: pitch * 0.7, length: 2)
                    if s.alpha < 0.5 { flush(); continue }
                    let width = min(pitch * 0.97, pitch * (0.045 + 0.925 * s.tone) * weight)
                    left.append(CGPoint(x: u - width / 2, y: v))
                    right.append(CGPoint(x: u + width / 2, y: v))
                }
                flush()
            }
            return result
        }

        let alongPitch = pitch * (style == .bricks ? 2.7 : (style == .candles ? 2.25 : 1.8))
        let rowCount = Int(ceil(reach / alongPitch)) + 1
        for column in -columnCount...columnCount {
            let u = CGFloat(column) * pitch
            let stagger = column.isMultiple(of: 2) ? CGFloat.zero : alongPitch / 2
            for row in -rowCount...rowCount {
                let v = CGFloat(row) * alongPitch + stagger
                guard bounds.contains(world(u, v)) else { continue }
                let s = average(u, v, width: pitch * 0.8, length: alongPitch * 0.8)
                guard s.alpha >= 0.5 else { continue }
                let t = s.tone
                if style == .candles {
                    guard t > 0.018 else { continue }
                    let bodyWidth = min(pitch * 0.97, pitch * (0.13 + 0.74 * pow(t, 0.8)) * weight)
                    let bodyLength = alongPitch * (0.1 + 0.88 * pow(t, 0.85))
                    // A thin full-length wick and a shorter, wider body.
                    rectangle(u: u, v: v, width: max(0.24, pitch * 0.075 * weight), length: alongPitch * 0.99)
                    rectangle(u: u, v: v, width: bodyWidth, length: bodyLength)
                } else if style == .diagonal {
                    guard t > 0.018 else { continue }
                    let width = min(pitch * 1.04, pitch * (0.08 + 0.96 * pow(t, 0.8)) * weight)
                    let length = alongPitch * (0.12 + 0.88 * pow(t, 0.75))
                    rectangle(u: u, v: v, width: width, length: length)
                } else {
                    // Even paper-white areas retain the tiny rhythmic dashes
                    // visible in the reference; dark bricks nearly meet.
                    let width = min(pitch * 0.98, pitch * (0.065 + 0.88 * t) * weight)
                    let length = alongPitch * (0.065 + 0.925 * pow(t, 0.7))
                    rectangle(u: u, v: v, width: width, length: length)
                }
            }
        }
        return result
    }
}

// Sutherland–Hodgman clipping works for both small rotated rectangles and the
// long variable-width ribbons, and keeps the resulting SVG entirely vector.
func clipPolygon(_ polygon: [CGPoint], to rect: CGRect) -> [CGPoint] {
    var points = polygon
    for edge in 0..<4 {
        guard !points.isEmpty else { break }
        func coordinate(_ p: CGPoint) -> CGFloat { edge < 2 ? p.x : p.y }
        let boundary = [rect.minX, rect.maxX, rect.minY, rect.maxY][edge]
        func inside(_ p: CGPoint) -> Bool { edge.isMultiple(of: 2) ? coordinate(p) >= boundary : coordinate(p) <= boundary }
        func intersection(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let delta = coordinate(b) - coordinate(a)
            let t = delta == 0 ? 0 : (boundary - coordinate(a)) / delta
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        var clipped: [CGPoint] = []
        var previous = points[points.count - 1]
        for point in points {
            if inside(point) {
                if !inside(previous) { clipped.append(intersection(previous, point)) }
                clipped.append(point)
            } else if inside(previous) { clipped.append(intersection(previous, point)) }
            previous = point
        }
        points = clipped
    }
    return points
}
