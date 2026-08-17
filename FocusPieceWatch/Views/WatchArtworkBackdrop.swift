import SwiftUI

/// The work behind the current cycle, blurred, as the watch's backdrop.
///
/// The wrist has no room for the puzzle grid the phone draws, so the reveal is
/// expressed as focus instead of as tiles: the painting starts almost unreadable
/// and sharpens as the cycle progresses. It never becomes fully sharp here —
/// that is `WatchRewardView`'s moment, and spending it early would leave the
/// completion screen with nothing to give.
///
/// Layout note: `ArtworkImage` in fill mode reports the thumbnail's pixel size
/// as its ideal size, which would make a bare `ZStack` around it 320 pt wide on
/// a 208 pt screen. The base colour therefore carries the layout and the
/// painting lives in an overlay, where it cannot be measured.
struct WatchArtworkBackdrop: View {
    let assetName: String
    /// 0…1 across the whole cycle — `SessionModel.progress`.
    var progress: Double = 0

    /// 22 pt down to 9 pt. The floor matters: at 0 the ring and the clock sit
    /// on top of hard brushstrokes and stop being readable.
    private var blurRadius: CGFloat {
        22 - 13 * min(max(progress, 0), 1)
    }

    var body: some View {
        Theme.Palette.paper
            .overlay {
                if !assetName.isEmpty {
                    ArtworkImage(assetName: assetName, contentMode: .fill)
                        // Blurring an image that exactly fills its frame leaves
                        // washed-out edges; oversizing first pushes them out of
                        // sight.
                        .scaleEffect(1.3)
                        .blur(radius: blurRadius, opaque: true)
                }
            }
            .clipped()
            .overlay {
                // Cream text (`ink` resolves to 0xEDE7DB on the watch, which is
                // always dark) has to stay legible over a bright painting too,
                // so the scrim is unconditional rather than luminance-driven.
                Theme.Palette.paper.opacity(0.46)
                LinearGradient(colors: [.black.opacity(0.28), .clear, .black.opacity(0.38)],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
    }
}
