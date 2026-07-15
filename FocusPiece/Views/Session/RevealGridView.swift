import SwiftUI

/// The reveal mechanic — the heart of FocusPiece.
///
/// A sharp painting sits underneath a 4-column × 5-row = 20-piece jigsaw
/// puzzle. Hidden pieces show a blurred copy of the underlying region (blur 8)
/// plus a faint paper veil; revealed pieces show the sharp image. Pieces turn
/// sharp one at a time, in the fixed scattered order
/// from `SessionModel.revealOrder`, as `revealedCount` rises with the timer.
struct RevealGridView: View {
    let assetName: String
    let revealedCount: Int

    private let columns = 4
    private let rows = 5

    /// The set of piece indices (0…19, row-major) that are currently sharp.
    private var revealedTiles: Set<Int> {
        Set(SessionModel.revealOrder.prefix(revealedCount))
    }

    var body: some View {
        ZStack {
            // Base — the sharp painting.
            ArtworkImage(assetName: assetName, contentMode: .fill)

            // Blurred copy + paper veil, masked to only the hidden pieces.
            ZStack {
                ArtworkImage(assetName: assetName, contentMode: .fill)
                    .blur(radius: 8)
                Theme.Palette.revealVeil
            }
            .mask(pieceMask)
        }
        .clipped()
    }

    /// Jigsaw pieces: opaque over hidden pieces, clear over revealed ones.
    /// Animating each piece's opacity gives the soft ease-in-out reveal.
    private var pieceMask: some View {
        ZStack {
            ForEach(0..<(rows * columns), id: \.self) { index in
                pieceShape(index)
                    .fill(.black)
                    .opacity(revealedTiles.contains(index) ? 0 : 1)
                    .animation(.easeInOut(duration: 0.55), value: revealedCount)
            }
        }
    }

    private func pieceShape(_ index: Int) -> JigsawPieceShape {
        JigsawPieceShape(row: index / columns, col: index % columns,
                         rows: rows, cols: columns)
    }
}
