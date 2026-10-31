import SwiftUI

@main
struct FormaTabletApp: App {
    @StateObject private var model = TabletModel()
    var body: some Scene {
        WindowGroup { TabletView().environmentObject(model) }
    }
}
