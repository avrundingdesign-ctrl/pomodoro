import SwiftUI

/// Screen 8 — the collection grid plus the shop shelf. Unlocked tiles show the
/// work; locked tiles are blurred behind a lock. Every tile — locked or not —
/// carries an ⓘ that opens the work's info sheet. Below the collection, the
/// purchasable sets appear as quiet teasers leading into the paywall.
struct GalleryView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: StoreModel
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case detail(Artwork)
        case info(Artwork)
        case paywall

        var id: String {
            switch self {
            case .detail(let a): return "detail.\(a.id)"
            case .info(let a):   return "info.\(a.id)"
            case .paywall:       return "paywall"
            }
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(app.collection) { art in
                        tile(for: art)
                            .overlay(alignment: .topTrailing) {
                                TileInfoButton(identifier: "gallery.info.\(art.id)") {
                                    activeSheet = .info(art)
                                }
                            }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)

                if !app.purchasablePacks.isEmpty {
                    shopShelf
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                }

                Spacer().frame(height: 24)
            }
        }
        .background(Theme.Palette.paper)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .detail(let art):  ArtworkDetailView(artwork: art)
            case .info(let art):    ArtworkInfoSheet(artwork: art)
            case .paywall:          PaywallView()
            }
        }
    }

    @ViewBuilder private func tile(for art: Artwork) -> some View {
        if art.unlocked {
            Button { activeSheet = .detail(art) } label: { GalleryTile(artwork: art) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("gallery.tile.unlocked.\(art.id)")
        } else {
            GalleryTile(artwork: art)
                .accessibilityIdentifier("gallery.tile.locked.\(art.id)")
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
                    .accessibilityIdentifier("gallery.count")
            }
            Spacer()
            Text("\(app.totalFocusHours) Std Fokus")
                .font(Theme.Font.sans(13, weight: .medium))
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityIdentifier("gallery.hours")
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    // MARK: Shop shelf — the purchasable sets

    private var shopShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEUE WERKE").eyebrow()
                Text("Sammlung erweitern")
                    .font(Theme.Font.serif(22))
                    .foregroundStyle(Theme.Palette.ink)
            }

            ForEach(app.purchasablePacks) { pack in
                packTeaser(pack)
            }
        }
    }

    private func packTeaser(_ pack: ArtworkPack) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.title)
                        .font(Theme.Font.serif(19))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(pack.tagline)
                        .font(Theme.Font.serifItalic(13))
                        .foregroundStyle(Theme.Palette.artistInk)
                }
                Spacer()
                Text(store.product(for: pack)?.displayPrice ?? "…")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.Palette.surface2)
                    .clipShape(Capsule())
            }

            // Veiled previews — ⓘ tells the story, the image stays a promise.
            HStack(spacing: 10) {
                ForEach(pack.works) { work in
                    ShopThumb(artwork: work) {
                        activeSheet = .info(work)
                    }
                }
            }

            Button { activeSheet = .paywall } label: {
                Text("Set entdecken")
                    .font(Theme.Font.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.primaryButton, style: .continuous)
                            .stroke(Color(hex: 0xDDD5C7), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gallery.shop.\(pack.id)")
        }
        .padding(16)
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                .stroke(Theme.Palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }
}

// MARK: - Tiles

/// Small ⓘ affordance layered over a tile or thumbnail.
private struct TileInfoButton: View {
    var identifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 27, height: 27)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("Werkinfo")
    }
}

/// Veiled shop preview with its own ⓘ.
private struct ShopThumb: View {
    let artwork: Artwork
    let onInfo: () -> Void

    var body: some View {
        ZStack {
            ArtworkImage(assetName: artwork.assetName, contentMode: .fill)
            Rectangle().fill(.ultraThinMaterial)
            Theme.Palette.paper.opacity(0.35)
            Button(action: onInfo) {
                Image(systemName: "info")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: 23, height: 23)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gallery.shopinfo.\(artwork.id)")
            .accessibilityLabel("Werkinfo")
        }
        .aspectRatio(3.0/4.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
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
