import SwiftUI
import Combine

enum SessionState { case ready, running, paused, complete, finished }

/// Where in the Pomodoro cycle the session currently is.
enum SessionPhase { case focus, shortBreak, longBreak }

/// Drives one Pomodoro cycle: several focus rounds with short breaks between
/// them, and the tile reveal spreading across all rounds. The artwork is fully
/// revealed when the last round ends (`.complete`); an optional long break can
/// follow from the completion screen (`.finished` once it runs out).
///
/// Each phase countdown is wall-clock based (`endDate`), not tick based:
/// locking the iPhone or leaving the app does NOT lose progress — on return
/// the remaining time is re-derived from the end date. Phase transitions are
/// manual (a tap starts the break / the next round); a local notification
/// announces a phase end that happens while the app is away.
@MainActor
final class SessionModel: ObservableObject {

    /// Fixed, scattered reveal order of the 20 tile indices (0 = top-left,
    /// row-major to 19 = bottom-right). Taken verbatim from the prototype so
    /// the reveal feels organic rather than row-by-row.
    static let revealOrder = [7, 14, 2, 11, 18, 5, 9, 0, 16, 3, 12, 19, 6, 1, 15, 8, 17, 4, 13, 10]
    static let tileCount = 20

    @Published private(set) var state: SessionState = .ready
    @Published private(set) var phase: SessionPhase = .focus
    /// Current focus round, 1-based. During the break after round r it stays r.
    @Published private(set) var round = 1
    @Published private(set) var completedRounds = 0
    @Published private(set) var remainingSeconds: Int
    @Published var artwork: Artwork

    let focusMinutes: Int
    let shortBreakMinutes: Int
    let longBreakMinutes: Int
    let totalRounds: Int
    /// The picked work was already unlocked when the cycle began (free focus).
    let isFreeSession: Bool

    /// Whether a phase-end notification should be scheduled while running.
    private let notifyOnCompletion: Bool

    /// Fires once a mutation has *fully* settled — the hook everything outside
    /// the session listens on (widget snapshot, Live Activity, watch sync).
    ///
    /// It exists because `@Published` publishes in `willSet`: a Combine
    /// subscriber on `$state` runs before the rest of the method's assignments
    /// land, and `start()` sets `state = .running` before it computes
    /// `endDate` — so such a subscriber would read `nil` and push a countdown
    /// with no end. SwiftUI's `onChange` happens to dodge this by delivering
    /// after the update pass; nothing on Combine does. Announcing explicitly
    /// at the end of each mutation makes the ordering a guarantee instead of a
    /// coincidence.
    ///
    /// Deliberately *not* fired from `sync()`: the half-second display beat
    /// changes nothing structural, and both devices derive the countdown from
    /// `endDate` themselves. Only shape changes travel.
    let changes = PassthroughSubject<Void, Never>()

    private var timer: AnyCancellable?
    /// Wall-clock moment the current phase ends; set while running. Read by the
    /// widget snapshot and the Live Activity so both count down against the
    /// same instant instead of re-deriving one that drifts.
    private(set) var endDate: Date?
    /// Gentle-start grace: extra settle seconds before the clock visibly moves.
    private let gentleSettleSeconds: Int
    private var didSettleThisRound = false

    init(focusMinutes: Int, shortBreakMinutes: Int, longBreakMinutes: Int,
         rounds: Int, artwork: Artwork, gentleStart: Bool, notifyOnCompletion: Bool = false) {
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.totalRounds = max(1, rounds)
        self.remainingSeconds = focusMinutes * 60
        self.artwork = artwork
        self.isFreeSession = artwork.unlocked
        self.gentleSettleSeconds = gentleStart ? 2 : 0
        self.notifyOnCompletion = notifyOnCompletion
    }

    // MARK: Derived durations
    private var focusSecondsPerRound: Int { focusMinutes * 60 }
    private var cycleFocusSeconds: Int { totalRounds * focusSecondsPerRound }
    /// Focused minutes across the whole cycle — what the completion screen credits.
    var cycleFocusMinutes: Int { totalRounds * focusMinutes }

    // MARK: Derived reveal state
    /// Progress 0…1 of *focused* time across the cycle; breaks freeze it.
    var progress: Double {
        guard cycleFocusSeconds > 0 else { return 0 }
        let inRound = (phase == .focus) ? focusSecondsPerRound - remainingSeconds : 0
        let elapsed = completedRounds * focusSecondsPerRound + inRound
        return min(1, Double(elapsed) / Double(cycleFocusSeconds))
    }
    /// How many tiles should currently be sharp: floor(progress * 20), full at completion.
    var revealedCount: Int {
        if state == .complete || state == .finished { return Self.tileCount }
        return min(Self.tileCount, Int(floor(progress * Double(Self.tileCount))))
    }
    /// "9 VON 20 TEILEN"
    var revealedLabel: String { String(localized: "\(revealedCount) VON \(Self.tileCount) TEILEN") }
    /// "Runde 2 von 4"
    var roundLabel: String { String(localized: "Runde \(round) von \(totalRounds)") }

    /// Whether abandoning this cycle would throw anything away. A ready cycle
    /// nobody has started yet is worth nothing, which is why closing it — or
    /// replacing it with a task picked from the gallery — does not need to ask.
    var hasProgress: Bool {
        !(state == .ready && phase == .focus && completedRounds == 0)
    }

    var timeString: String {
        let m = remainingSeconds / 60, s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: Controls
    func start() {
        guard state == .ready || state == .paused else { return }
        state = .running

        // The first start of each focus round gets the gentle settle beat;
        // resumes and breaks don't.
        let settle = (phase == .focus && !didSettleThisRound) ? gentleSettleSeconds : 0
        if phase == .focus { didSettleThisRound = true }
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds + settle))

        scheduleEndNotification(after: remainingSeconds + settle)

        startDisplayTimer()
        announce()
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        // Freeze the remaining time; the reveal halts with it.
        if let end = endDate {
            remainingSeconds = min(remainingSeconds, max(0, Int(end.timeIntervalSinceNow.rounded(.up))))
        }
        endDate = nil
        timer?.cancel(); timer = nil
        NotificationManager.shared.cancelSessionEnd()
        announce()
    }

    func toggle() { state == .running ? pause() : start() }

    /// Skip the short break (waiting or already running) and dive straight
    /// into the next focus round.
    func skipBreak() {
        guard phase == .shortBreak else { return }
        stopTimer()
        NotificationManager.shared.cancelSessionEnd()
        beginFocusRound(round + 1, autoStart: true)
    }

    /// The optional long break offered on the completion screen.
    func startLongBreak() {
        guard state == .complete else { return }
        phase = .longBreak
        remainingSeconds = longBreakMinutes * 60
        state = .ready
        start()
    }

    /// Abandon the cycle (user closed it). Cleans up timer + notification.
    func cancel() {
        stopTimer()
        NotificationManager.shared.cancelSessionEnd()
        announce()
    }

    /// Re-derive the remaining time from the end date — called on every timer
    /// beat and when the app returns to the foreground.
    func sync() {
        guard state == .running, let end = endDate else { return }
        let left = Int(end.timeIntervalSinceNow.rounded(.up))
        if left <= 0 {
            completePhase()
        } else {
            // `min` keeps the display steady during the gentle-start settle.
            remainingSeconds = min(remainingSeconds, left)
        }
    }

    // MARK: Phase machine
    private func completePhase() {
        stopTimer()
        // Redundant when the notification already fired in background;
        // suppresses it when the phase completes while the app is frontmost.
        NotificationManager.shared.cancelSessionEnd()

        switch phase {
        case .focus:
            completedRounds += 1
            if completedRounds >= totalRounds {
                remainingSeconds = 0
                state = .complete
            } else {
                phase = .shortBreak
                remainingSeconds = shortBreakMinutes * 60
                state = .ready
            }
        case .shortBreak:
            beginFocusRound(round + 1, autoStart: false)
        case .longBreak:
            remainingSeconds = 0
            state = .finished
        }
        announce()
    }

    private func beginFocusRound(_ next: Int, autoStart: Bool) {
        phase = .focus
        round = min(next, totalRounds)
        remainingSeconds = focusSecondsPerRound
        didSettleThisRound = false
        state = .ready
        // `start()` announces for us; otherwise say so here.
        if autoStart { start() } else { announce() }
    }

    private func startDisplayTimer() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sync() }
    }

    private func stopTimer() {
        timer?.cancel(); timer = nil
        endDate = nil
    }

    private func announce() { changes.send() }

    // MARK: Mirroring another device
    /// This cycle expressed as a wire snapshot. The caller fills in the fields
    /// the session cannot know about — the collection summary and the artwork's
    /// display text.
    var syncState: SessionSnapshot.State {
        switch state {
        case .ready:    return .ready
        case .running:  return .running
        case .paused:   return .paused
        case .complete: return .complete
        case .finished: return .finished
        }
    }

    var syncPhase: SessionSnapshot.Phase {
        switch phase {
        case .focus:      return .focus
        case .shortBreak: return .shortBreak
        case .longBreak:  return .longBreak
        }
    }

    /// Take over a cycle another device owns — the watch mirroring the phone,
    /// or the phone catching up on a cycle that was started from the wrist.
    ///
    /// Only *where* the cycle is gets adopted; its shape (durations, rounds) is
    /// fixed at init, so the caller rebuilds the model when that changes rather
    /// than mutating it here.
    ///
    /// Deliberately silent: it neither announces (an inbound change must not
    /// echo straight back to the sender) nor schedules a notification — exactly
    /// one device owns the phase-end alert, and it is not the mirroring one.
    func adopt(_ snapshot: SessionSnapshot) {
        phase = snapshot.phase.asSessionPhase
        round = snapshot.round
        completedRounds = snapshot.completedRounds
        remainingSeconds = snapshot.remainingSeconds
        endDate = snapshot.endDate
        state = snapshot.state.asSessionState ?? .ready
        // A mirrored round is already under way, so the gentle settle beat
        // must not replay when this device later resumes it.
        didSettleThisRound = true

        timer?.cancel(); timer = nil
        if state == .running, let end = endDate {
            remainingSeconds = max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
            startDisplayTimer()
        }
    }

    // MARK: Notifications
    /// Phase-appropriate copy for the notification that fires if the phase
    /// ends while the app is locked or in background.
    private func scheduleEndNotification(after seconds: Int) {
        guard notifyOnCompletion else { return }
        let title: String, body: String
        switch phase {
        case .focus where completedRounds + 1 >= totalRounds:
            title = String(localized: "Session vollendet")
            body = String(localized: "Dein Werk ist vollständig enthüllt — komm zurück und betrachte es.")
        case .focus:
            title = String(localized: "Runde \(round) geschafft")
            body = String(localized: "Gönn dir \(shortBreakMinutes) Minuten Pause — dein Werk nimmt Gestalt an.")
        case .shortBreak:
            title = String(localized: "Pause vorbei")
            body = String(localized: "Bereit für Runde \(round + 1) von \(totalRounds)? Dein Werk wartet.")
        case .longBreak:
            title = String(localized: "Pause beendet")
            body = String(localized: "Gut erholt — dein Werk hängt bereits in der Galerie.")
        }
        NotificationManager.shared.scheduleSessionEnd(after: seconds, title: title, body: body)
    }
}

// MARK: - Wire enum bridging
// The snapshot's enums are `String`-backed so the payload never depends on
// declaration order, which the session's own plain enums would.
extension SessionSnapshot.Phase {
    var asSessionPhase: SessionPhase {
        switch self {
        case .focus:      return .focus
        case .shortBreak: return .shortBreak
        case .longBreak:  return .longBreak
        }
    }
}

extension SessionSnapshot.State {
    /// `nil` for `.idle` — there is no session state that means "no session",
    /// which is exactly why the snapshot carries the extra case.
    var asSessionState: SessionState? {
        switch self {
        case .idle:     return nil
        case .ready:    return .ready
        case .running:  return .running
        case .paused:   return .paused
        case .complete: return .complete
        case .finished: return .finished
        }
    }
}
