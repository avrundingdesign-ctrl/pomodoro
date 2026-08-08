import SwiftUI

/// The ⓘ sheet: curator's notes for any work in the gallery — artist, year,
/// movement, the set ("Bildband") it belongs to, and the story of the piece.
/// Available for locked works too; only the image itself stays a secret.
struct ArtworkInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let artwork: Artwork

    private var packTitle: String {
        ArtworkCatalog.pack(id: artwork.packID)?.title ?? ArtworkCatalog.freePack.title
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("WERKINFO").eyebrow()
                    Spacer()
                    CircleIconButton(systemName: "xmark") { dismiss() }
                        .accessibilityIdentifier("info.close")
                }
                .padding(.bottom, 14)

                Text(artwork.title)
                    .font(Theme.Font.serif(28))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("info.title")
                Text(artwork.attribution)
                    .font(Theme.Font.serifItalic(15))
                    .foregroundStyle(Theme.Palette.artistInk)
                    .padding(.bottom, 16)

                Text(artwork.blurb)
                    .font(Theme.Font.sans(15))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.Palette.bodySoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22)

                VStack(spacing: 0) {
                    row("Künstler", artwork.artist)
                    row("Entstanden", artwork.year)
                    row("Epoche", artwork.collectionTag)
                    row("Bildband", packTitle)
                    row("Quelle", String(localized: "Public Domain · Wikimedia Commons"), last: true)
                }
                .padding(.horizontal, 16)
                .background(Theme.Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                        .stroke(Theme.Palette.hairline2, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
            }
            .padding(.horizontal, Theme.Pad.screenH)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .background(Theme.Palette.paper)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ label: LocalizedStringKey, _ value: String, last: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Theme.Font.sans(14))
                .foregroundStyle(Theme.Palette.muted2)
            Spacer(minLength: 16)
            Text(value)
                .font(Theme.Font.sans(14, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Theme.Palette.hairline).frame(height: 1) }
        }
    }
}
