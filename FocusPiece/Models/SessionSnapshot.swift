import Foundation

/// The running cycle as shared between iPhone and Apple Watch.
///
/// This is the WatchConnectivity counterpart to `WidgetSnapshot`: the widget
/// reads its copy from the app-group container, but **app groups do not span
/// devices**, so the watch cannot use that route and gets its copy pushed over
/// `WCSession` instead. Same idea, different pipe.
///
/// The countdown itself is not transmitted. Both sides hold `endDate` and
/// derive the remaining seconds from it locally, exactly as the Live Activity
/// does — so a snapshot that arrives late is still correct, and a session keeps
/// ticking on the wrist while the phone sleeps in a pocket.
///
/// Both devices may act on a session, so every write carries a Lamport clock.
/// See `supersededBy(_:)` for the ordering rules.
struct SessionSnapshot: Codable, Equatable {

    /// `idle` has no counterpart in `SessionState`: it means the phone holds no
    /// cycle at all, which is what the watch sees before anything is started.
    enum State: String, Codable { case idle, ready, running, paused, complete, finished }
    enum Phase: String, Codable { case focus, shortBreak, longBreak }
    enum Origin: String, Codable { case phone, watch }

    // MARK: Ordering
    var revision = 0
    var updatedAt = Date.distantPast
    var origin: Origin = .phone

    // MARK: Cycle shape — fixed for the life of one cycle
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var totalRounds = 4
    var gentleStart = true
    /// Mirrored from the phone's `Settings` so the wrist honours the same
    /// preferences without the watch persisting a second copy of them.
    var haptics = true
    var completionTone = true
    var notifications = true

    // MARK: Live state
    var state: State = .idle
    var phase: Phase = .focus
    var round = 1
    var completedRounds = 0
    var remainingSeconds = 0
    var endDate: Date?

    // MARK: The work behind this cycle
    /// Only the fields the watch actually renders. The full `Artwork` — with
    /// blurb, collection tag and year — never travels, and neither does the
    /// catalogue, which keeps the watch's string catalog small.
    var artworkID: String?
    var artworkTitle = ""
    var artworkArtist = ""
    var artworkAsset = ""

    // MARK: Collection summary for the watch's idle screen
    var worksUnlocked = 0
    var worksTotal = 8
    var totalFocusMinutes = 0

    // MARK: Derived
    /// Whether the phone holds a cycle the watch should mirror at all.
    var hasSession: Bool { state != .idle }
    /// A clock that is genuinely counting down right now.
    var isTicking: Bool { state == .running && endDate != nil }

    /// Seconds left, re-derived from the wall clock while running. This is the
    /// value to display; `remainingSeconds` alone goes stale in transit.
    var liveRemainingSeconds: Int {
        guard state == .running, let endDate else { return remainingSeconds }
        return max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
    }

    // MARK: Lamport ordering
    /// Whether `other` describes a newer truth than this snapshot.
    ///
    /// A higher revision always wins. Equal revisions — two devices that acted
    /// without having seen each other — fall back to the later timestamp, and a
    /// dead tie goes to the phone, which owns the collection and the purchases
    /// and is therefore the tie-breaker that cannot lose data.
    func supersededBy(_ other: SessionSnapshot) -> Bool {
        if other.revision != revision { return other.revision > revision }
        if other.updatedAt != updatedAt { return other.updatedAt > updatedAt }
        return origin == .watch && other.origin == .phone
    }

    /// Stamp this snapshot as the next write from `origin`.
    ///
    /// `seen` is the highest revision observed from either side, so the counter
    /// keeps climbing past whatever the peer last sent and neither device can
    /// have its change silently dropped as "older".
    mutating func stamp(origin: Origin, seen: Int) {
        revision = max(revision, seen) + 1
        updatedAt = Date()
        self.origin = origin
    }
}

/// What one device asks the other to do. Commands are deliberately verbs with
/// no parameters: the resulting state comes back as a `SessionSnapshot`, so
/// there is only ever one description of the truth in flight.
enum SessionCommand: String, Codable {
    case start, pause, toggle, skipBreak, startLongBreak, cancel
    /// Sent by the watch on launch — "tell me where we are".
    case requestState
}

/// A command plus enough context for the receiver to judge whether it still
/// means anything.
///
/// This matters because an unreachable phone makes the watch fall back to
/// `transferUserInfo`, which queues rather than fails. Without a timestamp a
/// "start" tapped at lunchtime would faithfully start a session when the phone
/// is next unlocked in the evening.
struct SessionCommandEnvelope: Codable {
    var command: SessionCommand
    var sentAt = Date()
    /// The snapshot revision the sender was looking at when it acted, so the
    /// receiver can tell that the wrist was working from a stale picture.
    var seenRevision = 0

    /// How long a queued command stays worth obeying.
    static let staleAfter: TimeInterval = 5 * 60

    var isStale: Bool {
        // Guard against a clock skew that would park a command in the future.
        let age = Date().timeIntervalSince(sentAt)
        return age > Self.staleAfter || age < -Self.staleAfter
    }
}

/// Wire format for both directions. `WCSession` carries
/// property-list dictionaries, so each payload is one JSON blob under one key
/// rather than a hand-flattened dictionary that could drift between the sides.
enum SessionSync {
    static let snapshotKey = "fp.session.snapshot"
    static let commandKey  = "fp.session.command"
    /// Highest revision seen from either device, persisted so the Lamport
    /// counter survives a relaunch and never restarts below the peer.
    static let revisionKey = "fp.session.revision"

    static func payload(_ snapshot: SessionSnapshot) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(snapshot) else { return [:] }
        return [snapshotKey: data]
    }

    static func snapshot(from dict: [String: Any]) -> SessionSnapshot? {
        guard let data = dict[snapshotKey] as? Data else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    static func payload(_ envelope: SessionCommandEnvelope) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(envelope) else { return [:] }
        return [commandKey: data]
    }

    static func envelope(from dict: [String: Any]) -> SessionCommandEnvelope? {
        guard let data = dict[commandKey] as? Data else { return nil }
        return try? JSONDecoder().decode(SessionCommandEnvelope.self, from: data)
    }
}
