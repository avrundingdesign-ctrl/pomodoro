import SwiftUI
import Photos

/// Screen 9 — full-bleed work detail with metadata.
struct ArtworkDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let artwork: Artwork
    @State private var showInfo = false
    @State private var saveState: SaveState = .idle

    /// iOS gives apps no way to set the wallpaper themselves, so the button
    /// puts the painting in the photo library and points the way from there.
    private enum SaveState: Equatable { case idle, saving, saved, denied, failed }

    /// "7. August 2026" / "August 7, 2026" — the locale picks the order.
    private static let dateStyle = Date.FormatStyle(date: .long, time: .omitted)

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
                    .overlay(alignment: .topTrailing) {
                        Button { showInfo = true } label: {
                            Image(systemName: "info")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Color(hex: 0x14110D).opacity(0.4))
                                .background(.ultraThinMaterial, in: Circle())
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("detail.info")
                        .accessibilityLabel("Werkinfo")
                        .padding(.trailing, 24).padding(.top, 8)
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

                    saveSection
                        .padding(.top, 22).padding(.bottom, 30)
                }
                .padding(.horizontal, 34)
                .padding(.top, 4)
                .contentColumn()
            }
        }
        .background(Theme.Palette.paper)
        .sheet(isPresented: $showInfo) {
            ArtworkInfoSheet(artwork: artwork)
        }
    }

    private var unlockedDateText: String {
        guard let d = artwork.unlockedDate else { return "—" }
        return d.formatted(Self.dateStyle)
    }
    private var sessionText: String {
        guard let m = artwork.sessionMinutes else { return "—" }
        return String(localized: "\(m) Minuten")
    }

    /// Save button plus its result line. Kept out of `body` so the type
    /// checker doesn't have to solve it together with the header chain.
    @ViewBuilder private var saveSection: some View {
        let title: LocalizedStringKey = saveState == .saving
            ? "Wird gesichert…"
            : "Als Sperrbildschirm sichern"

        VStack(spacing: 10) {
            GhostButton(title: title) {
                Task { await saveToPhotos() }
            }
            .disabled(saveState == .saving)
            .accessibilityIdentifier("detail.saveWallpaper")

            if let note = saveNote {
                Text(note)
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(noteColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noteColor: Color {
        saveState == .saved ? Theme.Palette.muted2 : Theme.Palette.accent
    }

    /// Feedback under the button — nil while nothing has been attempted.
    private var saveNote: LocalizedStringKey? {
        switch saveState {
        case .idle, .saving: return nil
        case .saved:         return "In Fotos gesichert — dort als Sperrbildschirm festlegen."
        case .denied:        return "FocusPiece darf keine Fotos sichern. In den Einstellungen erlauben."
        case .failed:        return "Das Bild konnte nicht gesichert werden."
        }
    }

    /// Add-only access is enough — the app never reads the user's library.
    private func saveToPhotos() async {
        guard let image = ArtworkImage.load(artwork.assetName) else {
            saveState = .failed
            return
        }
        saveState = .saving

        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else {
            saveState = .denied
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            saveState = .saved
        } catch {
            saveState = .failed
        }
    }

    private func metaRow(_ label: LocalizedStringKey, _ value: String) -> some View {
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
