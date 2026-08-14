import Foundation
import Combine
import SwiftUI

/// What the watch app knows: the phone's last word, plus a local `SessionModel`
/// running the same cycle.
///
/// The local model is the point. Rather than re-deriving the countdown and the
/// reveal maths here — a second implementation that would drift from the
/// phone's — the watch adopts the snapshot into the very same `SessionModel`
/// the iPhone uses, and reads `progress`, `revealedCount` and `roundLabel`
/// straight off it. That is also why the model keeps its own half-second timer:
/// the wrist stays live while the phone is asleep, because both sides count
/// down against one shared `endDate`.
@MainActor
final class WatchModel: ObservableObject {

    @Published private(set) var snapshot = SessionSnapshot()
    @Published private(set) var session: SessionModel?
    @Published private(set) var isReachable = false

    private let connection = WatchConnection()
    private var sessionObserver: AnyCancellable?
    /// Focus rounds we have already buzzed for in the current cycle.
    private var buzzedRounds = 0

    init() {
        connection.onSnapshot = { [weak self] snapshot in
            self?.adopt(snapshot)
        }
        connection.onReachabilityChange = { [weak self] reachable in
            self?.isReachable = reachable
        }
    }

    func activate() {
        connection.activate()
        isReachable = connection.isReachable
    }

    // MARK: Commands
    // Deliberately thin: every one of these is the phone's decision to make, so
    // the wrist states an intent and waits to be told what happened. Nothing
    // here mutates local state optimistically.

    func start()          { connection.send(.start) }
    func toggle()         { connection.send(.toggle) }
    func pause()          { connection.send(.pause) }
    func skipBreak()      { connection.send(.skipBreak) }
    func startLongBreak() { connection.send(.startLongBreak) }
    func cancel()         { connection.send(.cancel) }

    // MARK: Adopting the phone's state

    private func adopt(_ incoming: SessionSnapshot) {
        snapshot = incoming

        guard incoming.hasSession else {
            sessionObserver = nil
            session = nil
            buzzedRounds = 0
            return
        }

        if needsRebuild(for: incoming) {
            let model = SessionModel(
                focusMinutes: incoming.focusMinutes,
                shortBreakMinutes: incoming.shortBreakMinutes,
                longBreakMinutes: incoming.longBreakMinutes,
                rounds: incoming.totalRounds,
                artwork: Self.artwork(from: incoming),
                gentleStart: incoming.gentleStart,
                // The phone owns the phase-end notification. Exactly one device
                // may schedule it, or the wrist gets buzzed twice — once by our
                // own alert and once by the forwarded one.
                notifyOnCompletion: false)
            buzzedRounds = incoming.completedRounds
            observe(model)
            session = model
        }

        session?.adopt(incoming)
    }

    /// Whether the incoming snapshot describes a different cycle than the one we
    /// hold. The shape is fixed at init, so a change of shape means rebuild.
    private func needsRebuild(for incoming: SessionSnapshot) -> Bool {
        guard let session else { return true }
        return session.focusMinutes != incoming.focusMinutes
            || session.shortBreakMinutes != incoming.shortBreakMinutes
            || session.longBreakMinutes != incoming.longBreakMinutes
            || session.totalRounds != incoming.totalRounds
            || session.artwork.id != (incoming.artworkID ?? "")
    }

    /// Buzz when the *local* clock crosses a round boundary.
    ///
    /// This is the one thing the watch does on its own authority, because it is
    /// the whole reason to wear it: the phone's notification arrives on the
    /// wrist too, but only via forwarding, and only when the phone is not in
    /// use. While this app is open, the local clock is what is honest.
    private func observe(_ model: SessionModel) {
        sessionObserver = model.changes
            .sink { [weak self, weak model] in
                guard let self, let model else { return }
                guard model.completedRounds > self.buzzedRounds else { return }
                self.buzzedRounds = model.completedRounds
                guard self.snapshot.haptics else { return }
                if model.state == .complete {
                    Feedback.sessionCompleted(tone: self.snapshot.completionTone,
                                              haptics: true)
                } else {
                    Feedback.roundCompleted(haptics: true)
                }
            }
    }

    /// A stand-in `Artwork` built from the four fields the snapshot carries.
    ///
    /// The catalogue never travels — the watch only ever shows the one painting
    /// behind the current cycle, so the unused text fields stay empty rather
    /// than dragging 37 works' translations into this bundle.
    private static func artwork(from snapshot: SessionSnapshot) -> Artwork {
        Artwork(id: snapshot.artworkID ?? "",
                title: snapshot.artworkTitle,
                artist: snapshot.artworkArtist,
                year: "",
                assetName: snapshot.artworkAsset,
                collectionTag: "",
                blurb: "")
    }
}
