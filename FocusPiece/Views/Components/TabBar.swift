import SwiftUI

/// Bottom tab bar — translucent paper + blur, top hairline.
/// Fokus (clock) · Galerie (photo) · Einstellungen (sliders). Active = accent.
///
/// The bar sizes itself to its items instead of carrying a fixed height, and is
/// hung off `safeAreaInset` rather than stacked on top of the content — see the
/// note in `RootView`. Its background is the one part that ignores the bottom
/// safe area, so the paper runs to the screen edge behind the home indicator.
/// Painting that strip from here rather than letting the root background show
/// through matters: the bar is translucent (0.94 over a material), so it can
/// never resolve to exactly the same colour as the opaque paper beneath, and
/// the mismatch reads as a seam across the bar's lower edge.
struct TabBar: View {
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 0) {
            item(.focus,    icon: "clock",              label: "Fokus")
            item(.gallery,  icon: "photo.on.rectangle", label: "Galerie")
            item(.settings, icon: "slider.horizontal.3", label: "Einstellungen")
        }
        // Keep the three items together on iPad instead of spreading them
        // across the full width; the bar background still spans the screen.
        .contentColumn()
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background {
            Theme.Palette.paper.opacity(0.94)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
        }
    }

    private func item(_ tab: Tab, icon: String, label: LocalizedStringKey) -> some View {
        let active = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .regular))
                Text(label)
                    .font(Theme.Font.sans(11, weight: .medium))
            }
            .foregroundStyle(active ? Theme.Palette.accent : Theme.Palette.muted3)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
