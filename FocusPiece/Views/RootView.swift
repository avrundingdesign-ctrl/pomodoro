import SwiftUI

/// Root container — onboarding gate, then the three tabs with a custom tab bar.
struct RootView: View {
    @EnvironmentObject var app: AppModel

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
                // Rebuilt with a fresh ready session each time the tab is entered.
                SessionFlowView(app: app)
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
