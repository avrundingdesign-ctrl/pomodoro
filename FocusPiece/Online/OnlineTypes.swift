import Foundation
import CoreLocation

// MARK: - Account & Profil

/// Über welchen Weg das Konto angelegt wurde.
enum AuthProvider: String, Codable {
    case apple, google, email

    var label: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        case .email: return "E-Mail"
        }
    }
}

/// Eine Stadt als grober, selbst gewählter Standort — bewusst keine
/// Geolokalisierung: privatsphärenfreundlich und ohne Permission-Dialog.
struct City: Codable, Equatable, Hashable, Identifiable {
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double

    var id: String { "\(name), \(country)" }
    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    static let berlin = City(name: "Berlin", country: "Deutschland", latitude: 52.52, longitude: 13.405)

    /// Auswahlliste für Profil & Onboarding.
    static let catalog: [City] = [
        berlin,
        City(name: "Hamburg", country: "Deutschland", latitude: 53.551, longitude: 9.994),
        City(name: "München", country: "Deutschland", latitude: 48.137, longitude: 11.575),
        City(name: "Köln", country: "Deutschland", latitude: 50.938, longitude: 6.96),
        City(name: "Frankfurt", country: "Deutschland", latitude: 50.111, longitude: 8.682),
        City(name: "Stuttgart", country: "Deutschland", latitude: 48.775, longitude: 9.183),
        City(name: "Leipzig", country: "Deutschland", latitude: 51.34, longitude: 12.375),
        City(name: "Wien", country: "Österreich", latitude: 48.208, longitude: 16.373),
        City(name: "Salzburg", country: "Österreich", latitude: 47.811, longitude: 13.055),
        City(name: "Zürich", country: "Schweiz", latitude: 47.377, longitude: 8.541),
        City(name: "Amsterdam", country: "Niederlande", latitude: 52.368, longitude: 4.904),
        City(name: "Paris", country: "Frankreich", latitude: 48.857, longitude: 2.352),
        City(name: "London", country: "Großbritannien", latitude: 51.507, longitude: -0.128),
        City(name: "Kopenhagen", country: "Dänemark", latitude: 55.676, longitude: 12.568),
        City(name: "Stockholm", country: "Schweden", latitude: 59.329, longitude: 18.069),
        City(name: "Barcelona", country: "Spanien", latitude: 41.385, longitude: 2.173),
        City(name: "Lissabon", country: "Portugal", latitude: 38.722, longitude: -9.139),
        City(name: "Rom", country: "Italien", latitude: 41.903, longitude: 12.496),
        City(name: "Prag", country: "Tschechien", latitude: 50.075, longitude: 14.438),
        City(name: "New York", country: "USA", latitude: 40.713, longitude: -74.006),
        City(name: "San Francisco", country: "USA", latitude: 37.775, longitude: -122.419),
        City(name: "Tokio", country: "Japan", latitude: 35.677, longitude: 139.65),
    ]
}

/// Öffentliches Nutzerprofil — das, was andere sehen.
struct UserProfile: Codable, Equatable, Identifiable {
    let id: String
    var handle: String            // eindeutig, ohne "@"
    var displayName: String
    var city: City
    var bio: String = ""
    /// Profilbild als kleines JPEG (~256px); nil → farbiges Monogramm.
    var photoData: Data? = nil
    var joinedAt: Date
    var provider: AuthProvider

    var handleLabel: String { "@\(handle)" }

    init(id: String, handle: String, displayName: String, city: City,
         bio: String = "", photoData: Data? = nil, joinedAt: Date, provider: AuthProvider) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.city = city
        self.bio = bio
        self.photoData = photoData
        self.joinedAt = joinedAt
        self.provider = provider
    }
}

// MARK: - Presence

/// Momentaufnahme einer laufenden Fokus-Session für die Live-Ansicht.
struct FocusStatus: Codable, Equatable {
    var artworkTitle: String
    var round: Int
    var totalRounds: Int
    /// Enthüllungs-Fortschritt 0…1 zum Meldezeitpunkt.
    var progress: Double
    var startedAt: Date
}

/// Was ein Nutzer gerade tut — Basis für Live-Liste und Karte.
enum Presence: Codable, Equatable {
    case offline
    case online
    case focusing(FocusStatus)
    case paused(FocusStatus)
    case onBreak(FocusStatus)

    var isInSession: Bool {
        switch self {
        case .focusing, .paused, .onBreak: return true
        default: return false
        }
    }
    var focusStatus: FocusStatus? {
        switch self {
        case .focusing(let s), .paused(let s), .onBreak(let s): return s
        default: return nil
        }
    }
    /// Kurzer Status-Text für Listen und Karten-Pins.
    var label: String {
        switch self {
        case .offline:  return "Offline"
        case .online:   return "Online"
        case .focusing: return "Fokussiert"
        case .paused:   return "Pausiert"
        case .onBreak:  return "In der Pause"
        }
    }
}

// MARK: - Freunde & Nachrichten

struct FriendRequest: Codable, Equatable, Identifiable {
    let id: String
    let from: UserProfile
    let sentAt: Date
}

/// Interaktive Kurz-Nachrichten — ein Tipp genügt, um jemanden anzufeuern.
enum Nudge: String, Codable, CaseIterable, Identifiable {
    case applause, fire, target, coffee, star

    var id: String { rawValue }
    var emoji: String {
        switch self {
        case .applause: return "👏"
        case .fire:     return "🔥"
        case .target:   return "🎯"
        case .coffee:   return "☕️"
        case .star:     return "🌟"
        }
    }
    var label: String {
        switch self {
        case .applause: return "Applaus"
        case .fire:     return "Weiter so"
        case .target:   return "Voll im Fokus"
        case .coffee:   return "Pausengruß"
        case .star:     return "Stark"
        }
    }
    /// Der Satz, der als Nachricht ankommt.
    var line: String {
        switch self {
        case .applause: return "Applaus für deinen Fokus!"
        case .fire:     return "Du bist on fire — weiter so!"
        case .target:   return "Voll im Fokus. Zieh's durch!"
        case .coffee:   return "Gönn dir die Pause — du hast sie verdient."
        case .star:     return "Starke Session!"
        }
    }
}

enum MessageKind: Codable, Equatable {
    case text(String)
    case nudge(Nudge)
    /// „Kunstgruß“ — schickt ein bereits enthülltes Werk als kleine Karte.
    case artCard(assetName: String, title: String)
}

struct ChatMessage: Codable, Equatable, Identifiable {
    let id: UUID
    let senderID: String
    let sentAt: Date
    let kind: MessageKind
    var read: Bool = false

    init(senderID: String, kind: MessageKind, sentAt: Date = Date(), read: Bool = false) {
        self.id = UUID()
        self.senderID = senderID
        self.sentAt = sentAt
        self.kind = kind
        self.read = read
    }
}

// MARK: - Community-Feed

/// Kleine Ereignisse, die Live-Ansicht und Karte lebendig machen.
enum CommunityEventKind: Codable, Equatable {
    case sessionStarted
    case sessionCompleted(minutes: Int, artworkTitle: String)
    case achievementEarned(achievementID: String)
    case packUnlocked(packName: String)
}

struct CommunityEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let userID: String
    let date: Date
    let kind: CommunityEventKind

    init(userID: String, kind: CommunityEventKind, date: Date = Date()) {
        self.id = UUID()
        self.userID = userID
        self.date = date
        self.kind = kind
    }
}

// MARK: - Coins

/// Verdienst-Regeln — in Produktion serverseitig validiert (siehe docs/ONLINE.md).
enum CoinRules {
    /// 2 Münzen je 5 Fokus-Minuten (25-Min-Runde → 10 Münzen).
    static func coins(forRoundMinutes minutes: Int) -> Int {
        max(2, (minutes / 5) * 2)
    }
    /// Bonus für einen komplett abgeschlossenen Zyklus.
    static let cycleBonus = 15
    /// Bonus für die erste Runde eines Tages.
    static let firstOfDayBonus = 5
}

struct CoinTransaction: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let amount: Int          // positiv = verdient/gekauft, negativ = ausgegeben
    let reason: String       // "Fokus-Runde", "Zyklus-Bonus", "Paket: …", "Kauf: …"

    init(amount: Int, reason: String, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.amount = amount
        self.reason = reason
    }
}

// MARK: - Achievements

/// Erfolge werden aus den Statistiken abgeleitet — nie separat gespeichert,
/// dadurch für eigene wie fremde Profile identisch berechenbar.
struct Achievement: Identifiable, Equatable {
    let id: String
    let icon: String          // SF Symbol
    let title: String
    let subtitle: String
    let isEarned: (UserStats) -> Bool

    static func == (l: Achievement, r: Achievement) -> Bool { l.id == r.id }

    static let all: [Achievement] = [
        Achievement(id: "first_round", icon: "sparkles",
                    title: "Erster Fokus", subtitle: "Eine Fokus-Runde abgeschlossen",
                    isEarned: { $0.totalRounds >= 1 }),
        Achievement(id: "collector_5", icon: "photo.on.rectangle.angled",
                    title: "Sammler", subtitle: "5 Werke enthüllt",
                    isEarned: { $0.worksUnlocked >= 5 }),
        Achievement(id: "curator_12", icon: "building.columns",
                    title: "Kurator", subtitle: "12 Werke enthüllt",
                    isEarned: { $0.worksUnlocked >= 12 }),
        Achievement(id: "streak_3", icon: "flame",
                    title: "Dranbleiber", subtitle: "3 Tage in Folge fokussiert",
                    isEarned: { $0.bestStreak >= 3 }),
        Achievement(id: "streak_7", icon: "flame.fill",
                    title: "Eiserne Woche", subtitle: "7 Tage in Folge fokussiert",
                    isEarned: { $0.bestStreak >= 7 }),
        Achievement(id: "minutes_300", icon: "clock",
                    title: "Fünf Stunden", subtitle: "300 Minuten Fokus gesammelt",
                    isEarned: { $0.totalMinutes >= 300 }),
        Achievement(id: "minutes_1000", icon: "clock.badge.checkmark",
                    title: "Tiefenarbeit", subtitle: "1000 Minuten Fokus gesammelt",
                    isEarned: { $0.totalMinutes >= 1000 }),
        Achievement(id: "early_bird", icon: "sunrise",
                    title: "Frühaufsteher", subtitle: "5 Runden vor 8 Uhr",
                    isEarned: { $0.earlyRounds >= 5 }),
        Achievement(id: "night_owl", icon: "moon.stars",
                    title: "Nachteule", subtitle: "5 Runden nach 22 Uhr",
                    isEarned: { $0.lateRounds >= 5 }),
        Achievement(id: "rounds_100", icon: "100.circle",
                    title: "Hundert Runden", subtitle: "100 Fokus-Runden abgeschlossen",
                    isEarned: { $0.totalRounds >= 100 }),
    ]

    static func earned(by stats: UserStats) -> [Achievement] {
        all.filter { $0.isEarned(stats) }
    }
    static func byID(_ id: String) -> Achievement? {
        all.first { $0.id == id }
    }
}
