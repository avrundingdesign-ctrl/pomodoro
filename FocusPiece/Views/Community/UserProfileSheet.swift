import SwiftUI

/// Profil eines anderen Nutzers: Live-Status, Statistiken, Erfolge —
/// plus Freundschafts- und Nachrichten-Aktionen.
struct UserProfileSheet: View {
    @EnvironmentObject var online: OnlineModel
    @Environment(\.dismiss) private var dismiss

    let userID: String
    @State private var requested = false

    var body: some View {
        NavigationStack {
            Group {
                if let profile = online.profile(of: userID) {
                    content(profile)
                } else {
                    Text("Profil nicht gefunden")
                        .font(Theme.Font.sans(14))
                        .foregroundStyle(Theme.Palette.muted2)
                }
            }
            .background(Theme.Palette.paper)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func content(_ profile: UserProfile) -> some View {
        let presence = online.presence(of: userID)
        let stats = online.stats(of: userID)
        let isFriend = online.isFriend(userID)

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Kopf
                VStack(spacing: 10) {
                    AvatarView(profile: profile, size: 92, presence: presence)
                    Text(profile.displayName)
                        .font(Theme.Font.serif(26, weight: .medium))
                        .foregroundStyle(Theme.Palette.ink)
                    HStack(spacing: 8) {
                        Text(profile.handleLabel)
                        Text("·")
                        HStack(spacing: 4) {
                            Image(systemName: "mappin").font(.system(size: 10))
                            Text(profile.city.name)
                        }
                    }
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.muted2)
                    if !profile.bio.isEmpty {
                        Text(profile.bio)
                            .font(Theme.Font.serifItalic(14))
                            .foregroundStyle(Theme.Palette.bodySoft)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                // Live-Status
                if let status = presence.focusStatus {
                    liveCard(status, presence: presence, isFriend: isFriend)
                }

                // Aktionen
                if isFriend {
                    NavigationLink {
                        ChatView(partner: profile)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 15, weight: .medium))
                            Text("Nachricht senden")
                                .font(Theme.Font.sans(16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Theme.Palette.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.primaryButton, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    GhostButton(title: requested ? "Anfrage gesendet ✓" : "Als Freund hinzufügen",
                                icon: requested ? nil : "person.badge.plus") {
                        online.sendFriendRequest(to: userID)
                        requested = true
                    }
                    .disabled(requested)
                    .opacity(requested ? 0.6 : 1)
                }

                Text("Statistiken")
                    .font(Theme.Font.sans(11, weight: .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.muted3)
                    .padding(.leading, 12)
                StatsDashboard(stats: stats, compact: true)

                let earned = Achievement.earned(by: stats)
                if !earned.isEmpty {
                    Text("Erfolge")
                        .font(Theme.Font.sans(11, weight: .semibold))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Palette.muted3)
                        .padding(.leading, 12)
                    AchievementsGrid(stats: stats, earnedOnly: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
    }

    private func liveCard(_ status: FocusStatus, presence: Presence, isFriend: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Theme.Palette.live).frame(width: 8, height: 8)
                Text(presence.label.uppercased())
                    .font(Theme.Font.sans(11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.Palette.live)
                Spacer()
                Text("seit \(max(1, Int(Date().timeIntervalSince(status.startedAt) / 60))) Min")
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Palette.muted3)
            }
            Text("Runde \(status.round) von \(status.totalRounds) · \(status.artworkTitle)")
                .font(Theme.Font.sans(14))
                .foregroundStyle(Theme.Palette.ink)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.progressTrack)
                    Capsule().fill(Theme.Palette.live)
                        .frame(width: max(4, geo.size.width * CGFloat(status.progress)))
                }
            }
            .frame(height: 5)

            if isFriend {
                HStack(spacing: 8) {
                    ForEach(Nudge.allCases) { nudge in
                        Button {
                            online.send(.nudge(nudge), to: userID)
                        } label: {
                            Text(nudge.emoji)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .background(Theme.Palette.surface2)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                .stroke(Theme.Palette.hairline2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }
}
