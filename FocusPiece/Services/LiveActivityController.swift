import Foundation
import ActivityKit

/// Drives the Live Activity that shows a running cycle on the lock screen and
/// in the Dynamic Island.
///
/// The countdown itself needs no updates — the views render
/// `Text(timerInterval:)` against `endDate`, so the system ticks on its own.
/// Updates are only pushed when the state actually changes shape: pause,
/// resume, a new phase, a new round.
///
/// Every call is best-effort. A Live Activity that cannot start (the user
/// switched them off, the system is out of budget) must never disturb a focus
/// session, so failures are swallowed deliberately.
@MainActor
enum LiveActivityController {

    private static var current: Activity<FocusActivityAttributes>?

    /// Begin a Live Activity for this session, replacing any stale one.
    static func start(_ session: SessionModel) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard current == nil else {
            update(session)
            return
        }
        do {
            current = try Activity.request(
                attributes: FocusActivityAttributes(),
                content: ActivityContent(state: state(from: session), staleDate: nil))
        } catch {
            current = nil
        }
    }

    static func update(_ session: SessionModel) {
        guard let activity = current else { return }
        // Snapshot now, not inside the task — the session keeps moving.
        let next = state(from: session)
        Task {
            await activity.update(ActivityContent(state: next, staleDate: nil))
        }
    }

    /// Finish the activity. A completed cycle lingers briefly so the result is
    /// readable; an abandoned one disappears at once.
    static func end(_ session: SessionModel, completed: Bool) {
        guard let activity = current else { return }
        current = nil
        let final = state(from: session)
        Task {
            await activity.end(ActivityContent(state: final, staleDate: nil),
                               dismissalPolicy: completed ? .default : .immediate)
        }
    }

    /// Clear anything left over from a previous launch (a crash mid-session
    /// leaves the activity on screen until the system times it out).
    static func endStaleActivities() {
        for activity in Activity<FocusActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        current = nil
    }

    // MARK: Mapping

    private static func state(from s: SessionModel) -> FocusActivityAttributes.ContentState {
        FocusActivityAttributes.ContentState(
            phase: phase(from: s.phase),
            // `endDate` exists only while the clock runs. Otherwise the views
            // show the frozen remainder, so any value works as a placeholder.
            endDate: s.endDate ?? Date().addingTimeInterval(TimeInterval(s.remainingSeconds)),
            isPaused: s.state == .paused,
            isTicking: s.endDate != nil,
            remainingSeconds: s.remainingSeconds,
            round: s.round,
            totalRounds: s.totalRounds,
            revealedTiles: s.revealedCount,
            totalTiles: SessionModel.tileCount)
    }

    private static func phase(from p: SessionPhase) -> FocusActivityAttributes.Phase {
        switch p {
        case .focus:      return .focus
        case .shortBreak: return .shortBreak
        case .longBreak:  return .longBreak
        }
    }
}
