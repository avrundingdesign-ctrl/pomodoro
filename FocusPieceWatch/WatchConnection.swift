import Foundation
import WatchConnectivity

/// The watch's half of the link — the mirror image of `WatchSyncController`.
///
/// Division of labour, seen from here: **we send commands, the phone sends
/// state.** A command goes out as a message when the phone is reachable, and
/// falls back to a queued user-info transfer when it is not; state arrives as an
/// application context, which the system holds for us until this app next runs.
///
/// Nothing here ticks. The countdown is derived from the `endDate` inside the
/// snapshot, so the wrist keeps counting while the phone sleeps in a pocket and
/// a late-arriving context is still correct.
@MainActor
final class WatchConnection: NSObject {

    /// Called whenever a newer snapshot arrives, on the main actor.
    var onSnapshot: ((SessionSnapshot) -> Void)?
    /// Called when reachability changes, so the UI can say so.
    var onReachabilityChange: ((Bool) -> Void)?

    private let defaults = UserDefaults.standard

    /// Highest revision seen from either device, persisted so our Lamport
    /// stamps never restart below what the phone already holds.
    private var seenRevision: Int {
        get { defaults.integer(forKey: SessionSync.revisionKey) }
        set { defaults.set(newValue, forKey: SessionSync.revisionKey) }
    }

    /// The last snapshot we accepted, for rejecting anything older.
    private var current = SessionSnapshot()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    var isReachable: Bool {
        WCSession.isSupported() && WCSession.default.isReachable
    }

    // MARK: Sending

    /// Ask the phone to do something.
    ///
    /// A reachable phone answers with the resulting snapshot, so the wrist
    /// converges immediately instead of waiting for the context that follows.
    /// An unreachable one gets the command queued — `transferUserInfo` is
    /// guaranteed and ordered, which matters when several taps stack up.
    func send(_ command: SessionCommand) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let envelope = SessionCommandEnvelope(command: command,
                                              seenRevision: seenRevision)
        let payload = SessionSync.payload(envelope)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                Task { @MainActor in self?.accept(reply) }
            }, errorHandler: { _ in
                // Reachability can lapse between the check and the send, so a
                // failed message still deserves the queue.
                Task { @MainActor in
                    WCSession.default.transferUserInfo(payload)
                }
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    // MARK: Receiving

    /// Take a snapshot only if it is genuinely newer — see
    /// `SessionSnapshot.supersededBy`.
    private func accept(_ payload: [String: Any]) {
        guard let incoming = SessionSync.snapshot(from: payload) else { return }
        seenRevision = max(seenRevision, incoming.revision)
        guard current.supersededBy(incoming) else { return }
        current = incoming
        onSnapshot?(incoming)
    }
}

// MARK: - WCSessionDelegate
extension WatchConnection: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in
            // Adopt whatever the system was holding for us, then ask for fresh
            // state in case the phone moved on while this app was not running.
            self.accept(WCSession.default.receivedApplicationContext)
            self.send(.requestState)
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.accept(applicationContext) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            let reachable = session.isReachable
            self.onReachabilityChange?(reachable)
            // Coming back into range is the moment to re-sync: anything we
            // queued has now gone, but the phone may also have moved on.
            if reachable { self.send(.requestState) }
        }
    }
}
