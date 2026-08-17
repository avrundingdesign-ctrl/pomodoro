import SwiftUI

/// A cycle under way: the ring, the clock, and one control.
///
/// Covers running, paused, and a waiting break — they differ only in the
/// eyebrow and what the button offers, so splitting them into separate screens
/// would just duplicate the ring.
struct WatchRunningView: View {
    @ObservedObject var model: WatchModel
    @ObservedObject var session: SessionModel

    private var snapshot: SessionSnapshot { model.snapshot }
    private var isBreak: Bool { session.phase != .focus }

    var body: some View {
        VStack(spacing: 5) {
            FocusRing(progress: session.progress) {
                VStack(spacing: 1) {
                    clock
                    if session.totalRounds > 1 {
                        Text(verbatim: "\(session.round)/\(session.totalRounds)")
                            .font(Theme.Font.sans(10, weight: .medium))
                            .foregroundStyle(Theme.Palette.muted2)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Text(eyebrow)
                .font(Theme.Font.sans(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text("\(session.revealedCount)/\(SessionModel.tileCount) Teile")
                .font(Theme.Font.sans(11))
                .foregroundStyle(Theme.Palette.muted2)

            controls
        }
        .containerBackground(for: .navigation) {
            WatchArtworkBackdrop(assetName: snapshot.artworkAsset,
                                 progress: session.progress)
        }
    }

    /// Live while the clock runs, frozen otherwise. `Text(timerInterval:)` lets
    /// the system tick it, so this view is not redrawn every second.
    @ViewBuilder private var clock: some View {
        Group {
            if session.state == .running, let end = session.endDate, end > .now {
                Text(timerInterval: Date.now...end, countsDown: true)
            } else {
                Text(verbatim: session.timeString)
            }
        }
        .font(Theme.Font.serif(26, weight: .light))
        .monospacedDigit()
        .foregroundStyle(Theme.Palette.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var eyebrow: LocalizedStringKey {
        if session.state == .paused { return "PAUSIERT" }
        switch session.phase {
        case .focus:      return session.state == .ready ? "BEREIT" : "FOKUS LÄUFT"
        case .shortBreak: return "KURZE PAUSE"
        case .longBreak:  return "LANGE PAUSE"
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 6) {
            Button {
                model.toggle()
            } label: {
                Image(systemName: session.state == .running ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.accent)

            // A waiting or running break can be cut short — the same affordance
            // the phone offers, and the one most worth having on a wrist.
            if isBreak && session.phase == .shortBreak {
                Button {
                    model.skipBreak()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .font(Theme.Font.sans(13, weight: .semibold))
    }
}
