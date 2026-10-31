import SwiftUI

@main
struct FormaApp: App {
    @StateObject private var model = AppModel()

    init() {
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot-ui"), CommandLine.arguments.count > index + 1 {
            do { try Diagnostics.snapshot(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--self-test") {
            do { try Diagnostics.run(); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
    }

    var body: some Scene {
        WindowGroup("Forma") {
            ContentView().environmentObject(model)
                .onOpenURL { model.load($0) }
        }
        .defaultSize(width: 1180, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Открыть изображение…") { model.openImage() }.keyboardShortcut("o")
                Button("Загрузить пример") { model.loadSample() }
            }
            CommandGroup(after: .saveItem) {
                Button("Сохранить проект…") { model.saveProject() }.keyboardShortcut("s")
                Button("Открыть проект…") { model.openProject() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Экспортировать SVG…") { model.export(svg: true) }.keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!model.canExport)
                Button("Экспортировать PNG…") { model.export(svg: false) }.disabled(!model.canExport)
            }
        }
    }
}
