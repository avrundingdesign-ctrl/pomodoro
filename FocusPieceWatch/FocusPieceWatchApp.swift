import SwiftUI

/// Entry point of the watch companion.
///
/// `WatchModel` is created here and activated once, from `.task` rather than
/// `init`, so `WCSession` comes up after the scene exists — activating earlier
/// means the first application context can arrive before there is anything to
/// hand it to.
@main
struct FocusPieceWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            // The screens all set `.containerBackground(for: .navigation)`, and
            // that modifier is silently ignored outside a navigation container
            // — which is why every screen rendered on plain system black
            // instead of on paper. One stack, no destinations: it exists purely
            // so the backgrounds have something to attach to.
            NavigationStack {
                WatchRootView()
                    .environmentObject(model)
                    .task { model.activate() }
            }
        }
    }
}
