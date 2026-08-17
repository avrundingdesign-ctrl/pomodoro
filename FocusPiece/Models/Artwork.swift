import Foundation

/// What a cycle has to be for a work to fall.
///
/// Deliberately only the *shape* of a session — rounds and minutes per round.
/// Streaks and cumulative totals were considered and dropped: a requirement the
/// user can read off a tile and act on the same afternoon is the one that makes
/// a locked work feel like a task rather than a wait.
struct ArtworkRequirement: Equatable {
    var rounds: Int
    var minutesPerRound: Int

    var totalMinutes: Int { rounds * minutesPerRound }

    /// "At least as hard", not equal: someone who sat through 4×45 has cleared
    /// 4×25 several times over. Demanding an exact match would punish the
    /// longer session and be impossible to explain on a tile.
    func satisfied(byRounds r: Int, minutesPerRound m: Int) -> Bool {
        r >= rounds && m >= minutesPerRound
    }

    /// Cheap total order for "which locked work is the easiest left" — minutes
    /// first, then rounds, so 1×45 sorts above 3×15 at equal total.
    var difficulty: Int { totalMinutes * 100 + minutesPerRound }
}

/// A single public-domain artwork in the collection.
/// Images are bundled JPGs (see Scripts/fetch_artworks.sh); `assetName` is the
/// bundle resource base name. When the file is missing the UI shows a graceful
/// placeholder so the app still runs.
///
/// The text fields are resolved from the string catalog when the catalogue is
/// built, so the whole collection speaks the device language. That is also why
/// `Artwork` is deliberately **not** `Codable`: only `ArtworkProgress` is
/// persisted, and the wording always comes from the current translation.
struct Artwork: Identifiable, Equatable {
    let id: String
    let title: String
    /// Painter's name. Usually identical in every language, but the field is
    /// translated anyway — "Pieter Bruegel d. Ä." is "the Elder" in English.
    let artist: String
    let year: String
    let assetName: String        // e.g. "Almond_blossom" (bundled <assetName>.jpg)
    let collectionTag: String    // museal "Sammlung" tag, shown in detail
    let blurb: String            // short description for the detail screen
    /// The set this work belongs to (see ArtworkCatalog); the original eight
    /// works form the free "klassiker" pack.
    var packID: String = "klassiker"
    /// The cycle that reveals this work. Not `Codable` and never persisted, for
    /// the same reason the texts are not: it belongs to the catalogue, so
    /// retuning the ladder in a later version reaches every existing
    /// collection without a migration.
    var requirement = ArtworkRequirement(rounds: 1, minutesPerRound: 25)

    // Mutable progress state
    var unlocked: Bool = false
    var unlockedDate: Date? = nil
    var sessionMinutes: Int? = nil

    /// "Vincent van Gogh · 1890"
    var attribution: String { "\(artist) · \(year)" }

    /// The persistable part of this work.
    var progress: ArtworkProgress {
        ArtworkProgress(id: id, unlocked: unlocked,
                        unlockedDate: unlockedDate, sessionMinutes: sessionMinutes)
    }

    /// A catalogue work with the user's progress applied.
    func applying(_ p: ArtworkProgress?) -> Artwork {
        guard let p else { return self }
        var copy = self
        copy.unlocked = p.unlocked
        copy.unlockedDate = p.unlockedDate
        copy.sessionMinutes = p.sessionMinutes
        return copy
    }
}

/// What a session earned for one work — the only artwork state that is stored.
///
/// Collections written before the texts were localized persisted the whole
/// `Artwork` (German title, blurb, …). Those keys are a superset of these, so
/// old payloads decode straight into this type and the wording is simply taken
/// from the catalogue again.
struct ArtworkProgress: Codable, Equatable {
    let id: String
    var unlocked: Bool = false
    var unlockedDate: Date? = nil
    var sessionMinutes: Int? = nil

    init(id: String, unlocked: Bool = false,
         unlockedDate: Date? = nil, sessionMinutes: Int? = nil) {
        self.id = id
        self.unlocked = unlocked
        self.unlockedDate = unlockedDate
        self.sessionMinutes = sessionMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        unlocked = try c.decodeIfPresent(Bool.self, forKey: .unlocked) ?? false
        unlockedDate = try c.decodeIfPresent(Date.self, forKey: .unlockedDate)
        sessionMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionMinutes)
    }
}
