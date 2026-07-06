import SwiftUI
import Photos

/// Screen 9 — full-bleed work detail with metadata.
struct ArtworkDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let artwork: Artwork

    private enum SaveState { case idle, saved, denied, failed }
    @State private var saveState: SaveState = .idle

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
                // (Overlay pattern: the fill image must not drive the layout width.)
                Color.clear
                    .frame(height: 470)
                    .frame(maxWidth: .infinity)
                    .overlay(ArtworkImage(assetName: artwork.assetName, contentMode: .fill))
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

                    GhostButton(title: saveButtonTitle,
                                icon: saveState == .saved ? "checkmark" : "photo.badge.arrow.down") {
                        saveToPhotos()
                    }
                    .padding(.top, 22)

                    if saveState == .saved {
                        Text("Fotos öffnen → Teilen → „Als Hintergrundbild“ wählen.")
                            .font(Theme.Font.sans(12))
                            .foregroundStyle(Theme.Palette.muted2)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, 34)
                .padding(.top, 4)
            }
        }
        .background(Theme.Palette.paper)
        .alert("Kein Zugriff auf Fotos", isPresented: .init(
            get: { saveState == .denied },
            set: { if !$0 { saveState = .idle } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Erlaube FocusPiece in den iOS-Einstellungen, Bilder zu deiner Mediathek hinzuzufügen.")
        }
    }

    private var saveButtonTitle: String {
        switch saveState {
        case .saved:  return "In Fotos gespeichert"
        case .failed: return "Speichern fehlgeschlagen"
        default:      return "Als Sperrbildschirm sichern"
        }
    }

    /// Saves the painting to the photo library (add-only access), from where
    /// iOS lets the user set it as wallpaper.
    private func saveToPhotos() {
        guard saveState != .saved, let image = ArtworkImage.load(artwork.assetName) else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { saveState = .denied }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                DispatchQueue.main.async { saveState = success ? .saved : .failed }
            }
        }
    }

    private var unlockedDateText: String {
        guard let d = artwork.unlockedDate else { return "—" }
        return Self.dateFormatter.string(from: d)
    }
    private var sessionText: String {
        guard let m = artwork.sessionMinutes else { return "—" }
        return m == 1 ? "1 Minute" : "\(m) Minuten"
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
