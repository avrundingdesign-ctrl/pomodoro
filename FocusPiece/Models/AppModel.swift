import SwiftUI
import Combine

/// "Thema" — the appearance setting. Stored as a stable raw value so the
/// persisted state never depends on the display language.
enum AppTheme: String, Codable, CaseIterable {
    case light, dark, system

    /// Translated name for the settings picker.
    var label: String {
        switch self {
        case .light:  return String(localized: "Hell")
        case .dark:   return String(localized: "Dunkel")
        case .system: return String(localized: "System")
        }
    }

    /// Explicit color scheme, or nil to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    /// Before the app was localized the theme was persisted as its German
    /// display string; those values still have to resolve.
    init(stored: String) {
        switch stored {
        case "light", "Hell":   self = .light
        case "dark", "Dunkel":  self = .dark
        default:                self = .system
        }
    }
}

/// Persisted app settings (Klang & Haptik, Darstellung, Session).
/// Decoding is field-tolerant: adding a setting later never resets the others.
struct Settings: Codable, Equatable {
    var selectedDuration: Int = 25     // minutes — "Fokusdauer" (per round)
    var shortBreakMinutes: Int = 5     // "Kurze Pause" between rounds
    var longBreakMinutes: Int = 15     // "Lange Pause" after the full cycle
    var roundsPerCycle: Int = 4        // "Runden" — focus rounds per session
    var gentleStart: Bool = true       // "Sanfter Start"
    var completionTone: Bool = true    // "Abschluss-Ton"
    var haptics: Bool = true           // "Haptisches Feedback"
    var theme: AppTheme = .system      // "Thema" — Hell / Dunkel / System
    var notifications: Bool = true     // "Benachrichtigungen" (Phasenende-Notification)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        selectedDuration  = (try? c.decode(Int.self, forKey: .selectedDuration)) ?? d.selectedDuration
        shortBreakMinutes = (try? c.decode(Int.self, forKey: .shortBreakMinutes)) ?? d.shortBreakMinutes
        longBreakMinutes  = (try? c.decode(Int.self, forKey: .longBreakMinutes)) ?? d.longBreakMinutes
        roundsPerCycle    = (try? c.decode(Int.self, forKey: .roundsPerCycle)) ?? d.roundsPerCycle
        gentleStart       = (try? c.decode(Bool.self, forKey: .gentleStart)) ?? d.gentleStart
        completionTone    = (try? c.decode(Bool.self, forKey: .completionTone)) ?? d.completionTone
        haptics           = (try? c.decode(Bool.self, forKey: .haptics)) ?? d.haptics
        theme             = AppTheme(stored: (try? c.decode(String.self, forKey: .theme)) ?? "")
        notifications     = (try? c.decode(Bool.self, forKey: .notifications)) ?? d.notifications
    }

    /// Explicit color scheme, or nil to follow the system.
    var colorScheme: ColorScheme? { theme.colorScheme }
}

/// One completed focus round — the basis for statistics and streaks.
struct FocusSessionRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var date: Date
    var minutes: Int
    var artworkID: String
}

/// Top-level tabs.
enum Tab: Hashable { case focus, gallery, settings }

/// Global, persistent application state.
@MainActor
final class AppModel: ObservableObject {

    @Published var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: Keys.onboarding) }
    }
    @Published var settings: Settings {
        didSet {
            persist(settings, key: Keys.settings)
            publishWidgetSnapshot()
            // The wrist shows the configured duration on its idle screen and
            // honours the same haptics preference, so it needs these too.
            WatchSyncController.shared.publish(from: self)
        }
    }
    /// The works the user owns, rebuilt from the catalogue on every launch so
    /// the texts always match the current language. Only `progress` is stored.
    @Published var collection: [Artwork] {
        didSet { persist(collection.map(\.progress), key: Keys.collection); publishWidgetSnapshot() }
    }
    @Published var history: [FocusSessionRecord] {
        didSet { persist(history, key: Keys.history) }
    }
    @Published var selectedTab: Tab = .focus
    /// Set by the widget deep link; the Fokus tab consumes it and starts the session.
    @Published var pendingAutoStart = false

    /// The cycle currently under way, or nil when none is.
    ///
    /// Owned here rather than by `SessionFlowView` for two reasons: a command
    /// from the Apple Watch can arrive with no view on screen, and leaving the
    /// Fokus tab mid-session used to tear the session down while its Live
    /// Activity kept running.
    @Published private(set) var session: SessionModel?

    private var sessionObservers = Set<AnyCancellable>()
    /// Focus rounds already written to `history` for the current cycle.
    private var recordedRounds = 0
    /// The completion finale plays once, even though `unlock` is idempotent.
    private var celebratedCompletion = false
    /// Packs whose works belong to the collection. Always contains the free
    /// pack; paid packs join via StoreKit entitlements (cached for offline).
    @Published private(set) var ownedPackIDs: Set<String> {
        didSet { defaults.set(Array(ownedPackIDs).sorted(), forKey: Keys.ownedPacks) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let onboarding = "fp.onboardingComplete"
        static let settings   = "fp.settings"
        static let collection = "fp.collection"
        static let history    = "fp.history"
        static let ownedPacks = "fp.ownedPacks"
    }

    init() {
        let d = UserDefaults.standard
        onboardingComplete = d.bool(forKey: Keys.onboarding)
        settings = Self.load(Settings.self, key: Keys.settings, from: d) ?? Settings()

        // Free pack always; paid packs from the cached StoreKit entitlements.
        let owned = Set(d.stringArray(forKey: Keys.ownedPacks) ?? [])
            .union([ArtworkCatalog.freePackID])
        ownedPackIDs = owned

        // Rebuild the collection from the catalogue and lay the stored progress
        // over it. Works shipped by a newer app version join automatically.
        let progress = Self.load([ArtworkProgress].self, key: Keys.collection, from: d) ?? []
        collection = Self.buildCollection(progress: progress, ownedPackIDs: owned)

        var storedHistory = Self.load([FocusSessionRecord].self, key: Keys.history, from: d) ?? []
        // One-time migration: synthesize records from works unlocked before
        // history existed, so stats don't start at zero.
        if storedHistory.isEmpty {
            storedHistory = progress.compactMap { p in
                guard p.unlocked, let date = p.unlockedDate, let m = p.sessionMinutes else { return nil }
                return FocusSessionRecord(date: date, minutes: m, artworkID: p.id)
            }
        }
        history = storedHistory

        // Sessions don't survive a relaunch, so the widget starts out "bereit".
        publishWidgetSnapshot()
    }

    // MARK: Derived
    var unlockedCount: Int { collection.filter(\.unlocked).count }
    var totalCount: Int { collection.count }
    var allUnlocked: Bool { unlockedCount == totalCount }

    /// Total focused minutes across all completed sessions.
    var totalFocusMinutes: Int { history.map(\.minutes).reduce(0, +) }

    /// "45 Min Fokus" under an hour, then "1,5 Std Fokus" — the decimal
    /// separator follows the locale ("1.5 hrs focused" in English).
    var focusTimeLabel: String {
        let minutes = totalFocusMinutes
        if minutes < 60 { return String(localized: "\(minutes) Min Fokus") }
        let hours = Double(minutes) / 60.0
        let digits = hours.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1
        let text = hours.formatted(.number.precision(.fractionLength(digits)))
        return String(localized: "\(text) Std Fokus")
    }

    /// Consecutive days (ending today or yesterday) with at least one session.
    var streakDays: Int {
        let cal = Calendar.current
        let days = Set(history.map { cal.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return 0 }

        var cursor = cal.startOfDay(for: Date())
        // A streak still "lives" if the last session was yesterday.
        if !days.contains(cursor) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// A random still-locked artwork to hide behind the next session.
    func nextLockedArtwork() -> Artwork? {
        collection.filter { !$0.unlocked }.randomElement()
    }

    /// Record one completed focus round. Rounds count toward stats and the
    /// streak even when the cycle is abandoned before the artwork is revealed.
    func recordFocusRound(minutes: Int, artworkID: String) {
        history.append(FocusSessionRecord(date: Date(), minutes: minutes, artworkID: artworkID))
    }

    /// Mark an artwork unlocked and stamp it with the cycle's focus minutes.
    /// Already-unlocked works keep their original unlock stamp (free focus).
    func unlock(_ artwork: Artwork, minutes: Int) {
        guard let idx = collection.firstIndex(where: { $0.id == artwork.id }),
              !collection[idx].unlocked else { return }
        collection[idx].unlocked = true
        collection[idx].unlockedDate = Date()
        collection[idx].sessionMinutes = minutes
    }

    func finishOnboarding() { onboardingComplete = true }

    // MARK: Packs & purchases
    /// Paid packs that are not part of the collection yet — the shop teasers.
    var purchasablePacks: [ArtworkPack] {
        ArtworkCatalog.paidPacks.filter { !ownedPackIDs.contains($0.id) }
    }

    /// Sync from StoreKit entitlements: `productIDs` is the set of verified,
    /// unrevoked non-consumable purchases. Unknown ids are ignored.
    func applyPurchasedProducts(_ productIDs: Set<String>) {
        let owned = ArtworkCatalog.packIDs(forProducts: productIDs)
            .union([ArtworkCatalog.freePackID])
        guard owned != ownedPackIDs else { return }
        ownedPackIDs = owned
        let rebuilt = Self.buildCollection(progress: collection.map(\.progress), ownedPackIDs: owned)
        if rebuilt != collection { collection = rebuilt }
    }

    /// The collection in catalogue order: every work of an owned pack, plus any
    /// work that was already revealed — those stay forever, even after a refund.
    /// Stored progress is laid over the (localized) catalogue entries.
    private static func buildCollection(progress: [ArtworkProgress],
                                        ownedPackIDs: Set<String>) -> [Artwork] {
        let byID = Dictionary(progress.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return ArtworkCatalog.packs
            .flatMap(\.works)
            .filter { ownedPackIDs.contains($0.packID) || byID[$0.id]?.unlocked == true }
            .map { $0.applying(byID[$0.id]) }
    }

    // MARK: The running cycle
    /// Begin a cycle behind the next still-locked work.
    ///
    /// Idempotent — an existing cycle is handed back untouched, so entering the
    /// Fokus tab twice, or a command arriving from the watch while the tab is
    /// already open, can never discard progress.
    @discardableResult
    func beginSession() -> SessionModel {
        if let session { return session }

        let s = settings
        // All works unlocked → free session over a random collected work.
        let artwork = nextLockedArtwork()
            ?? collection.randomElement()
            ?? Artwork.seedCollection[0]
        let model = SessionModel(
            focusMinutes: s.selectedDuration,
            shortBreakMinutes: s.shortBreakMinutes,
            longBreakMinutes: s.longBreakMinutes,
            rounds: s.roundsPerCycle,
            artwork: artwork,
            gentleStart: s.gentleStart,
            notifyOnCompletion: s.notifications)

        recordedRounds = 0
        celebratedCompletion = false
        observe(model)
        session = model
        WatchSyncController.shared.publish(from: self)
        return model
    }

    /// Give up the cycle — the user closed it, or it ran all the way out.
    func endSession() {
        guard let session else { return }
        session.cancel()
        LiveActivityController.end(session, completed: session.state == .complete
                                                    || session.state == .finished)
        sessionObservers.removeAll()
        self.session = nil
        publishWidgetSnapshot()
        WatchSyncController.shared.publish(from: self)
    }

    /// Subscribe to the session's settled-mutation signal.
    ///
    /// `changes` rather than `$state`, because `@Published` fires in `willSet`
    /// and would hand us a session whose `endDate` is not written yet — see the
    /// note on `SessionModel.changes`.
    private func observe(_ model: SessionModel) {
        sessionObservers.removeAll()
        model.changes
            .sink { [weak self, weak model] in
                guard let self, let model else { return }
                self.handleSessionChange(model)
            }
            .store(in: &sessionObservers)
    }

    /// Everything that reacts to the cycle moving: crediting rounds, securing
    /// the artwork, feedback, the widget snapshot, the Live Activity and the
    /// watch. This used to live in `SessionFlowView`, which meant none of it
    /// happened unless the Fokus tab was on screen — and a command from the
    /// wrist arrives whenever it likes.
    private func handleSessionChange(_ s: SessionModel) {
        // Credit each finished focus round exactly once. Rounds count toward
        // stats and the streak even when the cycle is abandoned later. The
        // signal fires on every mutation, so the increment has to be detected
        // rather than assumed.
        if s.completedRounds > recordedRounds {
            for _ in recordedRounds..<s.completedRounds {
                recordFocusRound(minutes: s.focusMinutes, artworkID: s.artwork.id)
            }
            recordedRounds = s.completedRounds
            if s.state != .complete {
                Feedback.roundCompleted(haptics: settings.haptics)
            }
        }

        switch s.state {
        case .running:
            publishWidgetSnapshot(phase: .running,
                                  remainingSeconds: s.remainingSeconds,
                                  endDate: s.endDate)
            LiveActivityController.start(s)

        case .paused:
            publishWidgetSnapshot(phase: .paused,
                                  remainingSeconds: s.remainingSeconds)
            LiveActivityController.update(s)

        case .complete:
            // Secure the artwork right away — leaving from the completion
            // screen (or a killed app) can't lose it anymore.
            unlock(s.artwork, minutes: s.cycleFocusMinutes)
            // `unlock` is idempotent, the finale is not: only celebrate once.
            if !celebratedCompletion {
                celebratedCompletion = true
                Feedback.sessionCompleted(tone: settings.completionTone,
                                          haptics: settings.haptics)
            }
            publishWidgetSnapshot()
            LiveActivityController.end(s, completed: true)

        case .finished:   // the long break ran out
            Feedback.tap(settings.haptics)
            publishWidgetSnapshot()
            LiveActivityController.end(s, completed: true)

        case .ready:
            // Between phases: the cycle goes on, so the activity stays and
            // just picks up the new round / break.
            LiveActivityController.update(s)
        }

        WatchSyncController.shared.publish(from: self)
    }

    // MARK: Widget
    /// Push the current state into the shared app-group container so the
    /// home/lock screen widget can mirror it.
    func publishWidgetSnapshot(phase: WidgetSnapshot.Phase = .ready,
                               remainingSeconds: Int? = nil,
                               endDate: Date? = nil) {
        WidgetStore.publish(WidgetSnapshot(
            phase: phase,
            selectedMinutes: settings.selectedDuration,
            remainingSeconds: remainingSeconds,
            endDate: endDate,
            worksUnlocked: unlockedCount,
            worksTotal: totalCount,
            totalFocusMinutes: totalFocusMinutes))
    }

    // MARK: Watch
    /// The current state as a wire snapshot for the Apple Watch.
    ///
    /// Assembled here rather than in `SessionModel` because the session knows
    /// nothing about the collection, the settings, or the artwork's display
    /// text — and the watch needs all three.
    func sessionSnapshot() -> SessionSnapshot {
        var snap = SessionSnapshot()

        // Settings describe the *next* cycle; they are what the idle watch
        // shows and what it would start.
        snap.focusMinutes = settings.selectedDuration
        snap.shortBreakMinutes = settings.shortBreakMinutes
        snap.longBreakMinutes = settings.longBreakMinutes
        snap.totalRounds = settings.roundsPerCycle
        snap.gentleStart = settings.gentleStart
        snap.haptics = settings.haptics
        snap.completionTone = settings.completionTone
        snap.notifications = settings.notifications

        snap.worksUnlocked = unlockedCount
        snap.worksTotal = totalCount
        snap.totalFocusMinutes = totalFocusMinutes

        if let s = session {
            // A live cycle's shape was fixed when it began, so it wins over the
            // settings — changing "Fokusdauer" mid-session must not make the
            // wrist show a different clock than the phone.
            snap.focusMinutes = s.focusMinutes
            snap.shortBreakMinutes = s.shortBreakMinutes
            snap.longBreakMinutes = s.longBreakMinutes
            snap.totalRounds = s.totalRounds

            snap.state = s.syncState
            snap.phase = s.syncPhase
            snap.round = s.round
            snap.completedRounds = s.completedRounds
            snap.remainingSeconds = s.remainingSeconds
            snap.endDate = s.endDate

            snap.artworkID = s.artwork.id
            snap.artworkTitle = s.artwork.title
            snap.artworkArtist = s.artwork.artist
            snap.artworkAsset = s.artwork.assetName
        }
        return snap
    }

    /// Apply a command that arrived from the wrist. Creating the session when
    /// none exists is what makes "start from the watch" work with the phone
    /// still in a pocket and the Fokus tab never opened.
    func apply(_ command: SessionCommand) {
        switch command {
        case .requestState:
            break                       // the caller answers with a snapshot
        case .start:
            beginSession().start()
        case .pause:
            session?.pause()
        case .toggle:
            beginSession().toggle()
        case .skipBreak:
            session?.skipBreak()
        case .startLongBreak:
            session?.startLongBreak()
        case .cancel:
            endSession()
        }
    }

    /// Handle `focuspiece://start` from the widget's Start button: switch to the
    /// Fokus tab and begin the session once the tab is up (after onboarding).
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "focuspiece", url.host == "start" else { return }
        selectedTab = .focus
        pendingAutoStart = onboardingComplete
    }

    // MARK: Persistence helpers
    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    private static func load<T: Decodable>(_ type: T.Type, key: String, from d: UserDefaults) -> T? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
