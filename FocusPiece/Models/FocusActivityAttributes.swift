import Foundation
import ActivityKit

/// The running Pomodoro cycle as the lock screen and Dynamic Island see it.
///
/// Compiled into the app *and* the widget extension (see the membership
/// exceptions in project.pbxproj) — the app writes the state, the extension
/// renders it.
///
/// `ContentState` stays purely numeric: every visible word is rendered by the
/// extension from its own string catalog, so a translation lives in exactly one
/// place and the payload stays far below ActivityKit's ~4 KB budget.
struct FocusActivityAttributes: ActivityAttributes {

    /// Which part of the cycle is running — mirrors `SessionPhase`, but as its
    /// own `Codable` type so the activity payload never depends on app internals.
    enum Phase: String, Codable, Hashable {
        case focus, shortBreak, longBreak
    }

    struct ContentState: Codable, Hashable {
        var phase: Phase = .focus
        /// Wall-clock end of the current phase. The system counts down to this
        /// on its own, so a running session needs no updates at all.
        var endDate: Date
        var isPaused: Bool = false
        /// Whether the clock is actually running. False both while paused *and*
        /// while a phase waits to be started by hand — breaks and later rounds
        /// need a tap, and until then `endDate` is a placeholder that must not
        /// be counted down.
        var isTicking: Bool = false
        /// Frozen remainder, shown whenever the clock is not ticking.
        var remainingSeconds: Int = 0
        var round: Int = 1
        var totalRounds: Int = 1
        var revealedTiles: Int = 0
        var totalTiles: Int = 20
    }

    /// Nothing varies per session that the state doesn't already carry; the
    /// artwork deliberately stays out (the extension does not bundle the JPGs).
    var sessionName: String = "FocusPiece"
}
