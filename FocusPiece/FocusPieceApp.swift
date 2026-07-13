import SwiftUI

@main
struct FocusPieceApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(Theme.Palette.accent)
                // "Thema": Hell / Dunkel erzwingen, System folgt dem Gerät.
                .preferredColorScheme(app.settings.colorScheme)
                .onOpenURL { app.handleDeepLink($0) }
        }
    }
}
