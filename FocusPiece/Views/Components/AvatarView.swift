import SwiftUI
import UIKit

/// Profilbild: Foto (falls gesetzt) oder farbiges Monogramm aus den Initialen.
/// Optional mit Presence-Indikator (grün = in Session, Punkt = online).
struct AvatarView: View {
    let profile: UserProfile?
    var size: CGFloat = 44
    var presence: Presence? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatar
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(ringColor, lineWidth: ringWidth)
                )
            if let presence, presence != .offline {
                Circle()
                    .fill(presence.isInSession ? Theme.Palette.live : Theme.Palette.muted3Soft)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().stroke(Theme.Palette.paper, lineWidth: 2))
            }
        }
    }

    @ViewBuilder private var avatar: some View {
        if let data = profile?.photoData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                monogramColor
                Text(initials)
                    .font(Theme.Font.serif(size * 0.4, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    private var initials: String {
        let parts = (profile?.displayName ?? "?").split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// Ruhige, museale Monogramm-Farben — stabil pro Nutzer-ID.
    private var monogramColor: Color {
        let palette: [UInt] = [0x8C7A5B, 0x6B7A8C, 0x7A8C6B, 0x8C6B7A, 0x5B6E8C, 0xA3835B, 0x6E8C85]
        let idx = abs((profile?.id ?? "x").hashValue) % palette.count
        return Color(hex: palette[idx])
    }

    private var ringColor: Color {
        guard let presence else { return Theme.Palette.cardBorder }
        return presence.isInSession ? Theme.Palette.live : Theme.Palette.cardBorder
    }
    private var ringWidth: CGFloat { (presence?.isInSession ?? false) ? 2 : 1 }
}

/// Fotos aus dem Picker auf Avatar-Größe eindampfen (max. 256px, JPEG) —
/// klein genug für die lokale Persistenz und später für Firestore/Storage.
enum AvatarImage {
    static func downscaled(_ data: Data, maxSide: CGFloat = 256) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
