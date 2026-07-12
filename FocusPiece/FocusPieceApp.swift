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
                .onOpenURL { app.handleDeepLink($0) }
                .task {
                    await store.start()
                    app.applyPurchasedProducts(store.purchasedProductIDs)
                }
                .onChange(of: store.purchasedProductIDs) { _, ids in
                    app.applyPurchasedProducts(ids)
                }
        }
    }
}
