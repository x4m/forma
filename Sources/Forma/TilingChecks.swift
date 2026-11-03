import SwiftUI

extension Diagnostics {
    @MainActor
    static func tilingChecks(destination: URL?) throws {
        let model = AppModel(loadSample: false), manager = UndoManager()
        manager.groupsByEvent = false; model.useUndoManager(manager)
        model.mode = .tiling
        for kind in TileKind.allCases {
            model.setTileKind(kind)
            try require(model.tile.valid, "Default \(kind) does not tile")
            for preset in 0...2 {
                if preset == 0 { model.resetTile() } else { model.tilePreset(preset) }
                let design = model.tile
                try require(design.valid && (preset == 0 || !design.profiles[0].isEmpty), "Preset was rejected")
                try require(abs(tileArea(design.polygon) - design.determinant) < 1e-6, "Tile area differs from lattice cell area")
                for e in 0..<design.half {
                    let first = design.edge(e), opposite = design.edge(e + design.half).reversed()
                    let shift = tileAdd(design.vertices[e], design.vertices[e + 1])
                    for (a,b) in zip(first, opposite) {
                        try require(hypot(a.x - b.x - shift.x, a.y - b.y - shift.y) < 1e-6,
                                    "Paired sides do not match by translation")
                    }
                }
                // Sample the actual filled paths, across many lattice cells.
                let rect = CGRect(x: -480, y: -360, width: 960, height: 720)
                let cells = design.cells(in: rect), path = design.path
                for k in 0..<700 {
                    let x = -480 + (Double(k) * 0.61803398875).truncatingRemainder(dividingBy: 1) * 960
                    let y = -360 + (Double(k) * 0.41421356237 + 0.137).truncatingRemainder(dividingBy: 1) * 720
                    let p = CGPoint(x: x, y: y)
                    let count = cells.filter { i,j in path.contains(tileSubtract(p, design.origin(i,j))) }.count
                    try require(count == 1, "Gap or overlap at \(p), \(kind), preset \(preset): \(count) copies")
                }
                let document = TileDocument(tile: design)
                let data = try JSONEncoder().encode(document)
                let decoded = try JSONDecoder().decode(TileDocument.self, from: data)
                try decoded.validate()
                try require(decoded.tile == design, "Tile project round trip changed the design")
                for pattern in [false, true] {
                    try require(XMLParser(data: Data(design.svg(pattern: pattern).utf8)).parse(), "Invalid tiling SVG")
                }
                if let destination {
                    try Data(design.svg(pattern: true).utf8).write(to: destination.appendingPathComponent("tiling-\(kind.rawValue)-\(preset).svg"))
                    try design.png()!.write(to: destination.appendingPathComponent("tiling-\(kind.rawValue)-\(preset).png"))
                }
            }
            model.resetTile()
            let plain = model.editorState, design = model.tile
            let point = tileScale(tileAdd(design.vertices[0], design.vertices[1]), 0.5)
            model.insertTileKnot(at: point, tolerance: 3)
            try require(model.tile.profiles[0].count == 1, "Double-click insertion failed")
            let added = model.editorState, knot = model.tile.handles.first { if case .knot = $0.kind { return true }; return false }!
            model.beginContinuousEdit("Граница")
            let d = tileSubtract(design.vertices[1], design.vertices[0]), n = CGPoint(x: -d.y / hypot(d.x,d.y), y: d.x / hypot(d.x,d.y))
            for distance in 1...16 {
                try require(model.moveTileHandle(knot.kind, to: tileAdd(knot.point, tileScale(n, Double(distance)))), "A valid tab was rejected")
            }
            model.endContinuousEdit()
            let shaped = model.editorState
            manager.undo()
            try require(model.editorState == added, "Undo must cancel an entire boundary drag")
            manager.redo()
            try require(model.editorState == shaped, "Redo must restore the tab and its matching recess")
            model.removeTileKnot(0,0)
            try require(model.tile == plain.tile, "Deleting an edge knot must update the paired edge")
            manager.undo()
            try require(model.editorState == shaped, "Undo knot deletion failed")
            try require(model.tile.moving(.vertex(0), to: CGPoint(x: 900, y: 0)) == nil, "Invalid vertex must be rejected")
            try require(model.tile.moving(knot.kind, to: tileAdd(knot.point, tileScale(n, 300))) == nil,
                        "A crossing or excessively deep tab must be rejected")
            let moved = design.moving(.vertex(0), to: tileAdd(design.vertices[0], CGPoint(x: 10, y: 4)))
            try require(moved?.valid == true, "A valid base vertex edit was rejected")
            if let destination {
                let url = destination.appendingPathComponent("roundtrip-\(kind.rawValue).formatile")
                try JSONEncoder().encode(TileDocument(tile: model.tile)).write(to: url)
                model.resetTile(); model.load(url)
                try require(model.tile == shaped.tile && model.mode == .tiling, "Opening a tile project failed")
            }
        }
        var corrupt = TileDesign(); corrupt.vertices = []
        try require(!corrupt.valid, "Malformed tile arrays must be rejected safely")
        corrupt = TileDesign(); corrupt.profiles[0] = [TileKnot(t: .nan, offset: 0)]
        try require(!corrupt.valid, "Nonfinite tile coordinates must be rejected")
        corrupt = TileDesign(.quadrilateral)
        corrupt.vertices = [CGPoint(x: -50, y: -50), CGPoint(x: 50, y: -50), CGPoint(x: 50, y: 50), CGPoint(x: -50, y: 50)]
        corrupt.profiles = Array(repeating: [TileKnot(t: 0.2, offset: 80), TileKnot(t: 0.8, offset: 80)], count: 2)
        try require(!corrupt.valid, "Crossing profiles within coordinate limits must be rejected")
        let a = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 10)]
        let b = a.map { tileAdd($0, CGPoint(x: 2, y: 2)) }
        try require(abs(tileArea(tileClip(a, by: b)) - 18) < 1e-7, "Triangle intersection area is incorrect")
        try require(tileClip(a, by: a.map { tileAdd($0, CGPoint(x: 20, y: 0)) }).isEmpty,
                    "Separated triangles must not intersect")
        let far = CGRect(x: 1_000_000, y: -2_000_000, width: 4000, height: 3000)
        try require(!TileDesign().cells(in: far).isEmpty, "Panning far from the origin must not reach a finite edge")
        print("PASS: 4/6-sided tilings, exact edge pairing, no gaps/overlaps, tabs, vertex constraints, undo/redo, project and SVG/PNG")
    }
}
