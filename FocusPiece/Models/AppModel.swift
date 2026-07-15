import SwiftUI
import Combine

/// Persisted app settings (Session, Klang & Haptik).
/// Decoding is field-tolerant: adding a setting later never resets the others.
struct Settings: Codable, Equatable {
    var selectedDuration: Int = 25     // minutes — "Standarddauer"
    var gentleStart: Bool = true       // "Sanfter Start"
    var completionTone: Bool = true    // "Abschluss-Ton"
    var haptics: Bool = true           // "Haptisches Feedback"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        selectedDuration = (try? c.decode(Int.self, forKey: .selectedDuration)) ?? d.selectedDuration
        gentleStart      = (try? c.decode(Bool.self, forKey: .gentleStart)) ?? d.gentleStart
        completionTone   = (try? c.decode(Bool.self, forKey: .completionTone)) ?? d.completionTone
        haptics          = (try? c.decode(Bool.self, forKey: .haptics)) ?? d.haptics
    }
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
        didSet { persist(settings, key: Keys.settings) }
    }
    @Published var collection: [Artwork] {
        didSet { persist(collection, key: Keys.collection) }
    }
    @Published var selectedTab: Tab = .focus

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let onboarding = "fp.onboardingComplete"
        static let settings   = "fp.settings"
        static let collection = "fp.collection"
    }

    init() {
        let d = UserDefaults.standard
        onboardingComplete = d.bool(forKey: Keys.onboarding)
        settings = Self.load(Settings.self, key: Keys.settings, from: d) ?? Settings()

        // Merge: stored progress wins, but newly shipped works are appended so
        // the collection can grow with app updates.
        var stored = Self.load([Artwork].self, key: Keys.collection, from: d) ?? []
        let knownIDs = Set(stored.map(\.id))
        stored.append(contentsOf: Artwork.seedCollection.filter { !knownIDs.contains($0.id) })
        collection = stored
    }

    // MARK: Derived
    var unlockedCount: Int { collection.filter(\.unlocked).count }
    var totalCount: Int { collection.count }
    var allUnlocked: Bool { unlockedCount == totalCount }
    /// Total focused minutes across the whole collection.
    var totalFocusMinutes: Int { collection.compactMap(\.sessionMinutes).reduce(0, +) }

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

    /// A random still-locked artwork to hide behind the next session.
    func nextLockedArtwork() -> Artwork? {
        collection.filter { !$0.unlocked }.randomElement()
    }

    /// Mark an artwork unlocked and stamp it with this session's metadata.
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
