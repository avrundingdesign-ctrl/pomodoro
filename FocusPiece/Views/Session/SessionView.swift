import SwiftUI

/// Hosts one Pomodoro cycle inside the Fokus tab: focus rounds with short
/// breaks between them → completion (→ optional long break).
struct SessionFlowView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: SessionModel
    @State private var confirmAbort = false

    init(app: AppModel) {
        let s = app.settings
        // All works unlocked → free session over a random collected work.
        let artwork = app.nextLockedArtwork()
            ?? app.collection.randomElement()
            ?? Artwork.seedCollection[0]
        _session = StateObject(wrappedValue: SessionModel(
            focusMinutes: s.selectedDuration,
            shortBreakMinutes: s.shortBreakMinutes,
            longBreakMinutes: s.longBreakMinutes,
            rounds: s.roundsPerCycle,
            artwork: artwork,
            gentleStart: s.gentleStart,
            notifyOnCompletion: s.notifications))
    }

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()
            switch session.state {
            case .complete:
                CompletionView(session: session, onDone: leave)
            default:
                ActiveSessionView(session: session, haptics: app.settings.haptics, onClose: requestClose)
            }
        }
        // The countdown is wall-clock based and keeps running while the app is
        // locked or in background — returning just catches the display up.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.sync() }
        }
        // Every finished focus round counts toward history & streak, even if
        // the cycle is later abandoned before the artwork is revealed.
        .onChange(of: session.completedRounds) { _, rounds in
            guard rounds > 0 else { return }
            app.recordFocusRound(minutes: session.focusMinutes, artworkID: session.artwork.id)
            if session.state != .complete {
                Feedback.roundCompleted(haptics: app.settings.haptics)
            }
        }
        .onChange(of: session.state) { _, state in
            switch state {
            case .complete:
                // Secure the artwork right away — leaving from the completion
                // screen (or a killed app) can't lose it anymore.
                app.unlock(session.artwork, minutes: session.cycleFocusMinutes)
                Feedback.sessionCompleted(tone: app.settings.completionTone,
                                          haptics: app.settings.haptics)
            case .finished:   // the long break ran out
                Feedback.tap(app.settings.haptics)
                leave()
            default:
                break
            }
        }
        .confirmationDialog("Session beenden?", isPresented: $confirmAbort, titleVisibility: .visible) {
            Button("Session beenden", role: .destructive) {
                session.cancel()
                leave()
            }
            Button("Weiter fokussieren", role: .cancel) {}
        } message: {
            Text("Dein Werk bleibt verborgen — die Enthüllung geht verloren.")
        }
    }

    /// Close only asks when reveal progress is at stake: an untouched session
    /// and the long break (work already secured) leave directly.
    private func requestClose() {
        let untouched = session.state == .ready && session.phase == .focus && session.completedRounds == 0
        if untouched || session.phase == .longBreak {
            session.cancel()
            leave()
        } else {
            confirmAbort = true
        }
    }

    /// Close the session and return to the gallery. Re-entering the Fokus tab
    /// builds a fresh ready session with a new hidden work.
    private func leave() { app.selectedTab = .gallery }
}

// MARK: - Ready / Running / Paused / Break
private struct ActiveSessionView: View {
    @ObservedObject var session: SessionModel
    @Environment(\.horizontalSizeClass) private var hSize
    let haptics: Bool
    let onClose: () -> Void

    /// The four screens this view hosts.
    private enum Screen { case initialReady, roundReady, breakReady, active }
    private var screen: Screen {
        guard session.state == .ready else { return .active }
        if session.phase == .shortBreak { return .breakReady }
        return session.completedRounds == 0 ? .initialReady : .roundReady
    }
    /// The picked work was already unlocked — every work is collected.
    private var isFreeSession: Bool { session.isFreeSession }

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

            if screen == .active {
                timerBlock.padding(.bottom, 22)
                statusLine.padding(.bottom, 24)
            } else if screen == .breakReady {
                breakHeadline.padding(.bottom, 26)
            }

            artCard

            switch screen {
            case .initialReady:
                Spacer().frame(height: 30)
                readyTimerBlock(caption: initialCaption)
            case .roundReady:
                Spacer().frame(height: 30)
                readyTimerBlock(caption: "Die Pause ist vorbei — weiter geht's.")
            default:
                progressBar.padding(.top, 26)
                if session.totalRounds > 1 {
                    RoundDots(session: session).padding(.top, 14)
                }
            }

            Spacer(minLength: 0)

            controls
        }
        .padding(.horizontal, Theme.Pad.screenH)
        .padding(.bottom, 12)
        .contentColumn()
    }

    // Header: round back · title · round close
    private var header: some View {
        HStack {
            CircleIconButton(systemName: "chevron.left") { onClose() }
            Spacer()
            Text(headerTitle)
                .font(Theme.Font.sans(15))
                .foregroundStyle(Theme.Palette.muted)
            Spacer()
            CircleIconButton(systemName: "xmark") { onClose() }
        }
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var headerTitle: String {
        switch screen {
        case .initialReady:
            return "Neue Session"
        case .breakReady:
            return "Pause"
        case .roundReady:
            return session.roundLabel
        case .active:
            switch session.phase {
            case .focus:      return session.totalRounds > 1 ? session.roundLabel : "Fokus"
            case .shortBreak: return "Pause"
            case .longBreak:  return "Lange Pause"
            }
        }
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
        if session.state == .paused {
            prefix = "PAUSIERT"
        } else {
            switch session.phase {
            case .focus:      prefix = session.progress >= 0.7 ? "FAST GESCHAFFT" : "FOKUS LÄUFT"
            case .shortBreak: prefix = "KURZE PAUSE"
            case .longBreak:  prefix = "LANGE PAUSE"
            }
        }
        return "\(prefix) · \(session.revealedLabel)"
    }

    // Intermission headline after a finished round, before the break starts.
    private var breakHeadline: some View {
        VStack(spacing: 8) {
            Text("Runde \(session.completedRounds) geschafft")
                .font(Theme.Font.serif(34, weight: .light))
                .foregroundStyle(Theme.Palette.ink)
            Text("Gönn dir \(session.shortBreakMinutes) Minuten Pause — dein Werk wächst.")
                .font(Theme.Font.sans(14))
                .foregroundStyle(Theme.Palette.muted2)
                .multilineTextAlignment(.center)
        }
    }

    // The art card with the reveal grid (300 × 356, radius 26).
    private var artCard: some View {
        ZStack {
            RevealGridView(assetName: session.artwork.assetName,
                           revealedCount: session.revealedCount)
            if screen == .initialReady {
                VStack(spacing: 12) {
                    Image(systemName: isFreeSession ? "checkmark.seal.fill" : "lock.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(isFreeSession ? "Freie Session" : "Verborgenes Werk")
                        .font(Theme.Font.sans(14, weight: .semibold))
                        .foregroundStyle(.white)
                    if isFreeSession {
                        Text("Alle Werke enthüllt")
                            .font(Theme.Font.sans(12))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.artCard, style: .continuous))
        .shadow(color: Color(hex: 0x28221C).opacity(0.45), radius: 22, x: 0, y: 22)
        .frame(maxWidth: .infinity)
    }

    private var initialCaption: String {
        session.totalRounds > 1
            ? "Minuten Fokus · \(session.totalRounds) Runden"
            : "Minuten ungestörter Fokus"
    }

    // Ready states show the timer under the card.
    private func readyTimerBlock(caption: String) -> some View {
        VStack(spacing: 8) {
            Text(session.timeString)
                .font(Theme.Font.serif(isRegular ? 78 : 66, weight: .light))
                .tracking(0.7)
                .foregroundStyle(Theme.Palette.ink)
                .monospacedDigit()
            Text(caption)
                .font(Theme.Font.sans(14))
                .foregroundStyle(Theme.Palette.muted2)
            if session.totalRounds > 1 {
                RoundDots(session: session).padding(.top, 10)
            }
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
        switch screen {
        case .initialReady:
            PrimaryButton(title: "Fokus beginnen", height: 60) {
                Feedback.tap(haptics)
                session.start()
            }
        case .roundReady:
            PrimaryButton(title: "Runde \(session.round) beginnen", height: 60) {
                Feedback.tap(haptics)
                session.start()
            }
        case .breakReady:
            VStack(spacing: 14) {
                PrimaryButton(title: "Pause starten · \(session.shortBreakMinutes) Min", height: 60) {
                    Feedback.tap(haptics)
                    session.start()
                }
                Button {
                    Feedback.tap(haptics)
                    session.skipBreak()
                } label: {
                    Text("Überspringen & weiter fokussieren")
                        .font(Theme.Font.sans(14, weight: .medium))
                        .foregroundStyle(Theme.Palette.muted2)
                }
                .buttonStyle(.plain)
            }
        case .active:
            VStack(spacing: 12) {
                CircleIconButton(
                    systemName: session.state == .paused ? "play.fill" : "pause.fill",
                    diameter: 66,
                    background: Theme.Palette.circleButton,
                    iconColor: Theme.Palette.bodySoft,
                    iconSize: 22) {
                        Feedback.tap(haptics)
                        session.toggle()
                    }
                Text(session.state == .paused ? "Fortsetzen" : "Pausieren")
                    .font(Theme.Font.sans(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.muted2)
                if session.phase == .shortBreak {
                    Button {
                        Feedback.tap(haptics)
                        session.skipBreak()
                    } label: {
                        Text("Pause überspringen")
                            .font(Theme.Font.sans(13, weight: .medium))
                            .foregroundStyle(Theme.Palette.muted2)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }
}

// MARK: - Round dots
/// One dot per focus round: filled = done, half = in progress, faint = ahead.
private struct RoundDots: View {
    @ObservedObject var session: SessionModel

    var body: some View {
        HStack(spacing: 7) {
            ForEach(1...session.totalRounds, id: \.self) { r in
                Circle()
                    .fill(fill(for: r))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func fill(for r: Int) -> Color {
        if r <= session.completedRounds { return Theme.Palette.accent }
        let isCurrent = r == session.round && session.phase == .focus && session.state != .ready
        return isCurrent ? Theme.Palette.accent.opacity(0.4) : Theme.Palette.progressTrack
    }
}
