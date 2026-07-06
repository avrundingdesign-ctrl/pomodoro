import SwiftUI

/// Bottom tab bar — 90px, translucent paper + blur, top hairline.
/// Fokus · Galerie · Community · Store · Profil. Active = accent.
/// Community trägt ein Badge für ungelesene Nachrichten & Anfragen.
struct TabBar: View {
    @Binding var selection: Tab
    @EnvironmentObject var online: OnlineModel

    var body: some View {
        HStack(spacing: 0) {
            item(.focus,     icon: "clock",               label: "Fokus")
            item(.gallery,   icon: "photo.on.rectangle",  label: "Galerie")
            item(.community, icon: "person.2",            label: "Community",
                 badge: online.totalUnread + online.requests.count)
            item(.store,     icon: "bag",                 label: "Store")
            item(.profile,   icon: "person.crop.circle",  label: "Profil")
        }
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

    private func item(_ tab: Tab, icon: String, label: String, badge: Int = 0) -> some View {
        let active = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .regular))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(min(badge, 9))")
                                .font(Theme.Font.sans(9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 15, height: 15)
                                .background(Theme.Palette.accent)
                                .clipShape(Circle())
                                .offset(x: 9, y: -7)
                        }
                    }
                Text(label)
                    .font(Theme.Font.sans(10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(active ? Theme.Palette.accent : Theme.Palette.muted3)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
