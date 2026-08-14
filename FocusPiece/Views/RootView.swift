import SwiftUI

/// Root container — onboarding gate, then the three tabs with a custom tab bar.
struct RootView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var updateChecker: UpdateChecker
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if !app.onboardingComplete {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainTabs()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: app.onboardingComplete)
        .alert(item: Binding(
            get: { updateChecker.available },
            set: { newValue in
                if newValue == nil, let current = updateChecker.available {
                    updateChecker.dismiss(current)
                }
            }
        )) { update in
            Alert(
                title: Text("Update verfügbar"),
                message: Text("FocusPiece \(update.version) ist jetzt im App Store erhältlich."),
                primaryButton: .default(Text("Aktualisieren")) { openURL(update.storeURL) },
                secondaryButton: .cancel(Text("Später"))
            )
        }
    }
}

private struct MainTabs: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.Palette.paper.ignoresSafeArea()

            switch app.selectedTab {
            case .focus:
                // Immersive session flow — full screen, its own header, no tab bar.
                FocusTab()
            case .gallery:
                tabbed { GalleryView() }
            case .settings:
                tabbed { SettingsView() }
            }
        }
    }

    private func tabbed<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .bottom) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 90) // room for the tab bar
            TabBar(selection: $app.selectedTab)
        }
    }
}

/// Hands the Fokus tab the cycle that `AppModel` owns, creating one on first
/// entry.
///
/// The session is created from `.task` rather than inline in `body`, because
/// `beginSession()` publishes — doing it during the view update would draw
/// SwiftUI's "Publishing changes from within view updates" complaint. A watch
/// command can also have created the session already, in which case this just
/// picks it up.
private struct FocusTab: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()
            if let session = app.session {
                SessionFlowView(session: session)
            }
        }
        .task { app.beginSession() }
    }
}
