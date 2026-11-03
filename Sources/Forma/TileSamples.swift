import SwiftUI

struct TileDetail: Codable, Equatable {
    var points: [CGPoint]
    var radius: Double?
    var region: Int?
    var valid: Bool {
        !points.isEmpty && points.count <= 64 && points.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) < 600 && abs($0.y) < 600 }
        && (radius == nil || (radius!.isFinite && (1...12).contains(radius!)))
        && (region == nil || (0...1).contains(region!))
    }
}

enum TileSample: String, CaseIterable, Identifiable {
    case fish, birds, fishBird, leaves, waves, lock, zigzag, twoFigures
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fish: return "Рыбки"
        case .birds: return "Птицы"
        case .fishBird: return "Рыба и птица"
        case .twoFigures: return "Две фигуры"
        case .leaves: return "Листья"
        case .waves: return "Волны"
        case .lock: return "Замок"
        case .zigzag: return "Зигзаг"
        }
    }
    var subtitle: String {
        switch self {
        case .fishBird: return "Общая граница · по референсу Эшера"
        case .twoFigures: return "Простой пример разделения блока"
        case .fish, .birds: return "Фигурная плитка с деталями"
        case .leaves: return "Ромбическая основа и прожилки"
        default: return "Геометрический образец"
        }
    }
    var design: TileDesign {
        var tile = TileDesign(self == .lock || self == .zigzag || self == .fishBird || self == .twoFigures ? .hexagon : .quadrilateral)
        func knots(_ pairs: [(Double, Double)]) -> [TileKnot] { pairs.map { TileKnot(t: $0.0, offset: $0.1) } }
        func points(_ pairs: [(Double, Double)]) -> [CGPoint] { pairs.map { CGPoint(x: $0.0, y: $0.1) } }
        switch self {
        case .fish:
            tile.vertices = points([(-120,-80),(120,-80),(120,80),(-120,80)])
            tile.profiles[0] = knots([(0.25,0),(0.42,-32),(0.55,0),(0.78,8)])
            tile.profiles[1] = knots([(0.15,0),(0.28,-22),(0.43,-38),(0.5,-20),(0.57,-38),(0.72,-22),(0.85,0)])
            tile.details = [TileDetail(points: points([(105,-25)]), radius: 6),
                            TileDetail(points: points([(-25,10),(8,-10),(8,25)]))]
        case .birds:
            tile.vertices = points([(-120,-60),(100,-90),(120,60),(-100,90)])
            tile.setEdgeCurve(0,points([(-120,-60),(-85,-40),(-58,-82),(-25,-122),(-32,-75),(10,-65),(42,-85),(74,-83),(100,-90)]))
            tile.setEdgeCurve(1,points([(100,-90),(90,-72),(72,-61),(52,-56),(48,-44),(58,-35),(80,-36),(104,-51),(126,-47),(132,-35),(153,-25),(131,-21),(127,-5),(109,12),(110,27),(120,60)]))
            tile.details = [TileDetail(points:points([(120,-35)]),radius:4),
                            TileDetail(points:points([(-60,5),(-20,-45),(-10,-80)])),
                            TileDetail(points:points([(-49,14),(-8,-25),(30,-46)]))]
        case .fishBird:
            return TileDesign.fishBirdReference()
        case .twoFigures:
            tile.division = points([(30,-95),(55,-85),(50,-65),(10,-60),(-15,-70),(0,-45),
                                    (25,-25),(10,5),(40,35),(25,60),(-10,85)])
            tile.profiles[0] = knots([(0.35,-8),(0.65,8)])
            tile.profiles[2] = knots([(0.35,-18),(0.65,-18)])
            tile.details = [TileDetail(points: points([(64,-54)]), radius: 5, region: 0),
                            TileDetail(points: points([(20,-84)]), radius: 5, region: 1),
                            TileDetail(points: points([(43,-8),(78,24),(35,40)]), region: 0),
                            TileDetail(points: points([(-70,26),(-25,5),(-45,48)]), region: 1)]
            tile.palette = 2
        case .leaves:
            tile.vertices = points([(0,-145),(75,0),(0,145),(-75,0)])
            tile.profiles[0] = knots([(0.2,-8),(0.4,-14),(0.6,-14),(0.8,-8)])
            tile.profiles[1] = knots([(0.2,8),(0.4,14),(0.6,14),(0.8,8)])
            tile.palette = 3
            tile.details = [TileDetail(points: points([(0,-120),(0,115)])),
                            TileDetail(points: points([(-24,-45),(0,-15),(27,-48)])),
                            TileDetail(points: points([(-24,20),(0,50),(27,17)]))]
        case .waves:
            tile.vertices = points([(-110,-70),(110,-70),(110,70),(-110,70)])
            tile.profiles[0] = knots([(0.15,18),(0.3,28),(0.5,0),(0.7,-28),(0.85,-18)])
            tile.profiles[1] = knots([(0.25,-12),(0.5,0),(0.75,12)])
        case .lock:
            tile.profiles[0] = knots([(0.25,0),(0.35,-28),(0.65,-28),(0.75,0)])
            tile.palette = 1
        case .zigzag:
            tile.profiles[0] = knots([(0.3,-22),(0.7,22)])
            tile.profiles[1] = knots([(0.35,18),(0.65,-18)])
        }
        return tile
    }
}

extension TileDesign {
    mutating func setEdgeCurve(_ edge: Int, _ line: [CGPoint]) {
        let a = vertices[edge], d = tileSubtract(vertices[edge+1],a), length = hypot(d.x,d.y)
        profiles[edge] = line.dropFirst().dropLast().map { p in
            let delta = tileSubtract(p,a)
            return TileKnot(t:tileDot(delta,d)/(length*length),offset:tileCross(d,delta)/length)
        }
    }

    static func fishBirdReference() -> TileDesign {
        // Six common junctions: opposite edge pairs match exactly by translation.
        // The fourth edge of the bird is the interior fish/bird boundary.
        func p(_ x: Double,_ y: Double) -> CGPoint { CGPoint(x:x,y:y) }
        let b = p(130,-58), u = p(202,0), v = p(72,58), centre = p(217.75,125.25)
        let wing = p(218.5,87.5), tail = p(217,163), beak = p(88.5,145.5), shoulder = p(145,105)
        let belly = [tail,p(198,165),p(181,173),p(160,173),p(145,168),p(128,160),p(116,151),p(105,147),beak]
        let neck = [beak,p(94,140),p(97,130),p(109,130),p(121,136),p(133,140),p(144,140),p(137,134),p(130,130),p(128,125),p(130,120),p(138,113),shoulder]
        let feathers = [shoulder,p(157,101),p(171,95),p(184,85),p(184,99),p(201,95),p(212,88),wing]
        let shared = [wing,p(212,105),p(200,116),p(184,130),p(181,134),p(190,137),p(202,142),p(214,150),tail]
        func local(_ line: [CGPoint]) -> [CGPoint] { line.map { tileSubtract($0,centre) } }
        var tile = TileDesign(.hexagon)
        tile.vertices = local([wing,tileAdd(tail,b),tileAdd(wing,v),tail,beak,shoulder])
        tile.setEdgeCurve(0,local(belly.reversed().map { tileAdd($0,b) }))
        tile.setEdgeCurve(1,local(neck.reversed().map { tileAdd($0,u) }))
        tile.setEdgeCurve(2,local(feathers.reversed().map { tileAdd($0,v) }))
        tile.division = Array(local(shared).dropFirst().dropLast())
        tile.palette = 1; tile.seam = 0.9
        func eye(_ x: Double,_ y: Double,_ region: Int) -> TileDetail {
            TileDetail(points:local([p(x,y)]),radius:3.1,region:region)
        }
        func ink(_ coordinates: [(Double,Double)],_ region: Int) -> TileDetail {
            TileDetail(points:local(coordinates.map { p($0.0,$0.1) }),region:region)
        }
        tile.details = [eye(102,136,1),eye(207,123,0),
            ink([(90,144),(102,141),(110,141)],1),
            ink([(136,149),(151,136),(165,119),(181,104)],1),
            ink([(150,156),(165,145),(179,134)],1),
            ink([(165,161),(181,151),(194,145)],1),
            ink([(213,113),(221,117),(224,125),(221,136),(215,143),(205,147)],0),
            ink([(186,136),(197,140),(212,139)],0),
            ink([(245,127),(258,119),(270,121),(264,133),(250,134),(245,127)],0)]
        return tile
    }
    func regionFill(_ region: Int, i: Int, j: Int) -> NSColor {
        guard division != nil else { return fill(i,j) }
        let colours: [[NSColor]] = [
            [NSColor(srgbRed: 0.22, green: 0.3, blue: 0.49, alpha: 1), NSColor(srgbRed: 0.85, green: 0.9, blue: 0.98, alpha: 1)],
            [NSColor(srgbRed: 0.98, green: 0.93, blue: 0.82, alpha: 1), NSColor(srgbRed: 0.76, green: 0.34, blue: 0.23, alpha: 1)],
            [.init(white: 0.16, alpha: 1), .init(white: 0.96, alpha: 1)],
            [NSColor(srgbRed: 0.24, green: 0.39, blue: 0.29, alpha: 1), NSColor(srgbRed: 0.85, green: 0.92, blue: 0.75, alpha: 1)] ]
        return colours[palette][region]
    }

    func paint(in context: inout GraphicsContext, i: Int, j: Int) {
        for (index, polygon) in regions.enumerated() {
            context.fill(Path(tilePath(polygon)), with: .color(Color(nsColor: regionFill(index, i:i, j:j))))
        }
        if seam > 0 {
            let stroke = StrokeStyle(lineWidth: seam, lineJoin: .round)
            context.stroke(Path(path), with: .color(.black.opacity(0.55)), style: stroke)
            if division != nil { context.stroke(Path(tileOpenPath(divisionLine)), with: .color(.black.opacity(0.55)), style: stroke) }
        }
        guard showDetails != false else { return }
        for detail in details ?? [] {
            var ink = context
            let clipping = detail.region.flatMap { regions.indices.contains($0) ? regions[$0] : nil } ?? polygon
            ink.clip(to: Path(tilePath(clipping)))
            if let r = detail.radius, let p = detail.points.first {
                ink.fill(Path(ellipseIn: CGRect(x: p.x-r, y: p.y-r, width: r*2, height: r*2)), with: .color(.white))
                ink.fill(Path(ellipseIn: CGRect(x: p.x-r*0.55, y: p.y-r*0.55, width: r*1.1, height: r*1.1)), with: .color(.black))
            } else {
                ink.stroke(Path(tileOpenPath(detail.points)), with: .color(Color(white:0.35)),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }

    func paint(in context: CGContext, i: Int, j: Int) {
        for (index, points) in regions.enumerated() {
            context.setFillColor(regionFill(index,i:i,j:j).cgColor)
            context.addPath(tilePath(points)); context.fillPath()
        }
        context.setLineWidth(seam); context.setLineJoin(.round); context.setStrokeColor(NSColor.darkGray.cgColor)
        if seam > 0 {
            context.addPath(path); context.strokePath()
            if division != nil { context.addPath(tileOpenPath(divisionLine)); context.strokePath() }
        }
        guard showDetails != false else { return }
        for detail in details ?? [] {
            context.saveGState()
            let clipping = detail.region.flatMap { regions.indices.contains($0) ? regions[$0] : nil } ?? polygon
            context.addPath(tilePath(clipping)); context.clip()
            if let r = detail.radius, let p = detail.points.first {
                context.setFillColor(NSColor.white.cgColor)
                context.fillEllipse(in: CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2))
                context.setFillColor(NSColor.black.cgColor)
                context.fillEllipse(in: CGRect(x:p.x-r*0.55,y:p.y-r*0.55,width:r*1.1,height:r*1.1))
            } else {
                context.setLineWidth(1.8); context.setLineCap(.round); context.setStrokeColor(NSColor(white:0.35,alpha:1).cgColor)
                context.addPath(tileOpenPath(detail.points)); context.strokePath()
            }
            context.restoreGState()
        }
    }
}

func tileSVGPath(_ points: [CGPoint], closed: Bool = true) -> String {
    "M" + points.map { "\($0.x),\($0.y)" }.joined(separator: " L") + (closed ? " Z" : "")
}

func tileOpenPath(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    if let first = points.first { path.move(to: first); points.dropFirst().forEach { path.addLine(to: $0) } }
    return path
}

func tileNearest(_ point: CGPoint, on line: [CGPoint]) -> (segment: Int, point: CGPoint, distance: Double)? {
    guard line.count >= 2 else { return nil }
    return (0..<(line.count-1)).map { i -> (Int, CGPoint, Double) in
        let a = line[i], d = tileSubtract(line[i+1],a), length = tileDot(d,d)
        let t = length > 1e-9 ? max(0,min(1,tileDot(tileSubtract(point,a),d)/length)) : 0
        let p = tileAdd(a,tileScale(d,t))
        return (i,p,Double(hypot(point.x-p.x,point.y-p.y)))
    }.min { $0.2 < $1.2 }
}

@MainActor
extension AppModel {
    func selectTileSample(_ sample: TileSample) {
        let design = sample.design
        guard design.valid else { error = "Не удалось загрузить образец"; return }
        edit("Загрузить образец мощения") { tile = design; mode = .tiling }
    }
    func setTileDivision(_ enabled: Bool) {
        guard (tile.division != nil) != enabled else { return }
        var next = tile
        next.division = enabled ? [] : nil
        if !enabled { next.details = next.details?.filter { $0.region == nil } }
        if next.valid { edit("Разделить блок на фигуры") { tile = next } }
    }
    func removeTileDivisionPoint(_ index: Int) {
        var next = tile
        next.division?.remove(at: index)
        if next.valid { edit("Удалить точку общей границы") { tile = next } }
    }
}
