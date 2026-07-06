import SwiftUI
import Combine

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
    var theme: String = "System"       // "Thema" — Hell / Dunkel / System
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
        theme             = (try? c.decode(String.self, forKey: .theme)) ?? d.theme
        notifications     = (try? c.decode(Bool.self, forKey: .notifications)) ?? d.notifications
    }

    /// Explicit color scheme, or nil to follow the system.
    var colorScheme: ColorScheme? {
        switch theme {
        case "Hell":   return .light
        case "Dunkel": return .dark
        default:       return nil
        }
    }
}

/// One completed focus round — the basis for statistics and streaks.
struct FocusSessionRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var date: Date
    var minutes: Int
    var artworkID: String
}

/// Top-level tabs.
enum Tab: Hashable { case focus, gallery, community, store, profile }

/// Global, persistent application state.
@MainActor
final class AppModel: ObservableObject {

    @Published var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: Keys.onboarding) }
    }
    @Published var settings: Settings {
        didSet { persist(settings, key: Keys.settings) }
    }
    @Published var collection: [Artwork] {
        didSet { persist(collection, key: Keys.collection) }
    }
    @Published var history: [FocusSessionRecord] {
        didSet { persist(history, key: Keys.history) }
    }
    @Published var selectedTab: Tab = .focus

    /// Online-Modus: Account, Freunde, Presence, Wallet, Store.
    /// Eigenes ObservableObject — Views beobachten es direkt (Environment).
    let online: OnlineModel

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let onboarding = "fp.onboardingComplete"
        static let settings   = "fp.settings"
        static let collection = "fp.collection"
        static let history    = "fp.history"
    }

    init() {
        let d = UserDefaults.standard
        onboardingComplete = d.bool(forKey: Keys.onboarding)
        settings = Self.load(Settings.self, key: Keys.settings, from: d) ?? Settings()
        online = OnlineModel()

        // Merge: stored progress wins, but newly shipped works are appended so
        // the collection can grow with app updates.
        var stored = Self.load([Artwork].self, key: Keys.collection, from: d) ?? []
        let knownIDs = Set(stored.map(\.id))
        stored.append(contentsOf: Artwork.seedCollection.filter { !knownIDs.contains($0.id) })
        collection = stored

        var storedHistory = Self.load([FocusSessionRecord].self, key: Keys.history, from: d) ?? []
        // One-time migration: synthesize records from works unlocked before
        // history existed, so stats don't start at zero.
        if storedHistory.isEmpty {
            storedHistory = stored.compactMap { art in
                guard art.unlocked, let date = art.unlockedDate, let m = art.sessionMinutes else { return nil }
                return FocusSessionRecord(date: date, minutes: m, artworkID: art.id)
            }
        }
        history = storedHistory
        online.app = self
    }

    // MARK: Derived
    var unlockedCount: Int { collection.filter(\.unlocked).count }
    var totalCount: Int { collection.count }
    var allUnlocked: Bool { unlockedCount == totalCount }

    /// Total focused minutes across all completed sessions.
    var totalFocusMinutes: Int { history.map(\.minutes).reduce(0, +) }

    /// "45 Min Fokus" under an hour, then "1,5 Std Fokus".
    var focusTimeLabel: String {
        let minutes = totalFocusMinutes
        if minutes < 60 { return "\(minutes) Min Fokus" }
        let hours = Double(minutes) / 60.0
        let text = hours.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(hours))
            : String(format: "%.1f", hours).replacingOccurrences(of: ".", with: ",")
        return "\(text) Std Fokus"
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
        online.roundCompleted(minutes: minutes)
    }

    /// Werke aus einem gekauften Bilder-Paket aufnehmen — gesperrt, enthüllt
    /// wird wie immer nur durch Fokus-Sessions.
    func addArtworks(_ artworks: [Artwork]) {
        let known = Set(collection.map(\.id))
        collection.append(contentsOf: artworks.filter { !known.contains($0.id) })
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

    // MARK: Persistence helpers
    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    private static func load<T: Decodable>(_ type: T.Type, key: String, from d: UserDefaults) -> T? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
