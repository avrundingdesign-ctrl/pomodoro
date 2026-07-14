import SwiftUI

/// Hosts a focus session inside the Fokus tab: ready → running/paused → complete.
struct SessionFlowView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: SessionModel

    init(app: AppModel) {
        let minutes = app.settings.selectedDuration
        let artwork = app.nextLockedArtwork() ?? Artwork.seedCollection[0]
        _session = StateObject(wrappedValue: SessionModel(
            durationMinutes: minutes,
            artwork: artwork,
            gentleStart: app.settings.gentleStart))
    }

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()
            switch session.state {
            case .complete:
                CompletionView(session: session, onSave: saveAndCollect)
            default:
                ActiveSessionView(session: session, onClose: leave)
            }
        }
        // Leaving the app pauses the timer and the reveal.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, session.state == .running { session.pause() }
        }
    }

    private func saveAndCollect() {
        app.unlock(session.artwork, minutes: session.durationMinutes)
        leave()
    }

    /// Close the session and return to the gallery. Re-entering the Fokus tab
    /// builds a fresh ready session with a new hidden work.
    private func leave() { app.selectedTab = .gallery }
}

// MARK: - Ready / Running / Paused
private struct ActiveSessionView: View {
    @ObservedObject var session: SessionModel
    @Environment(\.horizontalSizeClass) private var hSize
    let onClose: () -> Void

    private var isReady: Bool { session.state == .ready }
    private var isRegular: Bool { hSize == .regular }

    /// Art card keeps the 300:356 proportion; on iPad it grows so it doesn't
    /// float lost in the middle of the large canvas.
    private var cardSize: CGSize {
        isRegular ? CGSize(width: 430, height: 510) : CGSize(width: 300, height: 356)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            if !isReady {
                timerBlock.padding(.bottom, 22)
                statusLine.padding(.bottom, 24)
            }

            artCard

            if isReady {
                Spacer().frame(height: 30)
                readyTimerBlock
            } else {
                progressBar.padding(.top, 26)
            }

            Spacer(minLength: 0)

            controls
        }
        .padding(.horizontal, Theme.Pad.screenH)
        .padding(.bottom, 12)
        .contentColumn()
    }

    // Header: round back · "Neue Session" · round close
    private var header: some View {
        HStack {
            CircleIconButton(systemName: "chevron.left") { onClose() }
            Spacer()
            Text("Neue Session")
                .font(Theme.Font.sans(15))
                .foregroundStyle(Theme.Palette.muted)
            Spacer()
            CircleIconButton(systemName: "xmark") { onClose() }
        }
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    // Big serif timer used while running.
    private var timerBlock: some View {
        Text(session.timeString)
            .font(Theme.Font.serif(isRegular ? 84 : 70, weight: .light))
            .tracking(0.7)
            .foregroundStyle(Theme.Palette.ink)
            .monospacedDigit()
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.Palette.accent).frame(width: 7, height: 7)
            Text(statusText)
                .font(Theme.Font.sans(13, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Theme.Palette.muted2)
        }
    }

    private var statusText: String {
        let prefix: String
        switch session.state {
        case .paused:  prefix = "PAUSIERT"
        default:       prefix = session.progress >= 0.7 ? "FAST GESCHAFFT" : "FOKUS LÄUFT"
        }
        return "\(prefix) · \(session.revealedLabel)"
    }

    // The art card with the reveal grid (300 × 356, radius 26).
    private var artCard: some View {
        ZStack {
            RevealGridView(assetName: session.artwork.assetName,
                           revealedCount: session.revealedCount)
            if isReady {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Verborgenes Werk")
                        .font(Theme.Font.sans(14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.artCard, style: .continuous))
        .shadow(color: Color(hex: 0x28221C).opacity(0.45), radius: 22, x: 0, y: 22)
        .frame(maxWidth: .infinity)
    }

    // Ready state shows the timer under the card.
    private var readyTimerBlock: some View {
        VStack(spacing: 8) {
            Text(session.timeString)
                .font(Theme.Font.serif(isRegular ? 78 : 66, weight: .light))
                .tracking(0.7)
                .foregroundStyle(Theme.Palette.ink)
                .monospacedDigit()
            Text("Minuten ungestörter Fokus")
                .font(Theme.Font.sans(14))
                .foregroundStyle(Theme.Palette.muted2)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.progressTrack)
                Capsule().fill(Theme.Palette.accent)
                    .frame(width: max(0, geo.size.width * CGFloat(session.progress)))
                    .animation(.easeInOut(duration: 0.55), value: session.revealedCount)
            }
        }
        .frame(height: 5)
        .frame(maxWidth: cardSize.width)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var controls: some View {
        if isReady {
            PrimaryButton(title: "Fokus beginnen", height: 60) { session.start() }
        } else {
            VStack(spacing: 12) {
                CircleIconButton(
                    systemName: session.state == .paused ? "play.fill" : "pause.fill",
                    diameter: 66,
                    background: Theme.Palette.circleButton,
                    iconColor: Theme.Palette.bodySoft,
                    iconSize: 22) { session.toggle() }
                Text(session.state == .paused ? "Fortsetzen" : "Pausieren")
                    .font(Theme.Font.sans(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.muted2)
            }
        }
    }
}
