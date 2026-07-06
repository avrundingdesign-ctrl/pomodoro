import SwiftUI

/// Community-Tab: Live-Übersicht, Karte und Freunde — plus Nachrichten-Inbox.
struct CommunityView: View {
    @EnvironmentObject var online: OnlineModel

    private enum Segment: String, CaseIterable {
        case live = "Live", map = "Karte", friends = "Freunde"
    }
    @State private var segment: Segment = .live
    @State private var showInbox = false

    var body: some View {
        VStack(spacing: 0) {
            header
            OnlineGate {
                VStack(spacing: 0) {
                    segmentPicker
                        .padding(.horizontal, 28)
                        .padding(.bottom, 14)
                    switch segment {
                    case .live:    LiveNowView()
                    case .map:     CommunityMapView()
                    case .friends: FriendsView()
                    }
                }
            }
        }
        .background(Theme.Palette.paper)
        .sheet(isPresented: $showInbox) {
            MessagesInboxView()
        }
    }

    private var header: some View {
        HStack {
            Text("Community")
                .font(Theme.Font.serif(32))
                .tracking(-0.3)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            if online.isSignedIn {
                CircleIconButton(systemName: "envelope") { showInbox = true }
                    .overlay(alignment: .topTrailing) {
                        if online.totalUnread > 0 {
                            Text("\(min(online.totalUnread, 9))")
                                .font(Theme.Font.sans(10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 17, height: 17)
                                .background(Theme.Palette.accent)
                                .clipShape(Circle())
                                .offset(x: 3, y: -3)
                        }
                    }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8).padding(.bottom, 16)
    }

    private var segmentPicker: some View {
        HStack(spacing: 0) {
            ForEach(Segment.allCases, id: \.self) { s in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { segment = s }
                } label: {
                    Text(s.rawValue)
                        .font(Theme.Font.sans(14, weight: .semibold))
                        .foregroundStyle(segment == s ? Theme.Palette.ink : Theme.Palette.muted3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(segment == s ? Theme.Palette.surface : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.Palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
