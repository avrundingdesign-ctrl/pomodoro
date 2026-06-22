import SwiftUI
import Combine

enum SessionState { case ready, running, paused, complete }

/// Drives a single focus session: the countdown and the tile reveal.
@MainActor
final class SessionModel: ObservableObject {

    /// Fixed, scattered reveal order of the 20 tile indices (0 = top-left,
    /// row-major to 19 = bottom-right). Taken verbatim from the prototype so
    /// the reveal feels organic rather than row-by-row.
    static let revealOrder = [7, 14, 2, 11, 18, 5, 9, 0, 16, 3, 12, 19, 6, 1, 15, 8, 17, 4, 13, 10]
    static let tileCount = 20

    @Published private(set) var state: SessionState = .ready
    @Published private(set) var remainingSeconds: Int
    @Published var artwork: Artwork

    let totalSeconds: Int
    let durationMinutes: Int

    private var timer: AnyCancellable?
    /// Gentle-start grace: the timer settles for a beat before counting down.
    private var gentleSettleTicks: Int

    init(durationMinutes: Int, artwork: Artwork, gentleStart: Bool) {
        self.durationMinutes = durationMinutes
        self.totalSeconds = durationMinutes * 60
        self.remainingSeconds = durationMinutes * 60
        self.artwork = artwork
        self.gentleSettleTicks = gentleStart ? 2 : 0
    }

    // MARK: Derived reveal state
    /// Progress 0…1 of elapsed focus.
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }
    /// How many tiles should currently be sharp: floor(progress * 20), full at completion.
    var revealedCount: Int {
        if state == .complete { return Self.tileCount }
        return min(Self.tileCount, Int(floor(progress * Double(Self.tileCount))))
    }
    /// "9 VON 20 TEILEN"
    var revealedLabel: String { "\(revealedCount) VON \(Self.tileCount) TEILEN" }

    var timeString: String {
        let m = remainingSeconds / 60, s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: Controls
    func start() {
        guard state == .ready || state == .paused else { return }
        state = .running
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        timer?.cancel(); timer = nil   // timer + reveal both halt ("hält die Enthüllung inne")
    }

    func toggle() { state == .running ? pause() : start() }

    private func tick() {
        // Gentle start: let the first beats settle before the clock moves.
        if gentleSettleTicks > 0 { gentleSettleTicks -= 1; return }
        guard remainingSeconds > 0 else { complete(); return }
        remainingSeconds -= 1
        if remainingSeconds == 0 { complete() }
    }

    private func complete() {
        timer?.cancel(); timer = nil
        remainingSeconds = 0
        state = .complete
    }
}
