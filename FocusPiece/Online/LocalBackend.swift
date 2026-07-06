import Foundation
import CryptoKit

/// Voll funktionsfähiges lokales Backend: Konten, Freunde, Chats und eine
/// lebendige, simulierte Community — komplett offline und persistent.
/// Es implementiert dasselbe Protokoll wie das spätere Server-Backend
/// (docs/ONLINE.md), sodass der Wechsel die App-Schicht nicht berührt.
@MainActor
final class LocalBackend: FocusBackend {

    var onEvent: ((BackendEvent) -> Void)?

    private var disk = DiskState()
    private var ownPresence: Presence = .online
    /// Laufende Simulations-Sessions der Demo-Nutzer.
    private var live: [String: LiveSession] = [:]
    /// Sperre bis zum nächsten möglichen Session-Start je Demo-Nutzer.
    private var cooldownUntil: [String: Date] = [:]
    private var events: [CommunityEvent] = []
    /// Deterministisch generierte Historien der Demo-Nutzer (pro Launch).
    private var demoHistories: [String: [FocusSessionRecord]] = [:]

    init() {
        disk = Self.loadDisk() ?? DiskState()
        for persona in Self.personas {
            demoHistories[persona.id] = Self.generateHistory(for: persona)
        }
        seedInitialLiveState()
        seedInitialEvents()
    }

    // MARK: - Konto

    func restore() -> UserProfile? { disk.account }

    func signInExternal(provider: AuthProvider, externalID: String,
                        displayName: String?) async throws -> (profile: UserProfile, isNew: Bool) {
        let key = "\(provider.rawValue):\(externalID)"
        if let existing = disk.externalAccounts[key],
           let profile = disk.profiles[existing] ?? (disk.account?.id == existing ? disk.account : nil) {
            disk.account = profile
            save()
            return (profile, false)
        }
        let name = displayName?.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? displayName! : "Fokus-Fan"
        let profile = makeProfile(displayName: name, provider: provider)
        disk.externalAccounts[key] = profile.id
        disk.profiles[profile.id] = profile
        disk.account = profile
        save()
        scheduleWelcome()
        return (profile, true)
    }

    func createEmailAccount(email: String, password: String,
                            displayName: String) async throws -> UserProfile {
        let mail = email.lowercased().trimmingCharacters(in: .whitespaces)
        guard disk.emailAccounts[mail] == nil else { throw BackendError.emailTaken }
        let profile = makeProfile(displayName: displayName, provider: .email)
        disk.emailAccounts[mail] = EmailAccount(passwordHash: Self.hash(password), profileID: profile.id)
        disk.profiles[profile.id] = profile
        disk.account = profile
        save()
        scheduleWelcome()
        return profile
    }

    func signInEmail(email: String, password: String) async throws -> UserProfile {
        let mail = email.lowercased().trimmingCharacters(in: .whitespaces)
        guard let acc = disk.emailAccounts[mail] else { throw BackendError.unknownEmail }
        guard acc.passwordHash == Self.hash(password) else { throw BackendError.wrongPassword }
        guard let profile = disk.profiles[acc.profileID] else { throw BackendError.unknownEmail }
        disk.account = profile
        save()
        return profile
    }

    func signOut() {
        reportOwnPresence(.offline)
        disk.account = nil
        save()
    }

    func saveProfile(_ profile: UserProfile) async throws {
        let handle = profile.handle.lowercased()
        guard Self.isValidHandle(handle) else { throw BackendError.invalidHandle }
        let takenByOther = Self.personas.contains { $0.handle == handle }
            || disk.profiles.values.contains { $0.handle == handle && $0.id != profile.id }
        guard !takenByOther else { throw BackendError.handleTaken }
        var p = profile
        p.handle = handle
        disk.profiles[p.id] = p
        disk.account = p
        save()
    }

    func isHandleAvailable(_ handle: String) -> Bool {
        let h = handle.lowercased()
        guard Self.isValidHandle(h) else { return false }
        if Self.personas.contains(where: { $0.handle == h }) { return false }
        return !disk.profiles.values.contains { $0.handle == h && $0.id != disk.account?.id }
    }

    // MARK: - Community

    func communityProfiles() -> [UserProfile] {
        Self.personas.map(\.profile)
    }

    func profile(id: String) -> UserProfile? {
        if disk.account?.id == id { return disk.account }
        return Self.personas.first { $0.id == id }?.profile ?? disk.profiles[id]
    }

    func presence(of id: String) -> Presence {
        if id == disk.account?.id { return ownPresence }
        guard let session = live[id] else { return isDemoOnline(id) ? .online : .offline }
        return session.presence(now: Date())
    }

    func stats(of id: String) -> UserStats {
        guard let history = demoHistories[id] else { return UserStats() }
        let rounds = history.count
        return StatsEngine.stats(records: history, worksUnlocked: min(28, 3 + rounds / 10))
    }

    func recentEvents() -> [CommunityEvent] { events }

    // MARK: - Freunde

    func friendIDs() -> Set<String> { disk.friendIDs }
    func incomingRequests() -> [FriendRequest] { disk.incomingRequests }

    func sendFriendRequest(to id: String) {
        guard !disk.friendIDs.contains(id), !disk.outgoingRequestIDs.contains(id) else { return }
        disk.outgoingRequestIDs.insert(id)
        save()
        // Demo-Nutzer nehmen nach kurzer Zeit an und begrüßen dich.
        guard let persona = Self.personas.first(where: { $0.id == id }) else { return }
        after(seconds: .random(in: 8...20)) { [weak self] in
            guard let self, self.disk.outgoingRequestIDs.contains(id) else { return }
            self.disk.outgoingRequestIDs.remove(id)
            self.disk.friendIDs.insert(id)
            self.save()
            self.onEvent?(.friendRequestAccepted(userID: id))
            self.after(seconds: 4) { [weak self] in
                self?.deliver(.text(persona.greeting), from: id)
            }
        }
    }

    func respondToRequest(_ requestID: String, accept: Bool) {
        guard let idx = disk.incomingRequests.firstIndex(where: { $0.id == requestID }) else { return }
        let request = disk.incomingRequests.remove(at: idx)
        if accept {
            disk.friendIDs.insert(request.from.id)
            if let persona = Self.personas.first(where: { $0.id == request.from.id }) {
                after(seconds: .random(in: 5...15)) { [weak self] in
                    self?.deliver(.text(persona.greeting), from: persona.id)
                }
            }
        }
        save()
    }

    func removeFriend(_ id: String) {
        disk.friendIDs.remove(id)
        disk.chats[id] = nil
        save()
    }

    // MARK: - Nachrichten

    func messages(with id: String) -> [ChatMessage] { disk.chats[id] ?? [] }

    func send(_ kind: MessageKind, to id: String) {
        guard let own = disk.account else { return }
        disk.chats[id, default: []].append(ChatMessage(senderID: own.id, kind: kind, read: true))
        save()
        scheduleReply(to: kind, from: id)
    }

    func markThreadRead(with id: String) {
        guard var thread = disk.chats[id] else { return }
        for i in thread.indices { thread[i].read = true }
        disk.chats[id] = thread
        save()
    }

    // MARK: - Eigene Aktivität

    func reportOwnPresence(_ presence: Presence) {
        ownPresence = presence
        guard let own = disk.account else { return }
        onEvent?(.presenceChanged(userID: own.id, presence: presence))
    }

    func reportOwnEvent(_ kind: CommunityEventKind) {
        guard let own = disk.account else { return }
        push(CommunityEvent(userID: own.id, kind: kind))
    }

    // MARK: - Simulation

    /// Herzschlag: Demo-Sessions starten, fortschreiten und enden lassen.
    func tick() {
        let now = Date()
        for persona in Self.personas {
            if let session = live[persona.id] {
                if now >= session.endsAt {
                    live[persona.id] = nil
                    cooldownUntil[persona.id] = now.addingTimeInterval(.random(in: 300...2400))
                    let minutes = Int(session.endsAt.timeIntervalSince(session.startedAt) / 60)
                    push(CommunityEvent(userID: persona.id,
                                        kind: .sessionCompleted(minutes: max(10, minutes),
                                                                artworkTitle: session.artworkTitle)))
                    onEvent?(.presenceChanged(userID: persona.id, presence: .online))
                    // Hin und wieder fällt mit der Session ein Erfolg.
                    if Double.random(in: 0...1) < 0.15, let a = Achievement.all.randomElement() {
                        push(CommunityEvent(userID: persona.id, kind: .achievementEarned(achievementID: a.id)))
                    }
                } else {
                    onEvent?(.presenceChanged(userID: persona.id, presence: session.presence(now: now)))
                }
                continue
            }
            // Startchance pro Tick, gewichtet nach Aktivität und Tageszeit.
            if now >= (cooldownUntil[persona.id] ?? .distantPast),
               Double.random(in: 0...1) < persona.activity * 0.10 * hourFactor(for: persona, now: now) {
                startSession(for: persona, elapsed: 0)
                push(CommunityEvent(userID: persona.id, kind: .sessionStarted))
            }
        }
        // Fokussierst du gerade, feuert dich ab und zu ein Freund an.
        if ownPresence.isInSession, !disk.friendIDs.isEmpty, Double.random(in: 0...1) < 0.05,
           let friendID = disk.friendIDs.randomElement(),
           let _ = Self.personas.first(where: { $0.id == friendID }),
           let nudge = Nudge.allCases.randomElement() {
            deliver(.nudge(nudge), from: friendID)
        }
    }

    private func startSession(for persona: DemoPersona, elapsed: TimeInterval) {
        let titles = (Artwork.seedCollection + ArtPack.catalog.flatMap(\.artworks)).map(\.title)
        let duration = TimeInterval.random(in: 900...3000)
        let started = Date().addingTimeInterval(-elapsed)
        live[persona.id] = LiveSession(
            startedAt: started,
            endsAt: started.addingTimeInterval(duration),
            artworkTitle: titles.randomElement() ?? "Verborgenes Werk",
            totalRounds: Int.random(in: 2...4))
    }

    /// Nachts sind weniger Demo-Nutzer unterwegs; um die persönliche
    /// Kernzeit eines Nutzers herum deutlich mehr.
    private func hourFactor(for persona: DemoPersona, now: Date) -> Double {
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 6 { return 0.15 }
        let distance = min(abs(hour - persona.hourCenter), 24 - abs(hour - persona.hourCenter))
        return max(0.3, 1.6 - Double(distance) * 0.2)
    }

    private func isDemoOnline(_ id: String) -> Bool {
        // Stabil pro Stunde: gut die Hälfte der Community ist "online".
        let hour = Calendar.current.component(.hour, from: Date())
        return (abs(id.hashValue) + hour) % 5 != 0
    }

    /// Beim Start sind einige Demo-Nutzer bereits mitten in einer Session,
    /// damit Live-Liste und Karte sofort leben.
    private func seedInitialLiveState() {
        var rng = SeededRNG(seed: UInt64(Date().timeIntervalSince1970 / 1800))
        for persona in Self.personas where Double.random(in: 0...1, using: &rng) < 0.28 + persona.activity * 0.2 {
            startSession(for: persona, elapsed: .random(in: 120...1200, using: &rng))
        }
    }

    private func seedInitialEvents() {
        var rng = SeededRNG(seed: UInt64(Date().timeIntervalSince1970 / 3600) &+ 7)
        let titles = (Artwork.seedCollection + ArtPack.catalog.flatMap(\.artworks)).map(\.title)
        for persona in Self.personas.shuffled(using: &rng).prefix(5) {
            let minutesAgo = Double.random(in: 10...180, using: &rng)
            events.append(CommunityEvent(
                userID: persona.id,
                kind: .sessionCompleted(minutes: [25, 50, 75, 100].randomElement(using: &rng)!,
                                        artworkTitle: titles.randomElement(using: &rng)!),
                date: Date().addingTimeInterval(-minutesAgo * 60)))
        }
        events.sort { $0.date > $1.date }
    }

    // MARK: - Antwortverhalten

    private func scheduleReply(to kind: MessageKind, from id: String) {
        guard let persona = Self.personas.first(where: { $0.id == id }) else { return }
        // In einer laufenden Fokus-Session antwortet niemand sofort — realistisch.
        let focusing = live[id] != nil
        let delay = focusing ? TimeInterval.random(in: 60...180) : .random(in: 12...45)
        guard Double.random(in: 0...1) < persona.chattiness else { return }
        after(seconds: delay) { [weak self] in
            let reply: MessageKind
            switch kind {
            case .nudge:
                reply = .text(["Danke dir! 🙌", "Das motiviert — danke!", "Gleich zurück an dich! 💪"].randomElement()!)
            case .artCard:
                reply = .text(["Wow, schönes Werk!", "Das hängt bei mir auch schon. 😄", "Sehr gute Wahl!"].randomElement()!)
            case .text:
                reply = .text(persona.lines.randomElement() ?? "Weiter geht's — Fokus!")
            }
            self?.deliver(reply, from: id)
        }
    }

    /// Eingehende Nachricht eines Demo-Nutzers zustellen.
    private func deliver(_ kind: MessageKind, from id: String) {
        let message = ChatMessage(senderID: id, kind: kind)
        disk.chats[id, default: []].append(message)
        save()
        onEvent?(.messageReceived(userID: id, message: message))
    }

    /// Neue Konten bekommen nach kurzer Zeit zwei Freundschaftsanfragen —
    /// die Community stellt sich vor.
    private func scheduleWelcome() {
        var rng = SeededRNG(seed: UInt64(abs((disk.account?.id ?? "x").hashValue)))
        let greeters = Self.personas.shuffled(using: &rng).prefix(2)
        var delay: TimeInterval = 15
        for persona in greeters {
            after(seconds: delay) { [weak self] in
                guard let self, self.disk.account != nil,
                      !self.disk.friendIDs.contains(persona.id),
                      !self.disk.incomingRequests.contains(where: { $0.from.id == persona.id }) else { return }
                let request = FriendRequest(id: UUID().uuidString, from: persona.profile, sentAt: Date())
                self.disk.incomingRequests.append(request)
                self.save()
                self.onEvent?(.friendRequestReceived(request))
            }
            delay += .random(in: 20...40)
        }
    }

    private func push(_ event: CommunityEvent) {
        events.insert(event, at: 0)
        if events.count > 40 { events.removeLast(events.count - 40) }
        onEvent?(.communityEvent(event))
    }

    private func after(seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            work()
        }
    }

    // MARK: - Profil-Fabrik

    private func makeProfile(displayName: String, provider: AuthProvider) -> UserProfile {
        var base = Self.handleSuggestion(from: displayName)
        var handle = base
        var counter = 2
        while !isHandleAvailable(handle) {
            handle = "\(base)\(counter)"
            counter += 1
        }
        if base.isEmpty { base = "fokus"; handle = "fokus\(Int.random(in: 100...999))" }
        return UserProfile(id: UUID().uuidString, handle: handle, displayName: displayName,
                           city: .berlin, joinedAt: Date(), provider: provider)
    }

    static func handleSuggestion(from name: String) -> String {
        let folded = name.lowercased()
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: " ", with: ".")
        let allowed = folded.unicodeScalars.filter {
            CharacterSet.lowercaseLetters.contains($0)
                || CharacterSet.decimalDigits.contains($0) || $0 == "."
        }
        return String(String.UnicodeScalarView(allowed)).prefix(20).description
    }

    static func isValidHandle(_ handle: String) -> Bool {
        handle.range(of: "^[a-z0-9.]{3,20}$", options: .regularExpression) != nil
    }

    private static func hash(_ password: String) -> String {
        SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Persistenz

    private struct EmailAccount: Codable {
        let passwordHash: String
        let profileID: String
    }

    private struct DiskState: Codable {
        var account: UserProfile?
        /// Alle je auf diesem Gerät angelegten Profile (id → Profil).
        var profiles: [String: UserProfile] = [:]
        /// "provider:externalID" → Profil-ID (Apple/Google).
        var externalAccounts: [String: String] = [:]
        var emailAccounts: [String: EmailAccount] = [:]
        var friendIDs: Set<String> = []
        var incomingRequests: [FriendRequest] = []
        var outgoingRequestIDs: Set<String> = []
        var chats: [String: [ChatMessage]] = [:]
    }

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusPiece", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("online_local.json")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(disk) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }

    private static func loadDisk() -> DiskState? {
        guard let data = try? Data(contentsOf: storeURL) else { return nil }
        return try? JSONDecoder().decode(DiskState.self, from: data)
    }

    // MARK: - Demo-Community

    private struct LiveSession {
        let startedAt: Date
        let endsAt: Date
        let artworkTitle: String
        let totalRounds: Int

        func presence(now: Date) -> Presence {
            let total = endsAt.timeIntervalSince(startedAt)
            let progress = min(1, max(0, now.timeIntervalSince(startedAt) / max(1, total)))
            let round = min(totalRounds, Int(progress * Double(totalRounds)) + 1)
            return .focusing(FocusStatus(artworkTitle: artworkTitle, round: round,
                                         totalRounds: totalRounds, progress: progress,
                                         startedAt: startedAt))
        }
    }

    struct DemoPersona {
        let id: String
        let handle: String
        let name: String
        let city: City
        let bio: String
        let activity: Double      // 0…1: wie oft Sessions laufen
        let chattiness: Double    // 0…1: Antwortwahrscheinlichkeit
        let hourCenter: Int       // typische Fokus-Stunde
        let greeting: String
        let lines: [String]

        var profile: UserProfile {
            UserProfile(id: id, handle: handle, displayName: name, city: city, bio: bio,
                        joinedAt: Date().addingTimeInterval(-86400 * 200), provider: .email)
        }
    }

    static let personas: [DemoPersona] = [
        DemoPersona(id: "demo.lena", handle: "lena.fokus", name: "Lena Marquardt",
                    city: City.catalog[0], bio: "Medizinstudentin. Lernt in 50er-Blöcken.",
                    activity: 0.9, chattiness: 0.9, hourCenter: 9,
                    greeting: "Hey! Schön, dass du dabei bist — auf viele fokussierte Stunden! 🎨",
                    lines: ["Gerade Anatomie durchgezogen — 4 Runden!", "Heute läuft's richtig gut.", "Machst du auch gerade eine Session?"]),
        DemoPersona(id: "demo.jonas", handle: "jonas.deep", name: "Jonas Beck",
                    city: City.catalog[1], bio: "Softwareentwickler, Deep-Work-Fan.",
                    activity: 0.8, chattiness: 0.7, hourCenter: 10,
                    greeting: "Willkommen! Die Karte ist mein Lieblingsfeature — man sieht nie allein zu sein.",
                    lines: ["Kopfhörer auf, Welt aus.", "Refactoring-Session beendet — 100 Minuten.", "Gleich noch eine Runde."]),
        DemoPersona(id: "demo.mira", handle: "mira.paints", name: "Mira Steiner",
                    city: City.catalog[7], bio: "Illustratorin aus Wien. Sammelt die Impressionisten.",
                    activity: 0.7, chattiness: 0.95, hourCenter: 14,
                    greeting: "Hallo! Welche Werke hast du schon enthüllt? Ich jage gerade die Monets. 🌸",
                    lines: ["Die Seerosen sind fast enthüllt!", "Nachmittags fokussiert es sich am besten.", "Kunstpause — im Wortsinn. 😄"]),
        DemoPersona(id: "demo.david", handle: "david.k", name: "David Kaufmann",
                    city: City.catalog[2], bio: "Jura-Examen 2026. Pomodoro seit Tag 1.",
                    activity: 0.85, chattiness: 0.5, hourCenter: 8,
                    greeting: "Servus! Zusammen fokussieren motiviert doppelt — willkommen.",
                    lines: ["Karteikarten, Runde 3 von 4.", "Morgens um 7 ist die Bibliothek leer — perfekt.", "Kurze Pause, dann weiter."]),
        DemoPersona(id: "demo.sophie", handle: "sophie.study", name: "Sophie Brunner",
                    city: City.catalog[9], bio: "PhD-Studentin. Schreibt an der Diss.",
                    activity: 0.75, chattiness: 0.8, hourCenter: 11,
                    greeting: "Hi! Ich schreibe meine Diss mit FocusPiece — ein Kapitel pro Werk. 📚",
                    lines: ["500 Wörter diese Session!", "Der Schreibflow war heute gut.", "Zürich regnet — perfektes Fokuswetter."]),
        DemoPersona(id: "demo.paul", handle: "paul.writes", name: "Paul Winkler",
                    city: City.catalog[6], bio: "Autor. Ein Roman, viele Runden.",
                    activity: 0.6, chattiness: 0.85, hourCenter: 21,
                    greeting: "Willkommen in der Galerie! Abends schreibt es sich am besten, findest du nicht?",
                    lines: ["Kapitel 12 ist fertig!", "Nachts sind die Ideen wach.", "Noch eine Runde, dann Feierabend."]),
        DemoPersona(id: "demo.emma", handle: "emma.reads", name: "Emma de Vries",
                    city: City.catalog[10], bio: "Lektorin aus Amsterdam.",
                    activity: 0.65, chattiness: 0.75, hourCenter: 15,
                    greeting: "Hoi! Schön, dich hier zu sehen. Auf gute Sessions! ✨",
                    lines: ["Manuskript Nummer drei diese Woche.", "Tee, Timer, Text — mehr braucht es nicht.", "Die große Welle hing bei mir zuerst."]),
        DemoPersona(id: "demo.noah", handle: "noah.codes", name: "Noah Lindgren",
                    city: City.catalog[13], bio: "Indie-Entwickler. 4×25 jeden Morgen.",
                    activity: 0.8, chattiness: 0.6, hourCenter: 7,
                    greeting: "Hej! Morgens vier Runden, dann gehört der Tag mir. Probier's mal!",
                    lines: ["Ship it! Session beendet.", "Bugfixing zählt auch als Kunst.", "Frühstart heute — 6:30."]),
        DemoPersona(id: "demo.clara", handle: "clara.art", name: "Clara Fontaine",
                    city: City.catalog[11], bio: "Kunstgeschichte an der Sorbonne.",
                    activity: 0.7, chattiness: 0.9, hourCenter: 16,
                    greeting: "Bonjour! Die Alten Meister sind mein Paket-Tipp — die Nachtwache lohnt sich. 🖼️",
                    lines: ["Heute: Vermeer-Seminar vorbereitet.", "Paris, Café, Fokus.", "Die goldene Adele ist enthüllt!"]),
        DemoPersona(id: "demo.finn", handle: "finn.flow", name: "Finn Hartmann",
                    city: City.catalog[3], bio: "Medizinische Weiterbildung, Nachtschichten.",
                    activity: 0.5, chattiness: 0.65, hourCenter: 23,
                    greeting: "Hi! Ich fokussiere nach der Schicht — die Karte zeigt, wer noch wach ist. 🌙",
                    lines: ["Nachtschicht vorbei, eine Runde noch.", "Der Schrei passt zu meinem Dienstplan. 😅", "Ruhige Nacht heute."]),
        DemoPersona(id: "demo.yuki", handle: "yuki.zen", name: "Yuki Tanaka",
                    city: City.catalog[21], bio: "UX-Designerin in Tokio. Hokusai-Fan.",
                    activity: 0.75, chattiness: 0.7, hourCenter: 13,
                    greeting: "こんにちは! Willkommen — die japanischen Meister sind natürlich Pflicht. 🌊",
                    lines: ["Der Kirifuri-Wasserfall ist enthüllt!", "Mittagsfokus im Büro.", "Acht Zeitzonen, ein Timer."]),
        DemoPersona(id: "demo.aylin", handle: "aylin.study", name: "Aylin Demir",
                    city: City.catalog[4], bio: "BWL-Studentin, Werkstudentin, Streak-Jägerin.",
                    activity: 0.85, chattiness: 0.8, hourCenter: 18,
                    greeting: "Hey! Mein Streak steht bei 12 Tagen — versuch mich einzuholen! 🔥",
                    lines: ["Streak lebt! Tag 12.", "Nach der Arbeit zwei Runden, immer.", "Controlling-Klausur, ich komme."]),
    ]

    /// Deterministische, plausible 12-Wochen-Historie eines Demo-Nutzers.
    private static func generateHistory(for persona: DemoPersona) -> [FocusSessionRecord] {
        var rng = SeededRNG(seed: UInt64(abs(persona.id.hashValue)))
        var records: [FocusSessionRecord] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let artworkIDs = Artwork.seedCollection.map(\.id)
        for dayOffset in 0..<StatsEngine.heatmapDays {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            // Wochenende etwas seltener; Grundfleiß nach Aktivitätswert.
            let weekday = calendar.component(.weekday, from: day)
            let weekendDamp = (weekday == 1 || weekday == 7) ? 0.6 : 1.0
            guard Double.random(in: 0...1, using: &rng) < persona.activity * 0.75 * weekendDamp else { continue }
            let rounds = Int.random(in: 1...5, using: &rng)
            for _ in 0..<rounds {
                let hour = max(5, min(23, persona.hourCenter + Int.random(in: -3...3, using: &rng)))
                let minute = Int.random(in: 0...59, using: &rng)
                guard let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
                records.append(FocusSessionRecord(date: date,
                                                  minutes: [15, 25, 25, 25, 45, 50].randomElement(using: &rng)!,
                                                  artworkID: artworkIDs.randomElement(using: &rng)!))
            }
        }
        return records
    }
}

/// Deterministischer RNG (SplitMix64) für stabile Demo-Daten.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
