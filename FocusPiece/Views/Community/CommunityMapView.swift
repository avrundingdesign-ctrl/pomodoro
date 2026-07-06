import SwiftUI
import MapKit

/// Die Community-Karte: alle Nutzer an ihren (selbst gewählten) Städten.
/// Wer gerade fokussiert, trägt einen Live-Fortschrittsring; ein Tipp öffnet
/// Profil, Statistiken und Erfolge.
struct CommunityMapView: View {
    @EnvironmentObject var online: OnlineModel

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 50.3, longitude: 9.5),
                           span: MKCoordinateSpan(latitudeDelta: 16, longitudeDelta: 16)))
    @State private var selectedUserID: String?

    var body: some View {
        Map(position: $camera) {
            ForEach(mapUsers) { user in
                Annotation(pinTitle(for: user), coordinate: jittered(user)) {
                    Button {
                        if user.id != online.profile?.id { selectedUserID = user.id }
                    } label: {
                        MapPin(profile: user,
                               presence: online.presence(of: user.id),
                               isSelf: user.id == online.profile?.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .overlay(alignment: .top) { statsChip }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                .stroke(Theme.Palette.hairline2, lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .sheet(item: Binding(
            get: { selectedUserID.map(SheetID.init) },
            set: { selectedUserID = $0?.id })) { sheet in
            UserProfileSheet(userID: sheet.id)
        }
    }

    private struct SheetID: Identifiable { let id: String }

    private var mapUsers: [UserProfile] {
        var users = online.communityProfiles
        if let me = online.profile { users.insert(me, at: 0) }
        return users
    }

    /// "Lena · fokussiert" unter dem Pin — die Karte erzählt, was passiert.
    private func pinTitle(for user: UserProfile) -> String {
        let name = user.id == online.profile?.id
            ? "Du" : user.displayName.split(separator: " ").first.map(String.init) ?? user.displayName
        let presence = online.presence(of: user.id)
        return presence.isInSession ? "\(name) · fokussiert" : name
    }

    /// Nutzer derselben Stadt deterministisch auffächern, damit sich die
    /// Pins nicht stapeln.
    private func jittered(_ user: UserProfile) -> CLLocationCoordinate2D {
        let seed = UInt64(bitPattern: Int64(user.id.hashValue))
        var rng = SeededRNG(seed: seed == 0 ? 1 : seed)
        let lat = user.city.latitude + Double.random(in: -0.12...0.12, using: &rng)
        let lon = user.city.longitude + Double.random(in: -0.12...0.12, using: &rng)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var statsChip: some View {
        let focusing = mapUsers.filter { online.presence(of: $0.id).isInSession }.count
        let cities = Set(mapUsers.map(\.city.id)).count
        return HStack(spacing: 8) {
            Circle().fill(Theme.Palette.live).frame(width: 8, height: 8)
            Text("\(focusing) im Fokus · \(cities) Städte")
                .font(Theme.Font.sans(12, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.Palette.paper.opacity(0.94))
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.Palette.cardBorder, lineWidth: 1))
        .padding(.top, 12)
    }
}

// MARK: - Pin

private struct MapPin: View {
    let profile: UserProfile
    let presence: Presence
    let isSelf: Bool

    var body: some View {
        ZStack {
            if let status = presence.focusStatus {
                Circle()
                    .stroke(Theme.Palette.paper, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.03, status.progress))
                    .stroke(Theme.Palette.live, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                AvatarView(profile: profile, size: 38)
            } else {
                Circle()
                    .stroke(Theme.Palette.paper, lineWidth: 3)
                AvatarView(profile: profile, size: 34)
                    .opacity(presence == .offline ? 0.55 : 1)
            }
            if isSelf {
                Circle()
                    .stroke(Theme.Palette.accent, lineWidth: 2)
            }
        }
        .frame(width: 46, height: 46)
        .shadow(color: Color(hex: 0x28221C).opacity(0.25), radius: 6, x: 0, y: 4)
    }
}
