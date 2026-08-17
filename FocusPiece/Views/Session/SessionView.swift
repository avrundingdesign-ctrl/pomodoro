import SwiftUI

/// Hosts one Pomodoro cycle inside the Fokus tab: focus rounds with short
/// breaks between them → completion (→ optional long break).
struct SessionFlowView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    /// Owned by `AppModel`, not by this view: a watch command arrives whether
    /// or not the Fokus tab is on screen, and leaving the tab used to tear the
    /// session down while its Live Activity kept running.
    @ObservedObject var session: SessionModel
    @State private var confirmAbort = false

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()
            switch session.state {
            case .complete:
                CompletionView(session: session, onDone: leave)
            default:
                ActiveSessionView(session: session,
                                  haptics: app.settings.haptics,
                                  showsTaskNote: shapedByWork,
                                  onClose: requestClose)
            }
        }
        // The countdown is wall-clock based and keeps running while the app is
        // locked or in background — returning just catches the display up.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.sync() }
        }
        // Crediting rounds, securing the artwork, feedback, the widget snapshot,
        // the Live Activity and the watch all hang off `SessionModel.changes` in
        // AppModel now — they have to happen with or without this view. What is
        // left here is the one genuinely navigational consequence.
        .onChange(of: session.state) { _, state in
            if state == .finished { leave() }   // the long break ran out
        }
        .confirmationDialog("Session beenden?", isPresented: $confirmAbort, titleVisibility: .visible) {
            Button("Session beenden", role: .destructive) { abandon() }
            Button("Weiter fokussieren", role: .cancel) {}
        } message: {
            Text("Dein Werk bleibt verborgen — die Enthüllung geht verloren.")
        }
        // Widget deep link: begin (or resume) as soon as the Fokus tab is up.
        .onAppear(perform: consumeAutoStart)
        .onChange(of: app.pendingAutoStart) { _, pending in
            if pending { consumeAutoStart() }
        }
    }

    /// Whether this cycle's shape came from the work rather than from the
    /// settings — a task picked in the gallery, or the fallback `AppModel`
    /// takes when nothing left is reachable with the current preferences.
    private var shapedByWork: Bool {
        session.focusMinutes != app.settings.selectedDuration
            || session.totalRounds != app.settings.roundsPerCycle
    }

    private func consumeAutoStart() {
        guard app.pendingAutoStart else { return }
        app.pendingAutoStart = false
        if session.state == .ready || session.state == .paused { session.start() }
    }

    /// Close only asks when reveal progress is at stake: an untouched session
    /// and the long break (work already secured) leave directly.
    private func requestClose() {
        if !session.hasProgress || session.phase == .longBreak {
            abandon()
        } else {
            confirmAbort = true
        }
    }

    private func abandon() { leave() }

    /// Close the cycle and return to the gallery. `endSession` stops the timer,
    /// takes the Live Activity down and tells the watch; re-entering the Fokus
    /// tab then builds a fresh ready session with a new hidden work.
    private func leave() {
        app.endSession()
        app.selectedTab = .gallery
    }
}

// MARK: - Ready / Running / Paused / Break
private struct ActiveSessionView: View {
    @ObservedObject var session: SessionModel
    @Environment(\.horizontalSizeClass) private var hSize
    let haptics: Bool
    /// The cycle's shape comes from the work, not the settings — say so.
    var showsTaskNote = false
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
                readyTimerBlock(caption: String(localized: "Die Pause ist vorbei — weiter geht's."))
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
            return String(localized: "Neue Session")
        case .breakReady:
            return String(localized: "Pause")
        case .roundReady:
            return session.roundLabel
        case .active:
            switch session.phase {
            case .focus:      return session.totalRounds > 1 ? session.roundLabel
                                                             : String(localized: "Fokus")
            case .shortBreak: return String(localized: "Pause")
            case .longBreak:  return String(localized: "Lange Pause")
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
            prefix = String(localized: "PAUSIERT")
        } else {
            switch session.phase {
            case .focus:      prefix = session.progress >= 0.7 ? String(localized: "FAST GESCHAFFT")
                                                               : String(localized: "FOKUS LÄUFT")
            case .shortBreak: prefix = String(localized: "KURZE PAUSE")
            case .longBreak:  prefix = String(localized: "LANGE PAUSE")
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

    private var taskLabel: String {
        ArtworkRequirement(rounds: session.totalRounds,
                           minutesPerRound: session.focusMinutes).shortLabel
    }

    private var initialCaption: String {
        session.totalRounds > 1
            ? String(localized: "Minuten Fokus · \(session.totalRounds) Runden")
            : String(localized: "Minuten ungestörter Fokus")
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
            // The cycle can be shaped by the work rather than by the settings —
            // either because a task was picked in the gallery, or because
            // nothing left was reachable with the current preferences. Saying
            // so is the difference between "the app ignored me" and "this is
            // what this work costs".
            if showsTaskNote {
                Text("Aufgabe dieses Werks · \(taskLabel)")
                    .font(Theme.Font.sans(12, weight: .medium))
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(.top, 2)
                    .accessibilityIdentifier("session.tasknote")
            }
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
