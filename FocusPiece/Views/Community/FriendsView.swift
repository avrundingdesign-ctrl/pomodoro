import SwiftUI

/// Freunde: offene Anfragen, die eigene Liste (mit Live-Status und Chat)
/// und die Suche über die Community.
struct FriendsView: View {
    @EnvironmentObject var online: OnlineModel

    @State private var search = ""
    @State private var requestedIDs: Set<String> = []
    @State private var selectedUserID: String?
    @State private var chatPartner: UserProfile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !online.requests.isEmpty {
                    sectionTitle("Anfragen")
                    VStack(spacing: 10) {
                        ForEach(online.requests) { request in
                            requestCard(request)
                        }
                    }
                }

                sectionTitle("Deine Freunde")
                if online.friends.isEmpty {
                    emptyFriends
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(online.friends.enumerated()), id: \.element.id) { idx, friend in
                            friendRow(friend)
                            if idx < online.friends.count - 1 {
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

                sectionTitle("Community entdecken")
                searchField
                VStack(spacing: 10) {
                    ForEach(filteredSuggestions) { user in
                        suggestionRow(user)
                    }
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
        .sheet(item: $chatPartner) { partner in
            NavigationStack {
                ChatView(partner: partner)
            }
        }
    }

    private struct SheetID: Identifiable { let id: String }

    private var filteredSuggestions: [UserProfile] {
        let pool = online.suggestions
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return Array(pool.prefix(5)) }
        return pool.filter {
            $0.displayName.lowercased().contains(query) || $0.handle.contains(query)
        }
    }

    // MARK: Bausteine

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.Font.sans(11, weight: .semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Palette.muted3)
            .padding(.leading, 12)
    }

    private func requestCard(_ request: FriendRequest) -> some View {
        HStack(spacing: 12) {
            AvatarView(profile: request.from, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.from.displayName)
                    .font(Theme.Font.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("\(request.from.handleLabel) · \(request.from.city.name)")
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Palette.muted2)
            }
            Spacer()
            Button {
                Feedback.tap(true)
                online.respond(to: request, accept: true)
            } label: {
                Text("Annehmen")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Theme.Palette.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Button {
                online.respond(to: request, accept: false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.muted2)
                    .frame(width: 34, height: 34)
                    .background(Theme.Palette.surface2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                .stroke(Theme.Palette.accent.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }

    private func friendRow(_ friend: UserProfile) -> some View {
        let presence = online.presence(of: friend.id)
        let unread = online.unreadCount(with: friend.id)
        return HStack(spacing: 12) {
            AvatarView(profile: friend, size: 46, presence: presence)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(Theme.Font.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(presence.isInSession
                     ? "Fokussiert · \(presence.focusStatus?.artworkTitle ?? "")"
                     : presence.label)
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(presence.isInSession ? Theme.Palette.live : Theme.Palette.muted3)
                    .lineLimit(1)
            }
            Spacer()
            if unread > 0 {
                Text("\(unread)")
                    .font(Theme.Font.sans(11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Theme.Palette.accent)
                    .clipShape(Circle())
            }
            Button {
                chatPartner = friend
            } label: {
                Image(systemName: "bubble.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.Palette.surface2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { selectedUserID = friend.id }
    }

    private func suggestionRow(_ user: UserProfile) -> some View {
        let requested = requestedIDs.contains(user.id)
        return HStack(spacing: 12) {
            AvatarView(profile: user, size: 46, presence: online.presence(of: user.id))
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(Theme.Font.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("\(user.handleLabel) · \(user.city.name)")
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Palette.muted2)
            }
            Spacer()
            Button {
                online.sendFriendRequest(to: user.id)
                requestedIDs.insert(user.id)
            } label: {
                Text(requested ? "Angefragt ✓" : "Hinzufügen")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(requested ? Theme.Palette.muted3 : Theme.Palette.accent)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(Theme.Palette.surface2)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(requested)
        }
        .padding(12)
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                .stroke(Theme.Palette.hairline2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { selectedUserID = user.id }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Palette.muted3)
            TextField("Name oder @nutzername", text: $search)
                .font(Theme.Font.sans(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.Palette.hairline2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyFriends: some View {
        Text("Noch keine Freunde — schick unten eine Anfrage. Die Community freut sich.")
            .font(Theme.Font.sans(13))
            .foregroundStyle(Theme.Palette.muted2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                    .stroke(Theme.Palette.hairline2, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }
}
