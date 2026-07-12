import SwiftUI

@main
struct FocusPieceApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(Theme.Palette.accent)
                .onOpenURL { app.handleDeepLink($0) }
        }
    }
}
