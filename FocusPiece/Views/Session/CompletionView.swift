import SwiftUI

/// Screen 7 — the work is fully revealed and unlocked.
struct CompletionView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.horizontalSizeClass) private var hSize
    @ObservedObject var session: SessionModel
    let onSave: () -> Void

    /// Ordinal this work will take in the collection ("7. Werk gesammelt").
    private var collectedOrdinal: Int { app.unlockedCount + 1 }

    var body: some View {
        VStack(spacing: 0) {
            // Sharp full painting with a wash to paper at the bottom.
            ArtworkImage(assetName: session.artwork.assetName, contentMode: .fill)
                .frame(height: hSize == .regular ? 620 : 486)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0x14110D).opacity(0.28), location: 0.0),
                            .init(color: Color(hex: 0x14110D).opacity(0.0), location: 0.24),
                            .init(color: Theme.Palette.paper.opacity(0), location: 0.70),
                            .init(color: Theme.Palette.paper, location: 1.0),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 0) {
                // "✓ ENTHÜLLT" pill
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("ENTHÜLLT")
                        .font(Theme.Font.sans(12, weight: .semibold))
                        .tracking(0.7)
                }
                .foregroundStyle(Theme.Palette.accent)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Theme.Palette.surface2)
                .clipShape(Capsule())
                .padding(.bottom, 18)

                Text(session.artwork.title)
                    .font(Theme.Font.serif(36))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.bottom, 6)
                Text(session.artwork.attribution)
                    .font(Theme.Font.serifItalic(16))
                    .foregroundStyle(Theme.Palette.artistInk)
                    .padding(.bottom, 22)

                // Stat row with hairline top/bottom.
                HStack(spacing: 0) {
                    stat(value: "\(session.durationMinutes)", caption: "Minuten Fokus")
                    stat(value: "\(collectedOrdinal).", caption: "Werk gesammelt", leadingDivider: true)
                }
                .overlay(Rectangle().fill(Theme.Palette.hairline).frame(height: 1), alignment: .top)
                .overlay(Rectangle().fill(Theme.Palette.hairline).frame(height: 1), alignment: .bottom)
                .padding(.bottom, 26)

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    PrimaryButton(title: "In Galerie speichern", action: onSave)
                    ShareLink(item: shareText) {
                        Text("Teilen")
                            .font(Theme.Font.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.bodySoft)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.primaryButton, style: .continuous)
                                    .stroke(Color(hex: 0xDDD5C7), lineWidth: 1)
                            )
                    }
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 34)
            .padding(.top, 6)
            .contentColumn()
        }
    }

    private var shareText: String {
        "Ich habe gerade „\(session.artwork.title)“ von \(session.artwork.attribution) in FocusPiece enthüllt — nach \(session.durationMinutes) Minuten Fokus."
    }

    private func stat(value: String, caption: String, leadingDivider: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Font.serif(22, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)
            Text(caption)
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Palette.muted2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .padding(.leading, leadingDivider ? 20 : 0)
        .overlay(alignment: .leading) {
            if leadingDivider {
                Rectangle().fill(Theme.Palette.hairline).frame(width: 1)
            }
        }
    }
}
