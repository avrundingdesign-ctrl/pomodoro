import SwiftUI

@main
struct FocusPieceApp: App {
    @StateObject private var app = AppModel()
    @StateObject private var store = StoreModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(store)
                .tint(Theme.Palette.accent)
                // "Thema": Hell / Dunkel erzwingen, System folgt dem Gerät.
                .preferredColorScheme(app.settings.colorScheme)
                .onOpenURL { app.handleDeepLink($0) }
                .task {
                    // A crash mid-session leaves its Live Activity on screen;
                    // sessions never survive a relaunch, so clear it first.
                    LiveActivityController.endStaleActivities()
                    await store.start()
                    app.applyPurchasedProducts(store.purchasedProductIDs)
                }
                .onChange(of: store.purchasedProductIDs) { _, ids in
                    app.applyPurchasedProducts(ids)
                }
        }
    }
}
