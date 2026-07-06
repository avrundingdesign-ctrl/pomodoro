import Foundation
import SwiftUI

/// Zentrale, beobachtbare Fassade des Online-Modus: Account, Freunde,
/// Presence, Chats, Community-Feed, Wallet und Bilder-Pakete.
/// Spricht ausschließlich über das FocusBackend-Protokoll mit der Welt.
@MainActor
final class OnlineModel: ObservableObject {

    // MARK: Account
    @Published private(set) var profile: UserProfile?
    /// Frisch angelegtes Konto → Profil-Einrichtung (Handle, Stadt) zeigen.
    @Published var needsProfileSetup = false

    // MARK: Community
    @Published private(set) var friends: [UserProfile] = []
    @Published private(set) var requests: [FriendRequest] = []
    @Published private(set) var presences: [String: Presence] = [:]
    @Published private(set) var feed: [CommunityEvent] = []
    @Published private(set) var chats: [String: [ChatMessage]] = [:]
    @Published private(set) var ownPresence: Presence = .online

    // MARK: Wallet & Store
    @Published private(set) var coins: Int
    @Published private(set) var transactions: [CoinTransaction]
    @Published private(set) var ownedPackIDs: Set<String>

    let iap = IAPManager()
    weak var app: AppModel?

    private let backend: FocusBackend
    private var timer: Timer?
    private var earnedAchievementIDs: Set<String>

    private enum Keys {
        static let coins = "fp.coins"
        static let coinTx = "fp.coinTx"
        static let ownedPacks = "fp.ownedPacks"
        static let achievements = "fp.earnedAchievements"
    }

    var isSignedIn: Bool { profile != nil }

    init(backend: FocusBackend? = nil) {
        // Default im Body statt als Default-Argument: das Argument würde im
        // nonisolated Kontext des Aufrufers ausgewertet (MainActor-Konflikt).
        self.backend = backend ?? LocalBackend()
        let d = UserDefaults.standard
        coins = d.object(forKey: Keys.coins) as? Int ?? 0
        ownedPackIDs = Set(d.stringArray(forKey: Keys.ownedPacks) ?? [])
        earnedAchievementIDs = Set(d.stringArray(forKey: Keys.achievements) ?? [])
        if let data = d.data(forKey: Keys.coinTx),
           let tx = try? JSONDecoder().decode([CoinTransaction].self, from: data) {
            transactions = tx
        } else {
            transactions = []
        }

        self.backend.onEvent = { [weak self] event in self?.handle(event) }
        iap.onCoinsPurchased = { [weak self] amount, _ in
            self?.grant(coins: amount, reason: "Münz-Kauf")
        }

        profile = self.backend.restore()
        refresh()

        // Simulations-/Sync-Herzschlag.
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.backend.tick()
            }
        }
    }

    // MARK: - Anmeldung

    func signInExternal(provider: AuthProvider, externalID: String, displayName: String?) async throws {
        let (profile, isNew) = try await backend.signInExternal(
            provider: provider, externalID: externalID, displayName: displayName)
        self.profile = profile
        needsProfileSetup = isNew
        refresh()
        backend.reportOwnPresence(.online)
    }

    func createEmailAccount(email: String, password: String, displayName: String) async throws {
        profile = try await backend.createEmailAccount(
            email: email, password: password, displayName: displayName)
        needsProfileSetup = true
        refresh()
        backend.reportOwnPresence(.online)
    }

    func signInEmail(email: String, password: String) async throws {
        profile = try await backend.signInEmail(email: email, password: password)
        needsProfileSetup = false
        refresh()
        backend.reportOwnPresence(.online)
    }

    func signOut() {
        backend.signOut()
        profile = nil
        friends = []
        requests = []
        chats = [:]
        needsProfileSetup = false
    }

    func saveProfile(_ updated: UserProfile) async throws {
        try await backend.saveProfile(updated)
        profile = updated
        needsProfileSetup = false
    }

    func isHandleAvailable(_ handle: String) -> Bool { backend.isHandleAvailable(handle) }

    // MARK: - Community-Zugriff

    /// Alle fremden Profile — Freunde zuerst, dann Vorschläge.
    var communityProfiles: [UserProfile] {
        let all = backend.communityProfiles()
        let friendSet = Set(friends.map(\.id))
        return all.sorted { (friendSet.contains($0.id) ? 0 : 1, $0.displayName)
                          < (friendSet.contains($1.id) ? 0 : 1, $1.displayName) }
    }

    /// Vorschläge: noch keine Freunde, keine offene Anfrage.
    var suggestions: [UserProfile] {
        let friendSet = Set(friends.map(\.id))
        let requested = Set(requests.map(\.from.id))
        return backend.communityProfiles().filter {
            !friendSet.contains($0.id) && !requested.contains($0.id)
        }
    }

    func profile(of id: String) -> UserProfile? {
        if id == profile?.id { return profile }
        return backend.profile(id: id)
    }

    func presence(of id: String) -> Presence {
        if id == profile?.id { return ownPresence }
        return presences[id] ?? backend.presence(of: id)
    }

    /// Eigene Statistiken aus der echten Historie; fremde vom Backend.
    var myStats: UserStats {
        StatsEngine.stats(records: app?.history ?? [], worksUnlocked: app?.unlockedCount ?? 0)
    }

    func stats(of id: String) -> UserStats {
        id == profile?.id ? myStats : backend.stats(of: id)
    }

    var isFriend: (String) -> Bool {
        let ids = Set(friends.map(\.id))
        return { ids.contains($0) }
    }

    struct LiveEntry: Identifiable {
        let profile: UserProfile
        let presence: Presence
        let status: FocusStatus
        var id: String { profile.id }
    }

    /// Wer ist gerade in einer Session? (Eigenes Profil zuerst, dann Community.)
    var liveUsers: [LiveEntry] {
        var result: [LiveEntry] = []
        if let me = profile, let s = ownPresence.focusStatus {
            result.append(LiveEntry(profile: me, presence: ownPresence, status: s))
        }
        for p in communityProfiles {
            let presence = presence(of: p.id)
            if let s = presence.focusStatus {
                result.append(LiveEntry(profile: p, presence: presence, status: s))
            }
        }
        return result
    }

    // MARK: - Freunde

    func sendFriendRequest(to id: String) {
        backend.sendFriendRequest(to: id)
        objectWillChange.send()
    }

    func respond(to request: FriendRequest, accept: Bool) {
        backend.respondToRequest(request.id, accept: accept)
        requests.removeAll { $0.id == request.id }
        refresh()
    }

    func removeFriend(_ id: String) {
        backend.removeFriend(id)
        refresh()
    }

    // MARK: - Nachrichten

    func send(_ kind: MessageKind, to id: String) {
        backend.send(kind, to: id)
        chats[id] = backend.messages(with: id)
    }

    func markThreadRead(with id: String) {
        backend.markThreadRead(with: id)
        chats[id] = backend.messages(with: id)
    }

    func unreadCount(with id: String) -> Int {
        (chats[id] ?? []).filter { $0.senderID == id && !$0.read }.count
    }

    var totalUnread: Int {
        chats.reduce(0) { sum, entry in
            sum + entry.value.filter { $0.senderID == entry.key && !$0.read }.count
        }
    }

    // MARK: - Session-Hooks (aus dem Fokus-Tab)

    /// Presence-Update der eigenen laufenden Session.
    func reportPresence(_ presence: Presence) {
        ownPresence = presence
        backend.reportOwnPresence(presence)
    }

    /// Eine abgeschlossene Fokus-Runde: Münzen gutschreiben.
    func roundCompleted(minutes: Int) {
        var earned = CoinRules.coins(forRoundMinutes: minutes)
        var reason = "Fokus-Runde (\(minutes) Min)"
        // Erste Runde des Tages → kleiner Bonus. Die Runde selbst wurde
        // bereits in die Historie geschrieben, daher Zählung == 1.
        let cal = Calendar.current
        let todayRounds = (app?.history ?? []).filter { cal.isDateInToday($0.date) }.count
        if todayRounds == 1 {
            earned += CoinRules.firstOfDayBonus
            reason = "Erste Runde des Tages"
        }
        grant(coins: earned, reason: reason)
        checkAchievements()
    }

    /// Kompletter Zyklus geschafft: Bonus + Community-Ereignis.
    func cycleCompleted(minutes: Int, artworkTitle: String) {
        grant(coins: CoinRules.cycleBonus, reason: "Zyklus-Bonus")
        backend.reportOwnEvent(.sessionCompleted(minutes: minutes, artworkTitle: artworkTitle))
        checkAchievements()
    }

    // MARK: - Wallet & Pakete

    func owns(_ pack: ArtPack) -> Bool { ownedPackIDs.contains(pack.id) }

    /// Paket mit Münzen freischalten; die Werke landen gesperrt in der Galerie.
    @discardableResult
    func purchase(_ pack: ArtPack) -> Bool {
        guard !owns(pack), coins >= pack.priceCoins else { return false }
        coins -= pack.priceCoins
        ownedPackIDs.insert(pack.id)
        record(CoinTransaction(amount: -pack.priceCoins, reason: "Paket: \(pack.name)"))
        app?.addArtworks(pack.artworks)
        backend.reportOwnEvent(.packUnlocked(packName: pack.name))
        persistWallet()
        return true
    }

    private func grant(coins amount: Int, reason: String) {
        guard amount > 0 else { return }
        coins += amount
        record(CoinTransaction(amount: amount, reason: reason))
        persistWallet()
    }

    private func record(_ tx: CoinTransaction) {
        transactions.insert(tx, at: 0)
        if transactions.count > 60 { transactions.removeLast(transactions.count - 60) }
    }

    private func persistWallet() {
        let d = UserDefaults.standard
        d.set(coins, forKey: Keys.coins)
        d.set(Array(ownedPackIDs), forKey: Keys.ownedPacks)
        if let data = try? JSONEncoder().encode(transactions) { d.set(data, forKey: Keys.coinTx) }
    }

    // MARK: - Achievements

    /// Neue Erfolge erkennen und in den Community-Feed melden.
    private func checkAchievements() {
        let earned = Set(Achievement.earned(by: myStats).map(\.id))
        let fresh = earned.subtracting(earnedAchievementIDs)
        guard !fresh.isEmpty else { return }
        earnedAchievementIDs.formUnion(fresh)
        UserDefaults.standard.set(Array(earnedAchievementIDs), forKey: Keys.achievements)
        if isSignedIn {
            for id in fresh { backend.reportOwnEvent(.achievementEarned(achievementID: id)) }
        }
    }

    // MARK: - Sync

    /// Zustand vollständig vom Backend übernehmen (Start, Login, Foreground).
    func refresh() {
        friends = backend.friendIDs().compactMap { backend.profile(id: $0) }
            .sorted { $0.displayName < $1.displayName }
        requests = backend.incomingRequests()
        feed = backend.recentEvents()
        var map: [String: Presence] = [:]
        for p in backend.communityProfiles() { map[p.id] = backend.presence(of: p.id) }
        presences = map
        var threads: [String: [ChatMessage]] = [:]
        for f in friends { threads[f.id] = backend.messages(with: f.id) }
        chats = threads
    }

    private func handle(_ event: BackendEvent) {
        switch event {
        case .presenceChanged(let id, let presence):
            presences[id] = presence
        case .messageReceived(let id, let message):
            chats[id, default: []].append(message)
        case .friendRequestReceived(let request):
            if !requests.contains(where: { $0.id == request.id }) { requests.append(request) }
        case .friendRequestAccepted:
            refresh()
        case .communityEvent(let event):
            feed.insert(event, at: 0)
            if feed.count > 40 { feed.removeLast(feed.count - 40) }
        }
    }
}
