import Foundation
import WatchConnectivity

/// The phone's half of the iPhone↔Watch link.
///
/// Division of labour: **the phone broadcasts state, the watch sends commands.**
/// State goes out as an application context, which coalesces to "only the
/// latest" and is delivered on the watch's next activation even if it was
/// unreachable when we wrote it. Commands come back as messages when the watch
/// can reach us and as queued user-info transfers when it cannot.
///
/// Nothing here ticks. Both devices hold `endDate` and derive the countdown
/// locally, so the link only carries changes of shape — start, pause, a new
/// round — and a session keeps running on the wrist while this app is asleep.
///
/// Every call is best-effort, in the same spirit as `LiveActivityController`: a
/// watch that cannot be reached must never disturb a focus session.
@MainActor
final class WatchSyncController: NSObject {

    static let shared = WatchSyncController()

    private weak var app: AppModel?
    /// The last thing we put on the wire, for suppressing identical writes.
    private var lastSent: SessionSnapshot?
    private let defaults = UserDefaults.standard

    /// Highest revision seen from either device, persisted so the Lamport
    /// counter never restarts below what the watch already holds.
    private var seenRevision: Int {
        get { defaults.integer(forKey: SessionSync.revisionKey) }
        set { defaults.set(newValue, forKey: SessionSync.revisionKey) }
    }

    private override init() { super.init() }

    /// Activate the link. Safe to call when no watch exists — `isSupported()`
    /// is false on iPad, and everything downstream checks `isWatchAppInstalled`.
    func configure(app: AppModel) {
        self.app = app
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: Outbound state

    /// Push the current state to the watch, unless it would say nothing new.
    func publish(from app: AppModel) {
        guard let session = readySession() else { return }

        var snapshot = app.sessionSnapshot()
        guard changedSinceLastSend(snapshot) else { return }

        snapshot.stamp(origin: .phone, seen: seenRevision)
        seenRevision = snapshot.revision

        do {
            try session.updateApplicationContext(SessionSync.payload(snapshot))
            lastSent = snapshot
        } catch {
            // Context writes fail while the pairing settles; the next change
            // carries the same information, so there is nothing to retry.
        }
    }

    /// A session that exists, is activated, and has a watch app to talk to.
    private func readySession() -> WCSession? {
        guard WCSession.isSupported() else { return nil }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled
        else { return nil }
        return session
    }

    /// Whether `candidate` differs in substance from the last write.
    ///
    /// The Lamport stamp changes on every write by definition, so it has to be
    /// neutralised before comparing — otherwise every settings `didSet` would
    /// spend a context update on identical state.
    private func changedSinceLastSend(_ candidate: SessionSnapshot) -> Bool {
        guard let lastSent else { return true }
        return neutralised(candidate) != neutralised(lastSent)
    }

    private func neutralised(_ snapshot: SessionSnapshot) -> SessionSnapshot {
        var copy = snapshot
        copy.revision = 0
        copy.updatedAt = .distantPast
        copy.origin = .phone
        return copy
    }

    // MARK: Inbound commands

    /// Apply a command from the wrist and describe the result.
    ///
    /// Returns the resulting snapshot so a reachable watch converges on the
    /// reply instead of waiting for the context that follows.
    private func handle(_ payload: [String: Any]) -> [String: Any] {
        guard let app else { return [:] }

        if let envelope = SessionSync.envelope(from: payload) {
            seenRevision = max(seenRevision, envelope.seenRevision)

            // A queued command can arrive long after it was tapped. Obeying a
            // lunchtime "start" in the evening would be worse than dropping it,
            // so a stale one only earns a fresh snapshot in reply.
            if !envelope.isStale, envelope.command != .requestState {
                app.apply(envelope.command)
            }
        }

        var snapshot = app.sessionSnapshot()
        snapshot.stamp(origin: .phone, seen: seenRevision)
        seenRevision = snapshot.revision
        lastSent = snapshot
        return SessionSync.payload(snapshot)
    }
}

// MARK: - WCSessionDelegate
// The delegate is called off the main actor, so every entry point hops back
// before touching `AppModel`.
extension WatchSyncController: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in
            guard let app = self.app else { return }
            // First contact: tell the watch where we are.
            self.publish(from: app)
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            replyHandler(self.handle(message))
        }
    }

    /// A command the watch queued while we were unreachable.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            _ = self.handle(userInfo)
            if let app = self.app { self.publish(from: app) }
        }
    }

    /// Switching to a different watch clears what the old one knew, so the
    /// suppression cache has to go with it.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.lastSent = nil
            WCSession.default.activate()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.lastSent = nil          // a newly installed watch app knows nothing
            if let app = self.app { self.publish(from: app) }
        }
    }
}
