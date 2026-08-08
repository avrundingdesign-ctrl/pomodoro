import SwiftUI

/// Bottom tab bar — 90px, translucent paper + blur, top hairline.
/// Fokus (clock) · Galerie (photo) · Einstellungen (sliders). Active = accent.
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
        .frame(maxWidth: .infinity)
        .frame(height: 90, alignment: .top)
        .background(
            Theme.Palette.paper.opacity(0.94)
                .background(.ultraThinMaterial)
        )
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
