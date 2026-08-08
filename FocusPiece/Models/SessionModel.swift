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

    private var timer: AnyCancellable?
    /// Wall-clock moment the current phase ends; set while running.
    private var endDate: Date?
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

        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sync() }
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
    }

    private func beginFocusRound(_ next: Int, autoStart: Bool) {
        phase = .focus
        round = min(next, totalRounds)
        remainingSeconds = focusSecondsPerRound
        didSettleThisRound = false
        state = .ready
        if autoStart { start() }
    }

    private func stopTimer() {
        timer?.cancel(); timer = nil
        endDate = nil
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
