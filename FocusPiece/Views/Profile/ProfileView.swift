import SwiftUI

/// Profil-Tab: Account, Münz-Wallet, umfangreiche Statistiken, Erfolge.
/// Ohne Konto zeigt der Tab die Anmeldung; die Einstellungen bleiben über
/// das Zahnrad immer erreichbar.
struct ProfileView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var online: OnlineModel

    @State private var showSettings = false
    @State private var showEditor = false
    @State private var showAllTransactions = false
    @State private var confirmSignOut = false

    var body: some View {
        VStack(spacing: 0) {
            header
            OnlineGate {
                signedInContent
            }
        }
        .background(Theme.Palette.paper)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .background(Theme.Palette.paper)
        }
        .sheet(isPresented: $showEditor) {
            if let profile = online.profile {
                ProfileEditorSheet(profile: profile, mode: .edit)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Profil")
                .font(Theme.Font.serif(32))
                .tracking(-0.3)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            CircleIconButton(systemName: "slider.horizontal.3") { showSettings = true }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8).padding(.bottom, 16)
    }

    private var signedInContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                accountCard
                coinsCard

                sectionTitle("Statistiken")
                StatsDashboard(stats: online.myStats)

                sectionTitle("Erfolge")
                AchievementsGrid(stats: online.myStats)

                GhostButton(title: "Abmelden") { confirmSignOut = true }
                    .padding(.top, 6)

                Text("FocusPiece · Version 1.0")
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.muted3Soft)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .confirmationDialog("Abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { online.signOut() }
            Button("Angemeldet bleiben", role: .cancel) {}
        } message: {
            Text("Deine Münzen und gekauften Pakete bleiben auf diesem Gerät erhalten.")
        }
    }

    // MARK: Account

    private var accountCard: some View {
        VStack(spacing: 0) {
            if let profile = online.profile {
                HStack(spacing: 16) {
                    AvatarView(profile: profile, size: 72, presence: online.ownPresence)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName)
                            .font(Theme.Font.serif(22, weight: .medium))
                            .foregroundStyle(Theme.Palette.ink)
                        Text(profile.handleLabel)
                            .font(Theme.Font.sans(13))
                            .foregroundStyle(Theme.Palette.muted2)
                        HStack(spacing: 5) {
                            Image(systemName: "mappin")
                                .font(.system(size: 10))
                            Text("\(profile.city.name), \(profile.city.country)")
                                .font(Theme.Font.sans(12))
                        }
                        .foregroundStyle(Theme.Palette.muted3)
                    }
                    Spacer()
                }
                .padding(16)

                if !profile.bio.isEmpty {
                    Text(profile.bio)
                        .font(Theme.Font.serifItalic(14))
                        .foregroundStyle(Theme.Palette.bodySoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }

                Divider().overlay(Theme.Palette.hairline3)

                HStack {
                    Text("Konto über \(profile.provider.label) · seit \(Self.joined(profile.joinedAt))")
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Palette.muted3)
                    Spacer()
                    Button {
                        showEditor = true
                    } label: {
                        Text("Bearbeiten")
                            .font(Theme.Font.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                .stroke(Theme.Palette.hairline2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }

    // MARK: Münzen

    private var coinsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                CoinBadge(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(online.coins) Münzen")
                        .font(Theme.Font.serif(20, weight: .medium))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("Verdient durch Fokus — einlösbar im Store")
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Palette.muted2)
                }
                Spacer()
                Button {
                    app.selectedTab = .store
                } label: {
                    Text("Store")
                        .font(Theme.Font.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            if !online.transactions.isEmpty {
                Divider().overlay(Theme.Palette.hairline3)
                VStack(spacing: 0) {
                    ForEach(online.transactions.prefix(showAllTransactions ? 12 : 3)) { tx in
                        HStack {
                            Text(tx.reason)
                                .font(Theme.Font.sans(13))
                                .foregroundStyle(Theme.Palette.muted)
                            Spacer()
                            Text(tx.amount > 0 ? "+\(tx.amount)" : "\(tx.amount)")
                                .font(Theme.Font.sans(13, weight: .semibold))
                                .foregroundStyle(tx.amount > 0 ? Theme.Palette.success : Theme.Palette.accent)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    if online.transactions.count > 3 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { showAllTransactions.toggle() }
                        } label: {
                            Text(showAllTransactions ? "Weniger anzeigen" : "Alle anzeigen")
                                .font(Theme.Font.sans(12, weight: .medium))
                                .foregroundStyle(Theme.Palette.muted2)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                .stroke(Theme.Palette.hairline2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.Font.sans(11, weight: .semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Palette.muted3)
            .padding(.leading, 12)
            .padding(.top, 4)
    }

    private static func joined(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }
}

/// Die FocusPiece-Münze — goldener Kreis mit Serifen-F.
struct CoinBadge: View {
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Palette.coin)
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: max(1, size * 0.04))
                .padding(size * 0.12)
            Text("F")
                .font(Theme.Font.serif(size * 0.52, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
