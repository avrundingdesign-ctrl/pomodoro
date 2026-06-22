import SwiftUI

/// The reveal mechanic — the heart of FocusPiece.
///
/// A sharp painting sits underneath a 4-column × 5-row = 20-tile grid.
/// Hidden tiles show a blurred copy of the underlying region (blur 8) plus a
/// faint paper veil; revealed tiles show the sharp image. Tiles turn sharp one
/// at a time, in the fixed scattered order from `SessionModel.revealOrder`, as
/// `revealedCount` rises with the timer.
struct RevealGridView: View {
    let assetName: String
    let revealedCount: Int

    private let columns = 4
    private let rows = 5

    /// The set of tile indices (0…19, row-major) that are currently sharp.
    private var revealedTiles: Set<Int> {
        Set(SessionModel.revealOrder.prefix(revealedCount))
    }

    var body: some View {
        ZStack {
            // Base — the sharp painting.
            ArtworkImage(assetName: assetName, contentMode: .fill)

            // Blurred copy + paper veil, masked to only the hidden tiles.
            ZStack {
                ArtworkImage(assetName: assetName, contentMode: .fill)
                    .blur(radius: 8)
                Theme.Palette.revealVeil
            }
            .mask(tileMask)
        }
        .clipped()
    }

    /// A grid of rectangles: opaque over hidden tiles, clear over revealed ones.
    /// Animating each tile's opacity gives the soft ease-in-out reveal.
    private var tileMask: some View {
        GeometryReader { geo in
            let w = geo.size.width / CGFloat(columns)
            let h = geo.size.height / CGFloat(rows)
            ForEach(0..<(rows * columns), id: \.self) { index in
                let col = index % columns
                let row = index / columns
                Rectangle()
                    .fill(.black)
                    .frame(width: w, height: h)
                    .opacity(revealedTiles.contains(index) ? 0 : 1)
                    .position(x: w * (CGFloat(col) + 0.5), y: h * (CGFloat(row) + 0.5))
                    .animation(.easeInOut(duration: 0.55), value: revealedCount)
            }
        }
    }
}
