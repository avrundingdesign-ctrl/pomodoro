import SwiftUI

/// Chat mit einem Freund: Text, interaktive Nudges und Kunstgrüße
/// (ein enthülltes Werk als kleine Karte).
struct ChatView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var online: OnlineModel

    let partner: UserProfile
    @State private var draft = ""

    private var messages: [ChatMessage] { online.chats[partner.id] ?? [] }
    private var myID: String { online.profile?.id ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .onAppear {
                    online.markThreadRead(with: partner.id)
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: messages.count) { _, _ in
                    online.markThreadRead(with: partner.id)
                    if let last = messages.last {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            nudgeBar
            inputBar
        }
        .background(Theme.Palette.paper)
        .navigationTitle(partner.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Bubbles

    @ViewBuilder private func bubble(_ message: ChatMessage) -> some View {
        let mine = message.senderID == myID
        HStack {
            if mine { Spacer(minLength: 48) }
            bubbleContent(message, mine: mine)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !mine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    @ViewBuilder private func bubbleContent(_ message: ChatMessage, mine: Bool) -> some View {
        switch message.kind {
        case .text(let text):
            Text(text)
                .font(Theme.Font.sans(15))
                .foregroundStyle(mine ? .white : Theme.Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(mine ? Theme.Palette.accent : Theme.Palette.surface2)
        case .nudge(let nudge):
            VStack(spacing: 4) {
                Text(nudge.emoji)
                    .font(.system(size: 30))
                Text(nudge.line)
                    .font(Theme.Font.sans(13, weight: .medium))
                    .foregroundStyle(mine ? .white : Theme.Palette.ink)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(mine ? Theme.Palette.accent : Theme.Palette.surface2)
        case .artCard(let assetName, let title):
            VStack(alignment: .leading, spacing: 0) {
                ArtworkImage(assetName: assetName, contentMode: .fill)
                    .frame(width: 190, height: 130)
                    .clipped()
                HStack(spacing: 6) {
                    Image(systemName: "photo.artframe")
                        .font(.system(size: 11))
                    Text(title)
                        .font(Theme.Font.serifItalic(13))
                        .lineLimit(1)
                }
                .foregroundStyle(mine ? .white : Theme.Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(width: 190, alignment: .leading)
                .background(mine ? Theme.Palette.accent : Theme.Palette.surface2)
            }
        }
    }

    // MARK: Eingabe

    /// Ein Tipp genügt: schnelle interaktive Reaktionen.
    private var nudgeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Nudge.allCases) { nudge in
                    Button {
                        Feedback.tap(app.settings.haptics)
                        online.send(.nudge(nudge), to: partner.id)
                    } label: {
                        HStack(spacing: 5) {
                            Text(nudge.emoji)
                            Text(nudge.label)
                                .font(Theme.Font.sans(12, weight: .medium))
                                .foregroundStyle(Theme.Palette.muted)
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(Theme.Palette.surface2)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            // Kunstgruß: ein enthülltes Werk verschicken.
            Menu {
                let unlocked = app.collection.filter(\.unlocked)
                if unlocked.isEmpty {
                    Button("Erst ein Werk enthüllen …") {}.disabled(true)
                } else {
                    ForEach(unlocked.prefix(10)) { artwork in
                        Button(artwork.title) {
                            online.send(.artCard(assetName: artwork.assetName,
                                                 title: artwork.title), to: partner.id)
                        }
                    }
                }
            } label: {
                Image(systemName: "photo.artframe")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.Palette.surface2)
                    .clipShape(Circle())
            }

            TextField("Nachricht …", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(Theme.Font.sans(15))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.Palette.hairline2, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                sendText()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(canSend ? Theme.Palette.accent : Theme.Palette.toggleOff)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendText() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Feedback.tap(app.settings.haptics)
        online.send(.text(text), to: partner.id)
        draft = ""
    }
}

// MARK: - Inbox

/// Nachrichten-Übersicht: alle Chats, sortiert nach der letzten Nachricht.
struct MessagesInboxView: View {
    @EnvironmentObject var online: OnlineModel
    @Environment(\.dismiss) private var dismiss

    private var threads: [(partner: UserProfile, last: ChatMessage?)] {
        online.friends
            .map { ($0, online.chats[$0.id]?.last) }
            .sorted { ($0.1?.sentAt ?? .distantPast) > ($1.1?.sentAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if online.friends.isEmpty {
                    Text("Füge Freunde hinzu, um Nachrichten zu schreiben.")
                        .font(Theme.Font.sans(14))
                        .foregroundStyle(Theme.Palette.muted2)
                        .padding(28)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(threads, id: \.partner.id) { thread in
                                NavigationLink {
                                    ChatView(partner: thread.partner)
                                } label: {
                                    inboxRow(thread.partner, last: thread.last)
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(Theme.Palette.hairline3)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.Palette.paper)
            .navigationTitle("Nachrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func inboxRow(_ partner: UserProfile, last: ChatMessage?) -> some View {
        let unread = online.unreadCount(with: partner.id)
        return HStack(spacing: 12) {
            AvatarView(profile: partner, size: 48, presence: online.presence(of: partner.id))
            VStack(alignment: .leading, spacing: 3) {
                Text(partner.displayName)
                    .font(Theme.Font.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(last.map(Self.preview) ?? "Sag Hallo!")
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.muted2)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                if let last {
                    Text(LiveNowView.relative(last.sentAt))
                        .font(Theme.Font.sans(11))
                        .foregroundStyle(Theme.Palette.muted3)
                }
                if unread > 0 {
                    Text("\(unread)")
                        .font(Theme.Font.sans(11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Theme.Palette.accent)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private static func preview(_ message: ChatMessage) -> String {
        switch message.kind {
        case .text(let text): return text
        case .nudge(let nudge): return "\(nudge.emoji) \(nudge.line)"
        case .artCard(_, let title): return "🖼️ \(title)"
        }
    }
}
