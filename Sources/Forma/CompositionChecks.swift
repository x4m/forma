import AppKit
import SwiftUI

extension Diagnostics {
    @MainActor
    static func compositionChecks(destination: URL?) throws {
        let p = Parameters()
        try require([NSColor.red, .blue, .green, .white, .black].allSatisfy { $0.hex.count == 7 }, "SVG colours must stay inside the RGB range")
        let source = try fixture(transparent: false)
        for alphabet in ["0123456789", "АБВГДЖШЩЯ", "αβγδε", "<>&@"] {
            var letters = p; letters.alphabet = alphabet
            let drawing = Engine(raster: source, parameters: letters).drawing(.ascii, letters)
            try require(!drawing.isEmpty && drawing.raster == nil, "Alphabet \(alphabet) failed to produce vector outlines")
            try require(XMLParser(data: Data(drawing.svg(color: .black, background: nil).utf8)).parse(), "Custom symbols broke SVG XML")
        }
        var blank = p; blank.alphabet = " \n\t"
        try require(Engine(raster: source, parameters: blank).drawing(.ascii, blank).isEmpty, "Whitespace must not produce placeholder glyphs")

        var red = Drawing(); red.rect(CGRect(x: 40, y: 20, width: 40, height: 40))
        var blue = Drawing(); blue.rect(CGRect(x: 40, y: 20, width: 40, height: 40))
        let bottom = ArtLayer(style: .pixels, parameters: p, ink: Ink(.red))
        var top = ArtLayer(style: .pixels, parameters: p, ink: Ink(.blue))
        func pixel(_ composition: Composition, _ x: Int, _ y: Int) throws -> NSColor {
            guard let data = composition.png(pixels: 384), let rep = NSBitmapImageRep(data: data), let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                throw Failure(description: "Composition bitmap could not be read")
            }
            return c
        }
        var scene = Composition(layers: [RenderedLayer(layer: bottom, drawing: red), RenderedLayer(layer: top, drawing: blue)], background: .white)
        let first = try pixel(scene, 50, 30)
        try require(first.blueComponent > 0.9 && first.redComponent < 0.1, "Layer order must be bottom-to-top")
        scene.layers.reverse()
        let reversed = try pixel(scene, 50, 30)
        try require(reversed.redComponent > 0.9, "Reordering layers must change the result")
        top.blend = .multiply
        scene.layers = [RenderedLayer(layer: bottom, drawing: red), RenderedLayer(layer: top, drawing: blue)]
        let multiplied = try pixel(scene, 50, 30)
        try require(multiplied.redComponent < 0.1 && multiplied.blueComponent < 0.1, "Multiply blend did not combine colours")
        top.blend = .screen; scene.layers[1].layer = top
        let screened = try pixel(scene, 50, 30)
        try require(screened.redComponent > 0.9 && screened.blueComponent > 0.9, "Screen blend did not combine colours")
        top.blend = .normal
        top.enabled = false
        scene.layers = [RenderedLayer(layer: bottom, drawing: red), RenderedLayer(layer: top, drawing: blue)]
        try require(try pixel(scene, 50, 30).redComponent > 0.9, "Hidden layers must not be drawn")
        top.enabled = true; top.x = 80
        scene.layers[1].layer = top
        try require(try pixel(scene, 130, 30).blueComponent > 0.9, "Layer offset was not applied")
        var rotated = bottom; rotated.rotation = 90
        scene.layers = [RenderedLayer(layer: rotated, drawing: red)]
        try require(try pixel(scene, 354, 50).redComponent > 0.9, "Rotation must use the canvas centre")
        var blurred = bottom; blurred.id = UUID(); blurred.blur = 4; blurred.opacity = 0.5
        scene = Composition(layers: [RenderedLayer(layer: blurred, drawing: red)], background: nil)
        let halo = try pixel(scene, 37, 40)
        let centre = try pixel(scene, 60, 40)
        if let destination { try scene.png(pixels: 384)!.write(to: destination.appendingPathComponent("blur-check.png")) }
        try require(halo.alphaComponent > 0.02 && halo.alphaComponent < 0.5, "Blur must extend the layer and respect opacity; halo=\(halo.alphaComponent), centre=\(centre.alphaComponent)")
        try require(centre.alphaComponent > 0.45 && centre.alphaComponent < 0.55, "Layer opacity was applied incorrectly")
        try require(XMLParser(data: Data(scene.svg().utf8)).parse() && scene.svg().contains("feGaussianBlur"), "SVG must preserve a layer's blur")

        // A bitmap and a path at the same coordinates must have the same Y axis.
        let bitmap = NSBitmapImageRep(data: red.png(color: .red, background: nil, pixels: 384)!)!.cgImage!
        var photo = Drawing(); photo.raster = bitmap
        let imageColor = NSBitmapImageRep(data: photo.png(color: .black, background: nil, pixels: 384)!)!.colorAt(x: 50, y: 30)!
        try require(imageColor.alphaComponent > 0.95, "Bitmap exports were flipped vertically")
        photo.rasterUsesInk = true
        let tinted = NSBitmapImageRep(data: photo.png(color: .green, background: nil, pixels: 384)!)!
        let green = tinted.colorAt(x: 50, y: 30)!.usingColorSpace(.deviceRGB)!
        try require(green.greenComponent > 0.9 && green.redComponent < 0.1 && tinted.colorAt(x: 0, y: 0)!.alphaComponent == 0,
                    "Tinting a raster must preserve its alpha mask")
        try require(photo.svg(color: .green, background: nil).contains("data:image/png;base64,"), "Photo SVG must embed its raster")

        let recorded = try SourceRecord(source)
        let project = FormaProject(source: recorded, layers: [bottom, blurred], style: .ascii, parameters: p,
                                   ink: Ink(.black), paper: Ink(.white), opaque: false)
        let data = try JSONEncoder().encode(project)
        let restored = try JSONDecoder().decode(FormaProject.self, from: data)
        try require(restored.parameters.valid, "Decoded project parameters are invalid")
        try require(restored.layers.allSatisfy(\.valid), "Decoded layer settings are invalid: \(restored.layers.map(\.ink))")
        try require(restored.ink.valid && restored.paper.valid, "Decoded project colours are invalid")
        try restored.validate()
        try require(try restored.source.restore().rgba == source.rgba, "Project round trip changed the source pixels")
        try require(restored.layers == project.layers && !restored.opaque, "Project round trip changed layer settings")

        let model = AppModel(loadSample: false)
        model.raster = source
        model.addLayer(.ascii)
        let originalID = model.selectedLayerID
        model.duplicateLayer()
        try require(model.layers.count == 2 && model.layers[0].id != model.layers[1].id, "Duplicated layers need independent identities")
        model.moveLayer(up: false)
        try require(model.layers[1].id == originalID, "Moving a selected layer changed the wrong layer")
        model.removeLayer()
        try require(model.layers.count == 1 && model.selectedLayerID == originalID, "Delete must preserve another selectable layer")
        model.shadowPreset()
        try require(model.layers.count == 3 && model.layers[1].style == .shadow && model.layers[1].blur > 0 && model.layers.last?.style == .ascii,
                    "Shadow preset must use the selected layer and append, not replace existing work")
        model.regenerateComposition()
        let deadline = Date(timeIntervalSinceNow: 10)
        while model.layersBusy && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        try require(!model.layersBusy && model.compositionPreview != nil, "Composition preview did not finish")
        if let destination {
            let url = destination.appendingPathComponent("roundtrip.forma")
            try data.write(to: url)
            try model.composition.png()!.write(to: destination.appendingPathComponent("composition.png"))
            try Data(model.composition.svg().utf8).write(to: destination.appendingPathComponent("composition.svg"))
            model.loadProject(url)
            let finish = Date(timeIntervalSinceNow: 10)
            while (model.busy || model.layersBusy) && Date() < finish { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
            try require(model.layers == restored.layers && model.mode == .composition && model.compositionPreview != nil,
                        "Opening a saved project did not restore the composition")
        }
        print("PASS: Unicode glyph paths, layer order/visibility/transform/blur/alpha, raster orientation/tint, SVG filters, project round trip, layer editing")
    }
}
