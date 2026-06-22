import SwiftUI

/// Screen 9 — full-bleed work detail with metadata.
struct ArtworkDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let artwork: Artwork

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMMM yyyy"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Full image header with back button.
                ArtworkImage(assetName: artwork.assetName, contentMode: .fill)
                    .frame(height: 470)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: Color(hex: 0x14110D).opacity(0.32), location: 0.0),
                                .init(color: Color(hex: 0x14110D).opacity(0.0), location: 0.26),
                                .init(color: Theme.Palette.paper.opacity(0), location: 0.80),
                                .init(color: Theme.Palette.paper, location: 1.0),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .topLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Color(hex: 0x14110D).opacity(0.4))
                                .background(.ultraThinMaterial, in: Circle())
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 24).padding(.top, 8)
                    }
                    .ignoresSafeArea(edges: .top)

                VStack(alignment: .leading, spacing: 0) {
                    Text(artwork.title)
                        .font(Theme.Font.serif(34))
                        .tracking(-0.3)
                        .foregroundStyle(Theme.Palette.ink)
                        .padding(.bottom, 6)
                    Text(artwork.attribution)
                        .font(Theme.Font.serifItalic(16))
                        .foregroundStyle(Theme.Palette.artistInk)
                        .padding(.bottom, 20)
                    Text(artwork.blurb)
                        .font(Theme.Font.sans(15))
                        .lineSpacing(6)
                        .foregroundStyle(Theme.Palette.bodySoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 24)

                    VStack(spacing: 0) {
                        metaRow("Freigeschaltet", unlockedDateText)
                        metaRow("Fokus-Session", sessionText)
                        metaRow("Sammlung", artwork.collectionTag)
                    }
                    .overlay(Rectangle().fill(Theme.Palette.hairline).frame(height: 1), alignment: .top)

                    GhostButton(title: "Als Sperrbildschirm setzen") { }
                        .padding(.top, 22).padding(.bottom, 30)
                }
                .padding(.horizontal, 34)
                .padding(.top, 4)
            }
        }
        .background(Theme.Palette.paper)
    }

    private var unlockedDateText: String {
        guard let d = artwork.unlockedDate else { return "—" }
        return Self.dateFormatter.string(from: d)
    }
    private var sessionText: String {
        guard let m = artwork.sessionMinutes else { return "—" }
        return "\(m) Minuten"
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.sans(15))
                .foregroundStyle(Theme.Palette.muted2)
            Spacer()
            Text(value)
                .font(Theme.Font.sans(15, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(.vertical, 15)
        .overlay(Rectangle().fill(Theme.Palette.hairline).frame(height: 1), alignment: .bottom)
    }
}
