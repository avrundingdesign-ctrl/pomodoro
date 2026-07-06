import SwiftUI

/// Screen 8 — the collection grid. Unlocked tiles show the work; locked tiles
/// are blurred behind a lock.
struct GalleryView: View {
    @EnvironmentObject var app: AppModel
    @State private var selected: Artwork?

    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(app.collection) { art in
                        GalleryTile(artwork: art)
                            .onTapGesture { if art.unlocked { selected = art } }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.Palette.paper)
        .sheet(item: $selected) { art in
            ArtworkDetailView(artwork: art)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Galerie")
                    .font(Theme.Font.serif(32))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.Palette.ink)
                Text("\(app.unlockedCount) von \(app.totalCount) Werken enthüllt")
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Palette.muted2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(app.focusTimeLabel)
                    .font(Theme.Font.sans(13, weight: .medium))
                    .foregroundStyle(Theme.Palette.accent)
                if app.streakDays >= 2 {
                    Text("\(app.streakDays) Tage in Folge")
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Palette.muted2)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }
}

private struct GalleryTile: View {
    let artwork: Artwork

    var body: some View {
        // Overlay pattern: the tile's size comes from the grid column + aspect
        // ratio alone — the fill image must not drive the layout width.
        Color.clear
            .aspectRatio(3.0/4.0, contentMode: .fit)
            .overlay(tileContent)
            .background(Theme.Palette.hairline)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.galleryTile, style: .continuous))
    }

    private var tileContent: some View {
        ZStack {
            // Same trick one level down: the image must not inflate the ZStack.
            Color.clear
                .overlay(ArtworkImage(assetName: artwork.assetName, contentMode: .fill))

            if artwork.unlocked {
                // Title overlay at the bottom.
                VStack(alignment: .leading, spacing: 3) {
                    Spacer()
                    Text(artwork.title)
                        .font(Theme.Font.serif(15, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(artwork.artist)
                        .font(Theme.Font.sans(11))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13).padding(.bottom, 13).padding(.top, 30)
                .background(
                    LinearGradient(colors: [Color(hex: 0x14110D).opacity(0),
                                            Color(hex: 0x14110D).opacity(0.82)],
                                   startPoint: .top, endPoint: .bottom)
                )
            } else {
                // Locked — blurred veil + lock.
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Theme.Palette.paper.opacity(0.4)
                    VStack(spacing: 10) {
                        Image(systemName: "lock")
                            .font(.system(size: 21, weight: .regular))
                            .foregroundStyle(Theme.Palette.artistInk)
                        Text("Fokussiere, um\nfreizuschalten")
                            .multilineTextAlignment(.center)
                            .font(Theme.Font.sans(12, weight: .medium))
                            .foregroundStyle(Theme.Palette.muted)
                    }
                    .padding(16)
                }
            }
        }
    }
}
