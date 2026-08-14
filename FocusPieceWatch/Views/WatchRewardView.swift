import SwiftUI

/// The cycle is complete: the painting, finally, full-bleed.
///
/// The only screen on the watch that shows the artwork at all. During the cycle
/// the ring stands in for it; here it has been earned, so it gets the whole
/// display with the title laid over a scrim at the bottom.
struct WatchRewardView: View {
    @ObservedObject var model: WatchModel
    @ObservedObject var session: SessionModel

    var body: some View {
        ZStack(alignment: .bottom) {
            // Thumbnails come from Scripts/make_watch_thumbs.sh. When one is
            // missing, ArtworkImage falls back to its gradient placeholder, so
            // this never renders empty.
            ArtworkImage(assetName: session.artwork.assetName, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            VStack(spacing: 1) {
                Text(session.artwork.title)
                    .font(Theme.Font.serif(14, weight: .medium))
                    .lineLimit(2)
                if !session.artwork.artist.isEmpty {
                    Text(session.artwork.artist)
                        .font(Theme.Font.sans(10))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .containerBackground(Theme.Palette.paper, for: .navigation)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 6) {
                    Button("Lange Pause") { model.startLongBreak() }
                        .font(Theme.Font.sans(12, weight: .medium))
                    Button("Fertig") { model.cancel() }
                        .font(Theme.Font.sans(12, weight: .semibold))
                }
            }
        }
    }
}
