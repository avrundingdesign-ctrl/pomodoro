import SwiftUI
import UIKit

/// Loads a bundled painting JPG by base name. If the file isn't bundled yet
/// (run Scripts/fetch_artworks.sh), it renders a calm placeholder so the app
/// still builds and runs.
struct ArtworkImage: View {
    let assetName: String
    var contentMode: ContentMode = .fill

    var body: some View {
        if let ui = Self.load(assetName) {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            ArtworkPlaceholder(seed: assetName)
        }
    }

    /// First try the asset catalog, then a loose bundled `<name>.jpg`/`.png`.
    static func load(_ name: String) -> UIImage? {
        if let img = UIImage(named: name) { return img }
        for ext in ["jpg", "jpeg", "png"] {
            if let path = Bundle.main.path(forResource: name, ofType: ext),
               let img = UIImage(contentsOfFile: path) {
                return img
            }
        }
        return nil
    }
}

/// A quiet, deterministic gradient stand-in for a not-yet-bundled painting.
struct ArtworkPlaceholder: View {
    let seed: String

    private var hue: Double { Double(abs(seed.hashValue) % 360) / 360.0 }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.18, brightness: 0.42),
                    Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.22, brightness: 0.28)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "photo.artframe")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}
