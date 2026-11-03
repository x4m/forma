import AppKit

enum TileKind: Int, CaseIterable, Codable, Identifiable {
    case quadrilateral = 4, hexagon = 6
    var id: Int { rawValue }
    var title: String { self == .quadrilateral ? "Четырёхугольник" : "Шестиугольник" }
}

struct TileKnot: Codable, Equatable { var t: Double; var offset: Double }
struct TileHandle: Identifiable {
    enum Kind { case vertex(Int), knot(Int, Int), division(Int) }
    var id: String
    var point: CGPoint
    var kind: Kind
}

// Opposite edges share a profile by TRANSLATION, with reversed traversal.
// A protrusion on one edge is therefore the matching recess on the other.
struct TileDesign: Codable, Equatable {
    var kind: TileKind
    var vertices: [CGPoint]
    var profiles: [[TileKnot]]
    var palette = 0
    var seam: Double = 1.4
    // Optional fields keep projects made before subdivisions readable.
    var division: [CGPoint]?
    var details: [TileDetail]?
    var showDetails: Bool?

    init(_ kind: TileKind = .hexagon) {
        self.kind = kind
        vertices = kind == .quadrilateral
            ? [CGPoint(x: -100, y: -100), CGPoint(x: 100, y: -100), CGPoint(x: 100, y: 100), CGPoint(x: -100, y: 100)]
            : [CGPoint(x: 0, y: -120), CGPoint(x: 104, y: -60), CGPoint(x: 104, y: 60),
               CGPoint(x: 0, y: 120), CGPoint(x: -104, y: 60), CGPoint(x: -104, y: -60)]
        profiles = Array(repeating: [], count: kind.rawValue / 2)
    }

    var half: Int { kind.rawValue / 2 }
    var u: CGPoint { tileAdd(vertices[0], vertices[1]) }
    var v: CGPoint { tileAdd(vertices[1], vertices[2]) }
    var determinant: Double { tileCross(u, v) }
    func origin(_ i: Int, _ j: Int) -> CGPoint { tileAdd(tileScale(u, Double(i)), tileScale(v, Double(j))) }
    func coordinates(_ p: CGPoint) -> CGPoint {
        CGPoint(x: tileCross(p, v) / determinant, y: tileCross(u, p) / determinant)
    }

    func edge(_ index: Int) -> [CGPoint] {
        let e = index % half, a = vertices[e], b = vertices[e + 1]
        let d = tileSubtract(b, a), length = hypot(d.x, d.y)
        let normal = CGPoint(x: -d.y / length, y: d.x / length)
        let line = [a] + profiles[e].map { tileAdd(tileAdd(a, tileScale(d, $0.t)), tileScale(normal, $0.offset)) } + [b]
        if index < half { return line }
        let shift = tileAdd(a, b)
        return line.reversed().map { tileSubtract($0, shift) }
    }

    var polygon: [CGPoint] { (0..<kind.rawValue).flatMap { Array(edge($0).dropLast()) } }
    var path: CGPath { tilePath(polygon) }
    var bounds: CGRect { path.boundingBoxOfPath }
    var divisionLine: [CGPoint] { [vertices[0]] + (division ?? []) + [vertices[half]] }
    var regions: [[CGPoint]] {
        guard let division else { return [polygon] }
        let first = (0..<half).flatMap { Array(edge($0).dropLast()) } + [vertices[half]]
        let second = (half..<kind.rawValue).flatMap { Array(edge($0).dropLast()) } + [vertices[0]]
        return [first + division.reversed(), second + division]
    }
    var handles: [TileHandle] {
        var result = vertices.indices.map { TileHandle(id: "v\($0)", point: vertices[$0], kind: .vertex($0)) }
        for e in 0..<kind.rawValue {
            let line = edge(e)
            for j in profiles[e % half].indices {
                let index = e < half ? j + 1 : line.count - 2 - j
                result.append(TileHandle(id: "e\(e)-\(j)", point: line[index], kind: .knot(e, j)))
            }
        }
        for (i, point) in (division ?? []).enumerated() {
            result.append(TileHandle(id: "division\(i)", point: point, kind: .division(i)))
        }
        return result
    }

    func moving(_ handle: TileHandle.Kind, to point: CGPoint) -> Self? {
        guard point.x.isFinite && point.y.isFinite else { return nil }
        var next = self
        switch handle {
        case .division(let index): next.division?[index] = point
        case .vertex(let index):
            let i = index % half, p = index < half ? point : tileScale(point, -1)
            next.vertices[i] = p; next.vertices[i + half] = tileScale(p, -1)
        case .knot(let edge, let index):
            let e = edge % half, a = vertices[e], b = vertices[e + 1], d = tileSubtract(b, a)
            let p = edge < half ? point : tileAdd(point, tileAdd(a, b))
            let relative = tileSubtract(p, a), length = hypot(d.x, d.y)
            next.profiles[e][index] = TileKnot(t: tileDot(relative, d) / (length * length),
                                              offset: tileCross(d, relative) / length)
        }
        return next.valid ? next : nil
    }

    func inserting(at point: CGPoint, tolerance: Double) -> Self? {
        if let division, division.count < 32,
           let hit = tileNearest(point, on: divisionLine), hit.distance < tolerance,
           !divisionLine.contains(where: { hypot($0.x - hit.point.x, $0.y - hit.point.y) < 3 }) {
            var next = self
            next.division?.insert(hit.point, at: hit.segment)
            return next.valid ? next : nil
        }
        var nearest: (edge: Int, segment: Int, point: CGPoint, distance: Double)?
        for e in 0..<kind.rawValue where profiles[e % half].count < 32 {
            let line = edge(e)
            for i in 0..<(line.count - 1) {
                let a = line[i], d = tileSubtract(line[i + 1], a)
                let t = max(0, min(1, tileDot(tileSubtract(point, a), d) / tileDot(d, d)))
                let p = tileAdd(a, tileScale(d, t)), distance = hypot(p.x - point.x, p.y - point.y)
                if distance < (nearest?.distance ?? tolerance) { nearest = (e, i, p, Double(distance)) }
            }
        }
        guard let hit = nearest else { return nil }
        let e = hit.edge % half, a = vertices[e], b = vertices[e + 1], d = tileSubtract(b, a)
        let p = hit.edge < half ? hit.point : tileAdd(hit.point, tileAdd(a, b))
        let relative = tileSubtract(p, a), length = hypot(d.x, d.y)
        let knot = TileKnot(t: tileDot(relative, d) / (length * length), offset: tileCross(d, relative) / length)
        guard !edge(hit.edge).contains(where: { tileClose($0,hit.point) || hypot($0.x-hit.point.x,$0.y-hit.point.y) < 2 }) else { return nil }
        var next = self
        let insertion = hit.edge < half ? hit.segment : profiles[e].count - hit.segment
        next.profiles[e].insert(knot,at:insertion)
        return next.valid ? next : nil
    }

    func cells(in rect: CGRect) -> [(Int, Int)] {
        let b = bounds
        let offsets = CGRect(x: rect.minX - b.maxX, y: rect.minY - b.maxY,
                             width: rect.width + b.width, height: rect.height + b.height)
        let p = [CGPoint(x: offsets.minX, y: offsets.minY), CGPoint(x: offsets.maxX, y: offsets.minY),
                 CGPoint(x: offsets.minX, y: offsets.maxY), CGPoint(x: offsets.maxX, y: offsets.maxY)].map(coordinates)
        guard p.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
        let x0 = Int(floor(p.map(\.x).min()!)), x1 = Int(ceil(p.map(\.x).max()!))
        guard x1 - x0 < 10_000 else { return [] }
        var result: [(Int, Int)] = []
        // Intersect each lattice row with the viewport. A rectangular loop in
        // lattice coordinates would waste many cells when the basis is skewed.
        for i in x0...x1 {
            let base = tileScale(u, Double(i))
            var low = -Double.infinity, high = Double.infinity
            for (start, step, minimum, maximum) in [(base.x, v.x, offsets.minX, offsets.maxX),
                                                    (base.y, v.y, offsets.minY, offsets.maxY)] {
                if abs(step) < 1e-8 {
                    if start < minimum - 1e-8 || start > maximum + 1e-8 { high = -Double.infinity }
                } else {
                    let a = (minimum - start) / step, c = (maximum - start) / step
                    low = max(low, Double(min(a,c))); high = min(high, Double(max(a,c)))
                }
            }
            guard low.isFinite, high.isFinite, low <= high + 1e-8 else { continue }
            let first = Int(ceil(low - 1e-8)), last = Int(floor(high + 1e-8))
            guard first <= last else { continue }
            guard last - first < 20_000, result.count + last - first + 1 < 20_000 else { return [] }
            for j in first...last { result.append((i,j)) }
        }
        return result
    }

    var valid: Bool {
        guard vertices.count == kind.rawValue, profiles.count == half, (0...3).contains(palette),
              seam.isFinite, (0...8).contains(seam), vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 260 && abs($0.y) <= 260 }) else { return false }
        for i in 0..<half {
            guard hypot(vertices[i].x + vertices[i + half].x, vertices[i].y + vertices[i + half].y) < 1e-6,
                  profiles[i].count <= 32 else { return false }
            for knot in profiles[i] {
                guard knot.t.isFinite, knot.offset.isFinite, (-0.5...1.5).contains(knot.t),
                      abs(knot.offset) <= 100 else { return false }
            }
        }
        for i in vertices.indices {
            let a = vertices[i], b = vertices[(i + 1) % vertices.count], c = vertices[(i + 2) % vertices.count]
            guard tileCross(tileSubtract(b, a), tileSubtract(c, b)) > 800,
                  hypot(b.x - a.x, b.y - a.y) > 40 else { return false }
        }
        guard determinant > 8000 else { return false }
        let p = polygon
        guard abs(tileArea(p) - determinant) < 1e-5 else { return false }
        guard p.indices.allSatisfy({ hypot(p[$0].x-p[($0+1)%p.count].x,p[$0].y-p[($0+1)%p.count].y) > 1e-5 }) else { return false }
        // Reject self-crossing and touching non-adjacent edges before triangulation.
        for i in p.indices {
            for j in p.indices where j > i + 1 && !(i == 0 && j == p.count - 1) {
                if tileSegmentsMeet(p[i], p[(i + 1) % p.count], p[j], p[(j + 1) % p.count]) { return false }
            }
        }
        guard let triangles = tileTriangles(p) else { return false }
        if let details {
            guard details.count <= 32, details.allSatisfy(\.valid) else { return false }
        }
        if let division {
            guard division.count <= 32, division.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) < 600 && abs($0.y) < 600 }) else { return false }
            let line = divisionLine
            for i in 0..<(line.count - 1) {
                let a = line[i], b = line[i + 1]
                guard hypot(b.x - a.x, b.y - a.y) > 2,
                      path.contains(tileScale(tileAdd(a,b), 0.5)) else { return false }
                for j in 0..<(line.count - 1) where j > i + 1 {
                    if tileSegmentsMeet(a,b,line[j],line[j+1]) { return false }
                }
                for j in p.indices {
                    let c = p[j], d = p[(j + 1) % p.count]
                    if tileSegmentsMeet(a,b,c,d) {
                        let atStart = i == 0 && (tileClose(c,a) || tileClose(d,a))
                        let atEnd = i == line.count - 2 && (tileClose(c,b) || tileClose(d,b))
                        guard (atStart || atEnd), abs(tileCross(tileSubtract(b,a), tileSubtract(d,c))) > 1e-6 else { return false }
                    }
                }
            }
            guard regions.allSatisfy({ tileArea($0) > 400 && tileTriangles($0) != nil }) else { return false }
        }
        // Matching edges alone do not prevent a very deep tab hitting a different
        // neighbour. Test positive intersection AREA, allowing shared seams.
        let neighbours = cells(in: bounds)
        guard !neighbours.isEmpty else { return false }
        let triangleBoxes = triangles.map { tilePath($0).boundingBoxOfPath }
        for (i, j) in neighbours where i != 0 || j != 0 {
            let o = origin(i, j), other = triangles.map { $0.map { tileAdd($0, o) } }
            for (index,a) in triangles.enumerated() {
                for (indexB,b) in other.enumerated() where triangleBoxes[index].intersects(triangleBoxes[indexB].offsetBy(dx:o.x,dy:o.y)) {
                    if abs(tileArea(tileClip(a, by: b))) > 1e-5 { return false }
                }
            }
        }
        return true
    }

    func fill(_ i: Int, _ j: Int) -> NSColor {
        let choices: [[NSColor]] = [
            [NSColor(srgbRed: 0.78, green: 0.82, blue: 0.92, alpha: 1), NSColor(srgbRed: 0.9, green: 0.91, blue: 0.96, alpha: 1), NSColor(srgbRed: 0.65, green: 0.71, blue: 0.86, alpha: 1)],
            [NSColor(srgbRed: 0.82, green: 0.56, blue: 0.4, alpha: 1), NSColor(srgbRed: 0.94, green: 0.79, blue: 0.61, alpha: 1), NSColor(srgbRed: 0.72, green: 0.4, blue: 0.29, alpha: 1)],
            [.init(white: 0.96, alpha: 1), .init(white: 0.83, alpha: 1), .init(white: 0.65, alpha: 1)],
            [NSColor(srgbRed: 0.63, green: 0.74, blue: 0.55, alpha: 1), NSColor(srgbRed: 0.84, green: 0.9, blue: 0.74, alpha: 1), NSColor(srgbRed: 0.45, green: 0.6, blue: 0.46, alpha: 1)] ]
        return choices[palette][((i - j) % 3 + 3) % 3]
    }
}

func tileAdd(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
func tileClose(_ a: CGPoint, _ b: CGPoint) -> Bool { hypot(a.x-b.x,a.y-b.y) < 1e-5 }
func tileSubtract(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
func tileScale(_ a: CGPoint, _ n: Double) -> CGPoint { CGPoint(x: a.x * n, y: a.y * n) }
func tileCross(_ a: CGPoint, _ b: CGPoint) -> Double { a.x * b.y - a.y * b.x }
func tileDot(_ a: CGPoint, _ b: CGPoint) -> Double { a.x * b.x + a.y * b.y }
func tileArea(_ p: [CGPoint]) -> Double {
    guard p.count >= 3 else { return 0 }
    return p.indices.reduce(0) { $0 + tileCross(p[$1], p[($1 + 1) % p.count]) } / 2
}
func tilePath(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    if let first = points.first { path.move(to: first); points.dropFirst().forEach { path.addLine(to: $0) }; path.closeSubpath() }
    return path
}
func tileSegmentsMeet(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
    let ab = tileSubtract(b, a), cd = tileSubtract(d, c)
    let denominator = tileCross(ab, cd)
    if abs(denominator) > 1e-8 {
        let t = tileCross(tileSubtract(c, a), cd) / denominator
        let s = tileCross(tileSubtract(c, a), ab) / denominator
        return (-1e-8...1.00000001).contains(t) && (-1e-8...1.00000001).contains(s)
    }
    guard abs(tileCross(ab, tileSubtract(c, a))) < 1e-7 else { return false }
    let length = tileDot(ab, ab)
    guard length > 1e-8 else { return true }
    let t = tileDot(tileSubtract(c, a), ab) / length, s = tileDot(tileSubtract(d, a), ab) / length
    return max(min(t, s), 0) <= min(max(t, s), 1) + 1e-8
}
func tileTriangles(_ input: [CGPoint]) -> [[CGPoint]]? {
    var p = input, output: [[CGPoint]] = []
    var changed = true
    while changed && p.count > 3 {
        changed = false
        for i in p.indices {
            let a = p[(i + p.count - 1) % p.count], b = p[i], c = p[(i + 1) % p.count]
            if abs(tileCross(tileSubtract(b, a), tileSubtract(c, b))) < 1e-7 {
                p.remove(at: i); changed = true; break
            }
        }
    }
    while p.count > 3 {
        var ear: Int?
        for i in p.indices {
            let previous = (i + p.count - 1) % p.count, next = (i + 1) % p.count
            let triangle = [p[previous], p[i], p[next]]
            guard tileArea(triangle) > 1e-7 else { continue }
            let occupied = p.indices.contains { j in
                j != previous && j != i && j != next && (0..<3).allSatisfy { k in
                    tileCross(tileSubtract(triangle[(k + 1) % 3], triangle[k]), tileSubtract(p[j], triangle[k])) >= -1e-8
                }
            }
            if !occupied { ear = i; output.append(triangle); break }
        }
        guard let i = ear else { return nil }
        p.remove(at: i)
    }
    if p.count == 3 { output.append(p) }
    return output
}
func tileClip(_ polygon: [CGPoint], by triangle: [CGPoint]) -> [CGPoint] {
    var output = polygon
    for i in 0..<3 {
        let a = triangle[i], edge = tileSubtract(triangle[(i + 1) % 3], a), input = output
        output = []
        guard let last = input.last else { break }
        var previous = last, d0 = tileCross(edge, tileSubtract(last, a))
        for point in input {
            let d1 = tileCross(edge, tileSubtract(point, a))
            if (d0 >= 0) != (d1 >= 0) {
                output.append(tileAdd(previous, tileScale(tileSubtract(point, previous), d0 / (d0 - d1))))
            }
            if d1 >= 0 { output.append(point) }
            previous = point; d0 = d1
        }
    }
    return output
}
