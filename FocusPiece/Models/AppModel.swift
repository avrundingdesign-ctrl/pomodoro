import SwiftUI
import Combine

/// Persisted app settings (Klang & Haptik, Darstellung, Session).
struct Settings: Codable, Equatable {
    var selectedDuration: Int = 25     // minutes — "Standarddauer"
    var gentleStart: Bool = true       // "Sanfter Start"
    var ambientSound: String = "Regen" // "Umgebungsklang"
    var completionTone: Bool = true    // "Abschluss-Ton"
    var haptics: Bool = false          // "Haptisches Feedback"
    var theme: String = "Hell"         // "Thema"
    var notifications: Bool = true     // "Benachrichtigungen"
}

/// Top-level tabs.
enum Tab: Hashable { case focus, gallery, settings }

/// Lightweight, cache-only usage stats. (Single implicit profile for now.)
struct Stats: Codable, Equatable {
    var sessionsCompleted: Int = 0      // every session that reached 00:00
    var totalFocusMinutes: Int = 0      // summed across all completed sessions
    var sessionsAborted: Int = 0        // started then closed before completion

    var totalFocusHours: Int { totalFocusMinutes / 60 }
}

/// Global, persistent application state.
@MainActor
final class AppModel: ObservableObject {

    @Published var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: Keys.onboarding) }
    }
    @Published var settings: Settings {
        didSet { persist(settings, key: Keys.settings); publishWidgetSnapshot() }
    }
    @Published var collection: [Artwork] {
        didSet { persist(collection, key: Keys.collection); publishWidgetSnapshot() }
    }
    @Published var stats: Stats {
        didSet { persist(stats, key: Keys.stats); publishWidgetSnapshot() }
    }
    @Published var selectedTab: Tab = .focus
    /// Set by the widget deep link; the Fokus tab consumes it and starts the session.
    @Published var pendingAutoStart = false
    /// Packs whose works belong to the collection. Always contains the free
    /// pack; paid packs join via StoreKit entitlements (cached for offline).
    @Published private(set) var ownedPackIDs: Set<String> {
        didSet { defaults.set(Array(ownedPackIDs).sorted(), forKey: Keys.ownedPacks) }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let onboarding = "fp.onboardingComplete"
        static let settings   = "fp.settings"
        static let collection = "fp.collection"
        static let stats      = "fp.stats"
        static let ownedPacks = "fp.ownedPacks"
    }

    /// `defaults` is injectable so tests can use an isolated, ephemeral store.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // UI-test launch hooks (no effect in normal runs).
        if LaunchConfig.reset {
            [Keys.onboarding, Keys.settings, Keys.collection, Keys.stats, Keys.ownedPacks].forEach {
                defaults.removeObject(forKey: $0)
            }
        }

        onboardingComplete = LaunchConfig.startOnboarded || defaults.bool(forKey: Keys.onboarding)
        settings = Self.load(Settings.self, key: Keys.settings, from: defaults) ?? Settings()
        collection = Self.load([Artwork].self, key: Keys.collection, from: defaults) ?? Artwork.seedCollection
        stats = Self.load(Stats.self, key: Keys.stats, from: defaults) ?? Stats()
        ownedPackIDs = Set(defaults.stringArray(forKey: Keys.ownedPacks) ?? [])
            .union([ArtworkCatalog.freePackID])

        if LaunchConfig.unlockOne, let idx = collection.firstIndex(where: { !$0.unlocked }) {
            collection[idx].unlocked = true
            collection[idx].unlockedDate = Date()
            collection[idx].sessionMinutes = settings.selectedDuration
        }

        // Older stored collections may miss works of packs owned meanwhile.
        syncCollectionWithOwnedPacks()

        // Sessions don't survive a relaunch, so the widget starts out "bereit".
        publishWidgetSnapshot()
    }

    // MARK: Derived
    var unlockedCount: Int { collection.filter(\.unlocked).count }
    var totalCount: Int { collection.count }
    /// Total focused minutes across collected works (drives the gallery stat).
    var totalFocusMinutes: Int { collection.compactMap(\.sessionMinutes).reduce(0, +) }
    var totalFocusHours: Int { totalFocusMinutes / 60 }

    /// A random still-locked artwork to hide behind the next session.
    func nextLockedArtwork() -> Artwork? {
        collection.filter { !$0.unlocked }.randomElement()
    }

    /// Mark an artwork unlocked and stamp it with this session's metadata.
    func unlock(_ artwork: Artwork, minutes: Int) {
        guard let idx = collection.firstIndex(where: { $0.id == artwork.id }) else { return }
        collection[idx].unlocked = true
        collection[idx].unlockedDate = Date()
        collection[idx].sessionMinutes = minutes
    }

    /// Record a fully completed focus session in the stats cache.
    func recordCompletedSession(minutes: Int) {
        stats.sessionsCompleted += 1
        stats.totalFocusMinutes += minutes
    }

    /// Record a session that was started and then abandoned before completion.
    func recordAbortedSession() {
        stats.sessionsAborted += 1
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
        syncCollectionWithOwnedPacks()
    }

    /// Make the collection mirror the owned packs: append missing works of
    /// owned packs (locked — sessions reveal them), drop still-locked works of
    /// packs no longer owned (refunds). Works already revealed stay forever.
    private func syncCollectionWithOwnedPacks() {
        var result = collection.filter { $0.unlocked || ownedPackIDs.contains($0.packID) }
        for pack in ArtworkCatalog.packs where ownedPackIDs.contains(pack.id) {
            for work in pack.works where !result.contains(where: { $0.id == work.id }) {
                result.append(work)
            }
        }
        if result != collection { collection = result }
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
            sessionsCompleted: stats.sessionsCompleted,
            worksUnlocked: unlockedCount,
            totalFocusMinutes: stats.totalFocusMinutes))
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
