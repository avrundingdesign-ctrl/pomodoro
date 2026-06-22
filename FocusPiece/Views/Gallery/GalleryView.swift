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
            Text("\(app.totalFocusHours) Std Fokus")
                .font(Theme.Font.sans(13, weight: .medium))
                .foregroundStyle(Theme.Palette.accent)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }
}

private struct GalleryTile: View {
    let artwork: Artwork

    var body: some View {
        ZStack {
            ArtworkImage(assetName: artwork.assetName, contentMode: .fill)

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
        .aspectRatio(3.0/4.0, contentMode: .fill)
        .background(Theme.Palette.hairline)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.galleryTile, style: .continuous))
    }
}
