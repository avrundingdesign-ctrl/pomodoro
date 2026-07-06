import Foundation

/// Push-Ereignisse vom Backend ins OnlineModel (in Produktion: Firestore-
/// Snapshot-Listener / Realtime-DB; lokal: die Community-Simulation).
enum BackendEvent {
    case presenceChanged(userID: String, presence: Presence)
    case messageReceived(userID: String, message: ChatMessage)
    case friendRequestReceived(FriendRequest)
    case friendRequestAccepted(userID: String)
    case communityEvent(CommunityEvent)
}

enum BackendError: LocalizedError {
    case handleTaken
    case emailTaken
    case unknownEmail
    case wrongPassword
    case invalidHandle
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .handleTaken:   return "Dieser Nutzername ist bereits vergeben."
        case .emailTaken:    return "Für diese E-Mail existiert bereits ein Konto."
        case .unknownEmail:  return "Kein Konto mit dieser E-Mail gefunden."
        case .wrongPassword: return "Das Passwort ist nicht korrekt."
        case .invalidHandle: return "Nutzernamen: 3–20 Zeichen, nur Buchstaben, Zahlen und Punkte."
        case .notSignedIn:   return "Du bist nicht angemeldet."
        }
    }
}

/// Alles, was der Online-Modus von einem Server braucht — als Protokoll,
/// damit das LocalBackend (voll funktionsfähige lokale Simulation) später
/// 1:1 gegen ein FirebaseBackend getauscht werden kann. Der konkrete
/// Produktionsplan steht in docs/ONLINE.md.
@MainActor
protocol FocusBackend: AnyObject {
    /// Kanal für Push-Ereignisse; wird vom OnlineModel gesetzt.
    var onEvent: ((BackendEvent) -> Void)? { get set }

    // MARK: Konto
    /// Gespeicherte Anmeldung wiederherstellen (App-Start).
    func restore() -> UserProfile?
    /// Apple-/Google-Anmeldung: Konto zu externer ID finden oder anlegen.
    func signInExternal(provider: AuthProvider, externalID: String,
                        displayName: String?) async throws -> (profile: UserProfile, isNew: Bool)
    func createEmailAccount(email: String, password: String,
                            displayName: String) async throws -> UserProfile
    func signInEmail(email: String, password: String) async throws -> UserProfile
    func signOut()
    /// Profil speichern; prüft Handle-Eindeutigkeit.
    func saveProfile(_ profile: UserProfile) async throws
    func isHandleAvailable(_ handle: String) -> Bool

    // MARK: Community
    /// Alle bekannten fremden Profile (Suche, Karte, Vorschläge).
    func communityProfiles() -> [UserProfile]
    func profile(id: String) -> UserProfile?
    func presence(of id: String) -> Presence
    /// Statistiken fremder Nutzer; die eigenen rechnet das OnlineModel aus
    /// der echten Historie.
    func stats(of id: String) -> UserStats
    func recentEvents() -> [CommunityEvent]

    // MARK: Freunde
    func friendIDs() -> Set<String>
    func incomingRequests() -> [FriendRequest]
    func sendFriendRequest(to id: String)
    func respondToRequest(_ requestID: String, accept: Bool)
    func removeFriend(_ id: String)

    // MARK: Nachrichten
    func messages(with id: String) -> [ChatMessage]
    func send(_ kind: MessageKind, to id: String)
    func markThreadRead(with id: String)

    // MARK: Eigene Aktivität
    func reportOwnPresence(_ presence: Presence)
    func reportOwnEvent(_ kind: CommunityEventKind)

    /// Simulations-/Sync-Herzschlag; das OnlineModel ruft ihn periodisch auf.
    func tick()
}
