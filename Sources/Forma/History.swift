import SwiftUI

// A plain WindowGroup may not supply SwiftUI's document undo environment.
// Use the actual NSWindow manager so the standard Edit menu and text editor
// keep their native responder-chain behaviour.
struct UndoWindowBridge: NSViewRepresentable {
    var model: AppModel
    func makeNSView(context: Context) -> WindowUndoView {
        let view = WindowUndoView()
        view.model = model
        return view
    }
    func updateNSView(_ view: WindowUndoView, context: Context) { view.model = model; view.connect() }
}

final class WindowUndoView: NSView {
    weak var model: AppModel?
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); connect() }
    func connect() {
        guard let window, let model else { return }
        model.useUndoManager(window.undoManager)
        if CommandLine.arguments.contains("--check-undo-ui") {
            DispatchQueue.main.async { Diagnostics.checkUndoWindow(model) }
        }
    }
}

// Only editable state is kept in history. Paths, thumbnails and render jobs are
// derived again, so undo cannot bring a stale preview back into the project.
struct EditorState: Equatable {
    var raster: Raster?
    var parameters: Parameters
    var style: Style
    var ink: Color
    var paper: Bool
    var paperColor: Color
    var layers: [ArtLayer]
    var selectedLayerID: UUID?
    var mode: WorkspaceMode
    var showOriginal: Bool
    var projectName: String
    var tile: TileDesign

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.raster?.image === rhs.raster?.image && lhs.parameters == rhs.parameters &&
        lhs.style == rhs.style && lhs.ink == rhs.ink && lhs.paper == rhs.paper &&
        lhs.paperColor == rhs.paperColor && lhs.layers == rhs.layers &&
        lhs.selectedLayerID == rhs.selectedLayerID && lhs.mode == rhs.mode &&
        lhs.showOriginal == rhs.showOriginal && lhs.projectName == rhs.projectName && lhs.tile == rhs.tile
    }
}

@MainActor
extension AppModel {
    var editorState: EditorState {
        EditorState(raster: raster, parameters: parameters, style: selected, ink: color,
                    paper: paper, paperColor: paperColor, layers: layers,
                    selectedLayerID: selectedLayerID, mode: mode, showOriginal: showOriginal,
                    projectName: projectName, tile: tile)
    }

    func useUndoManager(_ manager: UndoManager?) {
        guard historyManager !== manager else { return }
        endContinuousEdit()
        historyManager = manager
        // Raster storage and layer arrays are shared until edited (copy-on-write).
        manager?.levelsOfUndo = 100
    }

    func edit(_ name: String, record: Bool = true, _ changes: () -> Void) {
        guard editDepth == 0 else { changes(); return }
        let before = editorState
        editDepth += 1
        changes()
        editDepth -= 1
        guard before != editorState else { return }
        if record && continuousEdit == nil { registerRestore(before, name: name) }
        refresh(after: before)
    }

    func value<T>(_ path: ReferenceWritableKeyPath<AppModel, T>, name: String) -> Binding<T> {
        Binding(get: { self[keyPath: path] }, set: { value in
            self.edit(name) { self[keyPath: path] = value }
        })
    }

    // Never hold an UndoManager group open across mouse events. Keep the starting
    // state instead and register one action when the slider releases the mouse.
    func beginContinuousEdit(_ name: String) {
        guard continuousEdit == nil else { return }
        continuousEdit = (editorState, name)
    }

    func endContinuousEdit() {
        guard let pending = continuousEdit else { return }
        continuousEdit = nil
        if pending.state != editorState { registerRestore(pending.state, name: pending.name) }
    }

    private func registerRestore(_ state: EditorState, name: String) {
        guard let manager = historyManager else { return }
        let replaying = manager.isUndoing || manager.isRedoing
        if !replaying { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: self) { model in model.restore(state, name: name) }
        manager.setActionName(name)
        if !replaying { manager.endUndoGrouping() }
    }

    private func restore(_ state: EditorState, name: String) {
        let before = editorState
        registerRestore(before, name: name)
        raster = state.raster; parameters = state.parameters; selected = state.style
        color = state.ink; paper = state.paper; paperColor = state.paperColor
        layers = state.layers; selectedLayerID = state.selectedLayerID
        mode = state.mode; showOriginal = state.showOriginal; projectName = state.projectName
        tile = state.tile
        refresh(after: before)
    }
}
