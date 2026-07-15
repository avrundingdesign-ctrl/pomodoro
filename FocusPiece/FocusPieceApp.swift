import SwiftUI

@main
struct FocusPieceApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(Theme.Palette.accent)
                // Die Palette ist bewusst hell — ohne dieses Pinning würde die
                // Statusbar im System-Dunkelmodus weiß auf Papier rendern.
                .preferredColorScheme(.light)
        }
    }
}
