import SwiftUI

/// Live-Übersicht: wer gerade in einer Session steckt (mit Fortschritt und
/// Anfeuern-Aktion) und was zuletzt in der Community passiert ist.
struct LiveNowView: View {
    @EnvironmentObject var online: OnlineModel
    @State private var selectedUserID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let live = online.liveUsers
                HStack(spacing: 8) {
                    Circle().fill(Theme.Palette.live).frame(width: 8, height: 8)
                    Text(live.count == 1 ? "1 Person im Fokus" : "\(live.count) Personen im Fokus")
                        .font(Theme.Font.sans(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.muted2)
                }
                .padding(.leading, 12)

                if live.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(live) { entry in
                            LiveRow(entry: entry,
                                    isSelf: entry.profile.id == online.profile?.id,
                                    isFriend: online.isFriend(entry.profile.id)) {
                                selectedUserID = entry.profile.id
                            }
                        }
                    }
                }

                if !online.feed.isEmpty {
                    Text("Zuletzt in der Community")
                        .font(Theme.Font.sans(11, weight: .semibold))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Palette.muted3)
                        .padding(.leading, 12)
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(online.feed.prefix(12).enumerated()), id: \.element.id) { idx, event in
                            feedRow(event)
                            if idx < min(online.feed.count, 12) - 1 {
                                Divider().overlay(Theme.Palette.hairline3)
                            }
                        }
                    }
                    .background(Theme.Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                            .stroke(Theme.Palette.hairline2, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .sheet(item: Binding(
            get: { selectedUserID.map(SheetID.init) },
            set: { selectedUserID = $0?.id })) { sheet in
            UserProfileSheet(userID: sheet.id)
        }
    }

    private struct SheetID: Identifiable { let id: String }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.Palette.muted3)
            Text("Gerade fokussiert niemand.\nStarte eine Session — andere sehen dich hier live.")
                .multilineTextAlignment(.center)
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Palette.muted2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                .stroke(Theme.Palette.hairline2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }

    private func feedRow(_ event: CommunityEvent) -> some View {
        let user = online.profile(of: event.userID)
        return HStack(spacing: 12) {
            AvatarView(profile: user, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(feedText(event, name: user?.displayName ?? "Jemand"))
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.muted)
                    .lineLimit(2)
                Text(Self.relative(event.date))
                    .font(Theme.Font.sans(11))
                    .foregroundStyle(Theme.Palette.muted3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { selectedUserID = event.userID }
    }

    private func feedText(_ event: CommunityEvent, name: String) -> String {
        switch event.kind {
        case .sessionStarted:
            return "\(name) hat eine Session gestartet"
        case .sessionCompleted(let minutes, let title):
            return "\(name) hat \(minutes) Min fokussiert — „\(title)“"
        case .achievementEarned(let id):
            let title = Achievement.byID(id)?.title ?? "einen Erfolg"
            return "\(name) hat „\(title)“ erreicht"
        case .packUnlocked(let packName):
            return "\(name) hat das Paket „\(packName)“ freigeschaltet"
        }
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Live-Zeile

private struct LiveRow: View {
    @EnvironmentObject var online: OnlineModel
    let entry: OnlineModel.LiveEntry
    let isSelf: Bool
    let isFriend: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Avatar mit Fortschrittsring der laufenden Session.
            ZStack {
                Circle()
                    .stroke(Theme.Palette.progressTrack, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.02, entry.status.progress))
                    .stroke(Theme.Palette.live, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                AvatarView(profile: entry.profile, size: 44)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(isSelf ? "Du" : entry.profile.displayName)
                        .font(Theme.Font.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(1)
                    if case .paused = entry.presence {
                        Text("· pausiert")
                            .font(Theme.Font.sans(12))
                            .foregroundStyle(Theme.Palette.muted3)
                    }
                }
                Text("Runde \(entry.status.round) von \(entry.status.totalRounds) · \(entry.status.artworkTitle)")
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Palette.muted2)
                    .lineLimit(1)
                Text("seit \(Self.elapsed(entry.status.startedAt))")
                    .font(Theme.Font.sans(11))
                    .foregroundStyle(Theme.Palette.muted3)
            }

            Spacer(minLength: 0)

            if !isSelf, isFriend {
                // Interaktiv anfeuern — ein Tipp schickt den Nudge.
                Menu {
                    ForEach(Nudge.allCases) { nudge in
                        Button("\(nudge.emoji) \(nudge.label)") {
                            online.send(.nudge(nudge), to: entry.profile.id)
                        }
                    }
                } label: {
                    Image(systemName: "hands.clap")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Palette.accent)
                        .frame(width: 38, height: 38)
                        .background(Theme.Palette.surface2)
                        .clipShape(Circle())
                }
            }
        }
        .padding(12)
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                .stroke(Theme.Palette.hairline2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if !isSelf { onOpen() } }
    }

    private static func elapsed(_ start: Date) -> String {
        let minutes = max(1, Int(Date().timeIntervalSince(start) / 60))
        return minutes < 60 ? "\(minutes) Min" : "\(minutes / 60) Std \(minutes % 60) Min"
    }
}
