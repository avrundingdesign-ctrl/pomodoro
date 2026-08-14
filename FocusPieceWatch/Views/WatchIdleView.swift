import SwiftUI

/// Nothing running: what the next cycle would be, and one way to begin it.
struct WatchIdleView: View {
    @ObservedObject var model: WatchModel

    private var snapshot: SessionSnapshot { model.snapshot }

    var body: some View {
        VStack(spacing: 6) {
            Text("FOKUS")
                .font(Theme.Font.sans(11, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(Theme.Palette.accent)

            Text(verbatim: String(format: "%02d:00", snapshot.focusMinutes))
                .font(Theme.Font.serif(38, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.ink)

            Text("\(snapshot.worksUnlocked) von \(snapshot.worksTotal) Werken")
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Palette.muted2)

            Spacer(minLength: 4)

            Button {
                model.start()
            } label: {
                Text("Fokus beginnen")
                    .font(Theme.Font.sans(14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.accent)

            // Without a reachable phone a tap is queued rather than lost, but
            // saying so beats a button that looks like it did nothing.
            if !model.isReachable {
                Text("iPhone nicht in Reichweite")
                    .font(Theme.Font.sans(10))
                    .foregroundStyle(Theme.Palette.muted3)
            }
        }
        .multilineTextAlignment(.center)
        .containerBackground(Theme.Palette.paper, for: .navigation)
    }
}
