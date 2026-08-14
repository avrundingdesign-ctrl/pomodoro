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
            WatchRootView()
                .environmentObject(model)
                .task { model.activate() }
        }
    }
}
