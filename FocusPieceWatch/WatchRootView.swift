import SwiftUI

/// Root of the watch app — picks the screen for whatever the phone last said.
///
/// Wire it up from the target's generated `FocusPieceWatchApp.swift`:
///
/// ```swift
/// @main
/// struct FocusPieceWatch_Watch_AppApp: App {
///     @StateObject private var model = WatchModel()
///
///     var body: some Scene {
///         WindowGroup {
///             WatchRootView()
///                 .environmentObject(model)
///                 .task { model.activate() }
///         }
///     }
/// }
/// ```
struct WatchRootView: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        Group {
            if let session = model.session {
                switch session.state {
                case .complete:
                    WatchRewardView(model: model, session: session)
                case .finished:
                    // The long break ran out; the phone drops the cycle next,
                    // so show the idle face rather than an empty ring.
                    WatchIdleView(model: model)
                default:
                    WatchRunningView(model: model, session: session)
                }
            } else {
                WatchIdleView(model: model)
            }
        }
        // A phase change swaps the screen; without this it snaps.
        .animation(.easeInOut(duration: 0.25), value: model.session?.state)
    }
}
