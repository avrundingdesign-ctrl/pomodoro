import SwiftUI

/// The reveal progress as a ring, wrapping whatever sits inside it.
///
/// A ring rather than the 20-tile grid on purpose: at 44 mm a Vermeer is a
/// postage stamp, and the tiles would read as noise. The ring says how far the
/// cycle has come; the painting itself is the reward at the end, and the place
/// to actually look at it is the phone.
struct FocusRing<Content: View>: View {
    /// 0…1 of the cycle's focused time.
    let progress: Double
    var lineWidth: CGFloat = 6
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Palette.progressTrack, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(Theme.Palette.accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                // Start at twelve o'clock instead of three.
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)

            content()
                .padding(lineWidth * 2.5)
        }
    }
}
