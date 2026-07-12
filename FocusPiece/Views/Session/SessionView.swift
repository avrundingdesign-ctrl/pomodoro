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
        // A session reaching 00:00 counts toward the focus stats once; every
        // state change is mirrored into the widget snapshot.
        .onChange(of: session.state) { _, state in
            switch state {
            case .running:
                app.publishWidgetSnapshot(
                    phase: .running,
                    remainingSeconds: session.remainingSeconds,
                    endDate: Date().addingTimeInterval(TimeInterval(session.remainingSeconds)))
            case .paused:
                app.publishWidgetSnapshot(phase: .paused,
                                          remainingSeconds: session.remainingSeconds)
            case .complete:
                app.recordCompletedSession(minutes: session.durationMinutes)
            case .ready:
                break
            }
        }
        // Widget deep link: begin (or resume) as soon as the Fokus tab is up.
        .onAppear(perform: consumeAutoStart)
        .onChange(of: app.pendingAutoStart) { _, pending in
            if pending { consumeAutoStart() }
        }
    }

    private func consumeAutoStart() {
        guard app.pendingAutoStart else { return }
        app.pendingAutoStart = false
        if session.state == .ready || session.state == .paused { session.start() }
    }

    private func saveAndCollect() {
        app.unlock(session.artwork, minutes: session.durationMinutes)
        leave()
    }

    /// Close the session and return to the gallery. Closing a session that was
    /// under way (but not finished) counts as an aborted session.
    private func leave() {
        if session.state == .running || session.state == .paused {
            app.recordAbortedSession()
        }
        app.selectedTab = .gallery
    }
}

// MARK: - Ready / Running / Paused
private struct ActiveSessionView: View {
    @ObservedObject var session: SessionModel
    let onClose: () -> Void

    private var isReady: Bool { session.state == .ready }

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
    }

    // Header: round back · "Neue Session" · round close
    private var header: some View {
        HStack {
            CircleIconButton(systemName: "chevron.left", identifier: "session.back") { onClose() }
            Spacer()
            Text("Neue Session")
                .font(Theme.Font.sans(15))
                .foregroundStyle(Theme.Palette.muted)
            Spacer()
            CircleIconButton(systemName: "xmark", identifier: "session.close") { onClose() }
        }
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    // Big serif timer used while running.
    private var timerBlock: some View {
        Text(session.timeString)
            .font(Theme.Font.serif(70, weight: .light))
            .tracking(0.7)
            .foregroundStyle(Theme.Palette.ink)
            .monospacedDigit()
            .accessibilityIdentifier("session.timer")
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.Palette.accent).frame(width: 7, height: 7)
            Text(statusText)
                .font(Theme.Font.sans(13, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Theme.Palette.muted2)
                .accessibilityIdentifier("session.status")
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
        .frame(width: 300, height: 356)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.artCard, style: .continuous))
        .shadow(color: Color(hex: 0x28221C).opacity(0.45), radius: 22, x: 0, y: 22)
        .frame(maxWidth: .infinity)
    }

    // Ready state shows the timer under the card.
    private var readyTimerBlock: some View {
        VStack(spacing: 8) {
            Text(session.timeString)
                .font(Theme.Font.serif(66, weight: .light))
                .tracking(0.7)
                .foregroundStyle(Theme.Palette.ink)
                .monospacedDigit()
                .accessibilityIdentifier("session.timer")
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
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var controls: some View {
        if isReady {
            PrimaryButton(title: "Fokus beginnen", height: 60) { session.start() }
                .accessibilityIdentifier("session.begin")
        } else {
            VStack(spacing: 12) {
                CircleIconButton(
                    systemName: session.state == .paused ? "play.fill" : "pause.fill",
                    diameter: 66,
                    background: Theme.Palette.circleButton,
                    iconColor: Theme.Palette.bodySoft,
                    iconSize: 22,
                    identifier: "session.toggle") { session.toggle() }
                Text(session.state == .paused ? "Fortsetzen" : "Pausieren")
                    .font(Theme.Font.sans(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.muted2)
            }
        }
    }
}
