import SwiftUI

/// Screen 7 — the work is fully revealed and unlocked.
struct CompletionView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.horizontalSizeClass) private var hSize
    @ObservedObject var session: SessionModel
    let onDone: () -> Void

    @State private var shareImage: UIImage?

    /// Ordinal this work takes in the collection ("7. Werk gesammelt") —
    /// the unlock already happened when the last round completed.
    private var collectedOrdinal: Int { max(1, app.unlockedCount) }
    /// Free session over an already collected work (everything unlocked).
    private var isFreeSession: Bool { session.isFreeSession }

    /// "7." in German, "7th" in English — the locale decides.
    private static let ordinalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f
    }()
    private var ordinalText: String {
        Self.ordinalFormatter.string(from: NSNumber(value: collectedOrdinal))
            ?? "\(collectedOrdinal)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sharp full painting with a wash to paper at the bottom.
            // (Overlay pattern: the fill image must not drive the layout width.)
            Color.clear
                .frame(height: hSize == .regular ? 620 : 486)
                .frame(maxWidth: .infinity)
                .overlay(ArtworkImage(assetName: session.artwork.assetName, contentMode: .fill))
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
                    stat(value: "\(session.cycleFocusMinutes)",
                         caption: session.totalRounds > 1
                            ? String(localized: "Minuten · \(session.totalRounds) Runden")
                            : String(localized: "Minuten Fokus"))
                    if isFreeSession {
                        stat(value: String(localized: "Frei"),
                             caption: String(localized: "Alle Werke enthüllt"), leadingDivider: true)
                    } else {
                        stat(value: ordinalText,
                             caption: String(localized: "Werk gesammelt"), leadingDivider: true)
                    }
                }
                .overlay(Rectangle().fill(Theme.Palette.hairline).frame(height: 1), alignment: .top)
                .overlay(Rectangle().fill(Theme.Palette.hairline).frame(height: 1), alignment: .bottom)
                .padding(.bottom, 26)

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    PrimaryButton(title: isFreeSession ? "Zurück zur Galerie" : "In Galerie speichern",
                                  action: onDone)
                    HStack(spacing: 12) {
                        // The classic long break after a full cycle — optional.
                        Button {
                            Feedback.tap(app.settings.haptics)
                            session.startLongBreak()
                        } label: {
                            secondaryLabel("\(session.longBreakMinutes) Min Pause")
                        }
                        .buttonStyle(.plain)
                        shareLink
                    }
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 34)
            .padding(.top, 6)
            .contentColumn()
        }
        .onAppear(perform: renderShareCard)
    }

    // MARK: Share
    /// Shares a rendered picture card; falls back to text while rendering.
    @ViewBuilder private var shareLink: some View {
        if let ui = shareImage {
            ShareLink(item: Image(uiImage: ui),
                      preview: SharePreview(session.artwork.title, image: Image(uiImage: ui))) {
                shareLabel
            }
        } else {
            ShareLink(item: shareText) { shareLabel }
        }
    }

    private var shareLabel: some View { secondaryLabel("Teilen") }

    /// Bordered secondary button label (share / long break).
    private func secondaryLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Theme.Font.sans(15, weight: .semibold))
            .foregroundStyle(Theme.Palette.bodySoft)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.primaryButton, style: .continuous)
                    .stroke(Color(hex: 0xDDD5C7), lineWidth: 1)
            )
    }

    private var shareText: String {
        String(localized: "Ich habe gerade „\(session.artwork.title)“ von \(session.artwork.attribution) in FocusPiece enthüllt — nach \(session.cycleFocusMinutes) Minuten Fokus.")
    }

    private func renderShareCard() {
        let renderer = ImageRenderer(content: ShareCardView(
            artwork: session.artwork, minutes: session.cycleFocusMinutes))
        renderer.scale = 3
        renderer.proposedSize = .init(width: 360, height: 480)
        shareImage = renderer.uiImage
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

// MARK: - Share card
/// The picture card rendered for the share sheet (360×480 @3x). Uses fixed
/// light-palette values so the card looks identical regardless of theme.
private struct ShareCardView: View {
    let artwork: Artwork
    let minutes: Int

    var body: some View {
        VStack(spacing: 0) {
            ArtworkImage(assetName: artwork.assetName, contentMode: .fill)
                .frame(width: 360, height: 330)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(artwork.title)
                    .font(Theme.Font.serif(26))
                    .foregroundStyle(Color(hex: 0x2A251F))
                Text(artwork.attribution)
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Color(hex: 0x7D7468))

                Spacer(minLength: 0)

                HStack {
                    Text("\(minutes) MINUTEN FOKUS")
                        .font(Theme.Font.sans(11, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color(hex: 0xC25A35))
                    Spacer()
                    Text("FOCUSPIECE")
                        .font(Theme.Font.sans(11, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(Color(hex: 0xA39A8C))
                }
            }
            .padding(24)
            .frame(width: 360, height: 150, alignment: .topLeading)
            .background(Color(hex: 0xF3EFE7))
        }
        .frame(width: 360, height: 480)
    }
}
