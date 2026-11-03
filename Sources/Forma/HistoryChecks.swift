import SwiftUI

extension Diagnostics {
    @MainActor
    static func historyChecks() throws {
        let model = AppModel(loadSample: false)
        model.raster = try fixture(transparent: false)
        let manager = UndoManager()
        manager.groupsByEvent = false
        model.useUndoManager(manager)
        let original = model.editorState

        model.selectEffect(.xray)
        let xray = model.editorState
        try require(manager.canUndo && xray != original, "Effect selection was not recorded")
        manager.undo()
        try require(model.editorState == original, "Undo must restore effect, ink and paper together")
        manager.redo()
        try require(model.editorState == xray, "Redo must restore the entire effect selection")
        manager.undo()
        model.value(\.parameters, name: "Настройки").wrappedValue = model.parameters
        try require(manager.canRedo, "A no-op must preserve redo history")
        model.value(\.paper, name: "Фон").wrappedValue = false
        try require(!manager.canRedo && !model.paper, "New edits must discard the redo branch")
        manager.undo()
        try require(model.editorState == original, "Paper transparency undo failed")
        manager.removeAllActions()

        let settings = model.value(\.parameters, name: "Настройки")
        model.beginContinuousEdit("Шаг элементов")
        for step in 13...24 { var p = model.parameters; p.spacing = Double(step); settings.wrappedValue = p }
        model.endContinuousEdit()
        model.beginContinuousEdit("Шаг элементов")
        for step in 25...28 { var p = model.parameters; p.spacing = Double(step); settings.wrappedValue = p }
        model.endContinuousEdit()
        manager.undo()
        try require(model.parameters.spacing == 24, "Separate slider drags must be separate undo steps")
        manager.undo()
        try require(model.parameters.spacing == original.parameters.spacing && !manager.canUndo,
                    "One drag must undo every intermediate slider value in one step")
        manager.redo(); manager.redo()
        try require(model.parameters.spacing == 28, "Slider redo did not restore its final value")
        manager.removeAllActions()

        let beforePreset = model.editorState
        model.shadowPreset()
        let preset = model.editorState
        manager.undo()
        try require(model.editorState == beforePreset, "Two-layer preset must undo in one step")
        manager.redo()
        try require(model.editorState == preset, "Preset redo must retain layer IDs and selection")
        let id = model.selectedLayerID!
        model.duplicateLayer()
        let duplicate = model.editorState
        model.removeLayer()
        manager.undo()
        try require(model.editorState == duplicate, "Undo delete must restore selection and layer identity")
        manager.undo()
        try require(model.editorState == preset, "Undo duplicate changed the original layer")
        model.moveLayer(up: false)
        manager.undo()
        try require(model.editorState == preset, "Undo layer reorder failed")
        model.toggleLayer(id)
        manager.undo()
        try require(model.editorState == preset, "Undo layer visibility failed")
        model.setLayerStyle(.ascii)
        manager.undo()
        try require(model.editorState == preset, "Undo layer effect must restore its ink too")
        model.setLayerInk(.red)
        manager.undo()
        try require(model.editorState == preset, "Undo layer ink failed")
        model.layerValue(\.opacity, fallback: 1).wrappedValue = 0.4
        manager.undo()
        try require(model.editorState == preset, "Undo layer settings failed")
        model.value(\.color, name: "Чернила").wrappedValue = .green
        manager.undo()
        try require(model.editorState == preset, "Undo effect ink failed")
        model.value(\.paperColor, name: "Бумага").wrappedValue = .yellow
        manager.undo()
        try require(model.editorState == preset, "Undo paper colour failed")
        var alphabet = model.parameters
        alphabet.alphabet = "АБВ012"
        settings.wrappedValue = alphabet
        manager.undo()
        try require(model.editorState == preset, "Undo custom alphabet failed")
        model.reset()
        manager.undo()
        try require(model.editorState == preset, "Undo reset failed")

        let replacement = try fixture(transparent: true)
        model.edit("Исходник") { model.raster = replacement }
        manager.undo()
        try require(model.editorState == preset, "Undo source replacement failed")
        let deadline = Date(timeIntervalSinceNow: 15)
        while (model.busy || model.layersBusy) && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        try require(!model.renderBusy && model.compositionPreview != nil, "Undo did not rebuild the preview")
        let expected = Engine(raster: model.raster!, parameters: model.parameters).drawing(model.selected, model.parameters)
        try require(model.current.svg(color: .black, background: nil) == expected.svg(color: .black, background: nil),
                    "A stale render replaced the restored effect")
        print("PASS: undo/redo, atomic effect/preset, slider gestures, layer editing, colours, alphabet, reset, source and preview")
    }

    @MainActor
    static func checkUndoWindow(_ model: AppModel) {
        guard !undoWindowCheckStarted else { return }
        undoWindowCheckStarted = true
        do {
            guard let manager = model.historyManager, let window = NSApp.windows.first(where: { $0.canBecomeKey }) else {
                throw Failure(description: "The SwiftUI window did not supply an undo manager")
            }
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
            let deadline = Date(timeIntervalSinceNow: 10)
            while model.renderBusy && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
            manager.removeAllActions()
            let original = model.editorState
            model.selectEffect(.xray)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            try require(manager.canUndo, "Native window did not register the edit")
            func shortcut(redo: Bool) throws {
                NSApp.mainMenu?.update()
                func command(_ menu: NSMenu) -> NSMenuItem? {
                    for item in menu.items {
                        if item.action == Selector(redo ? "redo:" : "undo:") { return item }
                        if let sub = item.submenu { sub.update(); if let found = command(sub) { return found } }
                    }
                    return nil
                }
                guard let menu = NSApp.mainMenu, let item = command(menu), let parent = item.menu else {
                    throw Failure(description: "Native undo/redo command is missing")
                }
                try require(item.keyEquivalent == "z" && item.keyEquivalentModifierMask == (redo ? [.command, .shift] : [.command]),
                            "Native undo/redo shortcut is incorrect")
                try require(item.isEnabled, "Native undo/redo command is disabled")
                parent.performActionForItem(at: parent.index(of: item))
            }
            try shortcut(redo: false)
            try require(model.editorState == original, "Cmd+Z did not undo through the native responder chain")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            try require(manager.canRedo, "Undo did not create a native redo action")
            try shortcut(redo: true)
            try require(model.selected == .xray, "Cmd+Shift+Z did not redo through the native responder chain")
            model.selectEffect(.ascii)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            window.contentView?.layoutSubtreeIfNeeded()
            func findAlphabet(_ view: NSView) -> NSTextView? {
                if let text = view as? NSTextView, text.isEditable, text.string == model.parameters.alphabet { return text }
                if let field = view as? NSTextField, field.isEditable, field.stringValue == model.parameters.alphabet {
                    window.makeFirstResponder(field)
                    return field.currentEditor() as? NSTextView
                }
                for child in view.subviews { if let found = findAlphabet(child) { return found } }
                return nil
            }
            guard let editor = window.contentView.flatMap(findAlphabet) else {
                throw Failure(description: "Cannot find the real SwiftUI alphabet editor")
            }
            let alphabet = model.parameters.alphabet
            try require(window.makeFirstResponder(editor), "Cannot focus the alphabet editor")
            editor.insertText("Ж", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            try require(model.parameters.alphabet == alphabet + "Ж", "Native typing did not update the alphabet")
            try shortcut(redo: false)
            try require(model.parameters.alphabet == alphabet, "Cmd+Z in the alphabet editor must undo the typed text")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            try shortcut(redo: true)
            try require(model.parameters.alphabet == alphabet + "Ж", "Redo in the alphabet editor must restore typed text")
            window.makeFirstResponder(nil)
            try shortcut(redo: false)
            try require(model.parameters.alphabet == alphabet, "Undo after leaving the text field restored the wrong edit")
            model.mode = .tiling
            let beforeTile = model.tile
            model.tilePreset(1)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            try shortcut(redo: false)
            try require(model.tile == beforeTile, "Native undo did not restore the tile design")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            try shortcut(redo: true)
            try require(!model.tile.profiles[0].isEmpty, "Native redo did not restore the tile preset")
            model.selectTileSample(.fishBird)
            RunLoop.main.run(until: Date(timeIntervalSinceNow:0.1))
            // This probe runs in one callback. A nested RunLoop does not always
            // finish AppKit's outer event group as returning to the event loop
            // between a real menu click and a mouse drag would do.
            while manager.groupingLevel > 0 { manager.endUndoGrouping() }
            let pair = model.tile
            model.beginContinuousEdit("Общая граница")
            try require(model.moveTileHandle(.division(5),to:tileAdd(pair.division![5],CGPoint(x:3,y:0))), "Shared border edit failed in window")
            model.endContinuousEdit()
            RunLoop.main.run(until: Date(timeIntervalSinceNow:0.05))
            while manager.groupingLevel > 0 { manager.endUndoGrouping() }
            try shortcut(redo:false)
            try require(model.tile == pair, "Native undo lost part of the two-figure block")
            try shortcut(redo:true)
            try require(model.tile.division != pair.division, "Native redo did not restore shared border")
            print("PASS: real SwiftUI window, native undo/redo menu and shortcuts, alphabet typing/focus, tiling undo/redo")
            exit(0)
        } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
}
