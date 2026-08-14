import Foundation

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
